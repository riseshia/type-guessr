# TypeGuessr 아키텍처 재설계 v3

## 핵심 설계 원칙

1. **Prism 격리**: 추론 내부에서 Prism AST 참조 금지 (경계에서만 변환)
2. **RBS 격리**: RBS 타입을 내부 타입 시스템으로 즉시 변환
3. **단방향 그래프 IR**: Chain을 배열에서 그래프 구조로 변경
4. **위치 기반 인덱스**: (file, line, column) → IR 노드 매핑
5. **추론 근거 추적**: 타입 + 이유(reason) 함께 반환
6. **코드 출처 구분**: Gem vs Project 코드

---

## IR 그래프 구조

### 기존 Chain (배열)
```ruby
# 문제: 중간 위치에서 시작하면 역방향 탐색 필요
[Variable(:user), Call(:profile), Call(:name)]
```

### 새로운 IR (단방향 그래프)
```ruby
# user.profile.name
CallNode.new(
  method: :name,
  loc: Loc.new(line: 1, col: 13..17),
  receiver: CallNode.new(
    method: :profile,
    loc: Loc.new(line: 1, col: 5..12),
    receiver: VariableNode.new(
      name: :user,
      loc: Loc.new(line: 1, col: 0..4)
    )
  )
)
```

**장점:**
- 호버 위치에서 노드를 찾으면 `node.receiver`로 직접 접근
- 부모 정보 없이도 타입 추론 가능
- Prism AST 구조와 유사하지만 타입 추론에 필요한 정보만 유지

---

## IR 노드 타입

```ruby
module TypeGuessr::Core::IR
  # 위치 정보
  Loc = Data.define(:line, :col_range)  # col_range: Range (start..end)

  # 표현식 노드 (Expr)
  class Expr
    attr_reader :loc
  end

  # 리터럴: "hello", 123, [], {}
  LiteralNode = Data.define(:type, :loc)  # type: Types::Type

  # 변수 참조: user, @name, @@count
  VariableNode = Data.define(:name, :kind, :loc)  # kind: :local | :instance | :class

  # 상수 참조: User, Foo::Bar
  ConstantNode = Data.define(:name, :loc)

  # 메서드 호출: receiver.method(args)
  CallNode = Data.define(:receiver, :method, :args, :block, :loc)

  # .new 호출: User.new(args)
  NewCallNode = Data.define(:class_name, :args, :loc)

  # 조건: if cond then ... else ... end
  IfNode = Data.define(:condition, :then_expr, :else_expr, :loc)

  # OR: a || b
  OrNode = Data.define(:left, :right, :loc)

  # AND: a && b
  AndNode = Data.define(:left, :right, :loc)

  # 문장 노드 (Stmt)

  # 할당: x = expr
  AssignNode = Data.define(:target, :value, :loc)  # target: VariableNode

  # 메서드 정의
  DefNode = Data.define(:name, :params, :body, :loc)  # body: [Stmt]

  # 클래스/모듈 정의
  ClassNode = Data.define(:name, :superclass, :body, :loc)
  ModuleNode = Data.define(:name, :body, :loc)
end
```

---

## 위치 기반 인덱스

### LocationIndex

```ruby
module TypeGuessr::Core::Index
  class LocationIndex
    # file_path => sorted array of (loc, node) pairs
    @files = {}

    # 인덱싱
    def index(file_path, ir_nodes)
      entries = collect_all_nodes_with_loc(ir_nodes)
      @files[file_path] = entries.sort_by { |e| [e.loc.line, e.loc.col_range.begin] }
    end

    # 조회: O(log n) binary search
    def find(file_path, line, column)
      entries = @files[file_path]
      return nil unless entries

      # line, column을 포함하는 가장 specific한 노드 찾기
      candidates = entries.select do |entry|
        entry.loc.line == line && entry.loc.col_range.cover?(column)
      end

      # 가장 좁은 범위의 노드 반환 (innermost)
      candidates.min_by { |e| e.loc.col_range.size }
    end
  end
end
```

### 호버 흐름

```
LSP Event (file, line, column)
    │
    ▼
LocationIndex.find(file, line, column)
    │
    ▼
IR Node (CallNode, VariableNode, etc.)
    │
    ▼
Inference (IR 노드만 사용, Prism 참조 없음)
    │
    ▼
Result (type, reason, source)
```

---

## Prism 격리

### 경계 레이어: PrismConverter

```ruby
module TypeGuessr::Core
  class PrismConverter
    # Prism AST → IR 변환 (파싱 시점에 한 번만)
    def convert(prism_node)
      case prism_node
      when Prism::LocalVariableReadNode
        IR::VariableNode.new(
          name: prism_node.name,
          kind: :local,
          loc: convert_loc(prism_node.location)
        )
      when Prism::CallNode
        IR::CallNode.new(
          receiver: prism_node.receiver ? convert(prism_node.receiver) : nil,
          method: prism_node.name,
          args: convert_args(prism_node.arguments),
          block: convert_block(prism_node.block),
          loc: convert_loc(prism_node.location)
        )
      # ... 기타 노드 타입
      end
    end

    private

    def convert_loc(prism_loc)
      IR::Loc.new(
        line: prism_loc.start_line,
        col_range: prism_loc.start_column...prism_loc.end_column
      )
    end
  end
end
```

### Integration Layer에서만 Prism 사용

```ruby
# lib/ruby_lsp/type_guessr/hover/provider.rb
module RubyLsp::TypeGuessr::Hover
  class Provider
    def on_call_node_enter(prism_node)
      # Prism 노드에서 위치만 추출
      loc = prism_node.location

      # IR 노드 조회 (Core는 Prism 모름)
      ir_node = @location_index.find(
        @file_path,
        loc.start_line,
        loc.start_column
      )

      return unless ir_node

      # 추론 (IR 노드만 전달)
      result = @inference_resolver.infer(ir_node, @context)

      # 결과 포맷팅
      @content_builder.build(result)
    end
  end
end
```

---

## RBS 격리

### 경계 레이어: RBSConverter

```ruby
module TypeGuessr::Core
  class RBSConverter
    # RBS::Types → TypeGuessr::Core::Types 변환
    def convert(rbs_type)
      case rbs_type
      when RBS::Types::ClassInstance
        Types::ClassInstance.new(rbs_type.name.to_s)

      when RBS::Types::Union
        types = rbs_type.types.map { |t| convert(t) }
        Types::Union.new(types)

      when RBS::Types::Optional
        Types::Union.new([convert(rbs_type.type), Types::NilClass.instance])

      when RBS::Types::Tuple
        element_types = rbs_type.types.map { |t| convert(t) }
        Types::ArrayType.new(Types::Union.new(element_types))

      when RBS::Types::Record
        fields = rbs_type.fields.transform_values { |t| convert(t) }
        Types::HashShape.new(fields)

      when RBS::Types::Variable
        # 타입 변수: Elem, K, V 등 → 나중에 치환
        Types::TypeVariable.new(rbs_type.name)

      else
        Types::Unknown.instance
      end
    end
  end
end
```

### RBSProvider 수정

```ruby
module TypeGuessr::Core
  class RBSProvider
    def initialize
      @converter = RBSConverter.new
    end

    # 외부에는 항상 내부 타입만 반환
    def get_method_return_type(class_name, method_name)
      rbs_type = lookup_rbs_type(class_name, method_name)
      return Types::Unknown.instance unless rbs_type

      @converter.convert(rbs_type)  # 즉시 변환
    end

    def get_method_signatures(class_name, method_name)
      rbs_sigs = lookup_rbs_signatures(class_name, method_name)
      rbs_sigs.map { |sig| convert_signature(sig) }
    end

    private

    def convert_signature(rbs_sig)
      # RBS::MethodType → 내부 Signature 구조로 변환
      Signature.new(
        params: convert_params(rbs_sig.type.required_positionals),
        return_type: @converter.convert(rbs_sig.type.return_type),
        block: convert_block_type(rbs_sig.type.block)
      )
    end
  end
end
```

---

## 내부 타입 시스템

```ruby
module TypeGuessr::Core::Types
  class Type
    def ==(other); end
    def to_s; end
  end

  # 기본 타입
  class Unknown < Type; end          # 추론 실패
  class ClassInstance < Type         # User, String, etc.
    attr_reader :name
  end
  class NilClass < Type; end         # nil

  # 컬렉션 타입
  class ArrayType < Type             # Array[String]
    attr_reader :element_type
  end
  class HashShape < Type             # { name: String, age: Integer }
    attr_reader :fields              # Hash[Symbol, Type]
  end
  class HashType < Type              # Hash[String, Integer]
    attr_reader :key_type, :value_type
  end

  # 복합 타입
  class Union < Type                 # String | Integer
    attr_reader :types
  end

  # 타입 변수 (RBS 치환용)
  class TypeVariable < Type          # Elem, K, V
    attr_reader :name
  end

  # 프로시저 타입 (블록용)
  class ProcType < Type
    attr_reader :param_types, :return_type
  end
end
```

---

## 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────────────┐
│                    INTEGRATION LAYER                         │
│  - Prism 노드 수신 (LSP 이벤트)                              │
│  - 위치 정보 추출 후 Core에 전달                             │
│  - Prism 타입 직접 사용 금지                                 │
└─────────────────────────────────────────────────────────────┘
          │ (file, line, column)
          ▼
┌─────────────────────────────────────────────────────────────┐
│                      ADAPTER LAYER                           │
│  - PrismConverter: Prism AST → IR (인덱싱 시점)              │
│  - RBSConverter: RBS Types → Internal Types                  │
│  - LocationIndex: (file, line, col) → IR Node                │
└─────────────────────────────────────────────────────────────┘
          │ (IR Node)
          ▼
┌─────────────────────────────────────────────────────────────┐
│                       CORE LAYER                             │
│  - Prism 참조 없음                                           │
│  - RBS 타입 직접 사용 없음                                   │
│  - 순수하게 IR 노드와 내부 타입만 사용                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 데이터 흐름

### 인덱싱 (파싱 시점)

```
Source File
    │
    ▼
Prism.parse()
    │
    ▼
PrismConverter.convert()     ← Prism 경계
    │
    ▼
IR Nodes (그래프 구조)
    │
    ├──▶ LocationIndex.index()    (위치 → 노드)
    ├──▶ ScopeIndex.index()       (스코프 → 변수들)
    └──▶ MethodIndex.index()      (클래스#메서드 → DefNode)
```

### 호버 (요청 시점)

```
LSP Hover Event
    │
    ▼
Provider.on_*_node_enter(prism_node)
    │
    ▼ (위치만 추출)
LocationIndex.find(file, line, column)
    │
    ▼
IR Node
    │
    ▼
InferenceResolver.infer(ir_node, context)
    │
    ├── ir_node.receiver 탐색
    ├── RBSProvider.get_method_return_type() → 내부 타입
    └── ScopeIndex에서 변수 타입 조회
    │
    ▼
Result(type, reason, source)
    │
    ▼
ContentBuilder.build() → Markdown
```

---

## 디렉토리 구조

```
lib/
├── type_guessr/
│   └── core/
│       ├── ir/                      # IR 노드 정의
│       │   ├── nodes.rb             # 모든 노드 타입
│       │   └── loc.rb               # 위치 정보
│       │
│       ├── types/                   # 내부 타입 시스템
│       │   ├── type.rb              # 베이스
│       │   ├── class_instance.rb
│       │   ├── array_type.rb
│       │   ├── hash_shape.rb
│       │   ├── union.rb
│       │   └── type_variable.rb
│       │
│       ├── index/                   # 인덱스
│       │   ├── location_index.rb    # (file, line, col) → IR Node
│       │   ├── scope_index.rb       # scope → 변수 타입들
│       │   └── method_index.rb      # class#method → DefNode
│       │
│       ├── inference/               # 추론 엔진
│       │   ├── result.rb
│       │   ├── resolver.rb
│       │   └── strategies/
│       │
│       ├── converter/               # 경계 변환기
│       │   ├── prism_converter.rb   # Prism → IR
│       │   └── rbs_converter.rb     # RBS → Types
│       │
│       ├── rbs_provider.rb          # RBS 조회 (내부 타입 반환)
│       └── ...
│
└── ruby_lsp/
    └── type_guessr/
        ├── hover/
        │   └── provider.rb          # Prism 노드 수신, 위치만 사용
        └── ...
```

---

## 코드 출처 구분

(scenario2.md에서 유지)

| 구분 | Gem 코드 | Project 코드 |
|------|----------|--------------|
| **추론 우선순위** | RBS → 소스 → 휴리스틱 | 소스 → RBS → 휴리스틱 |
| **캐싱** | 영구 (gem:version) | 파일별 (file:mtime) |

---

## 추론 근거 추적

(scenario2.md에서 유지)

```ruby
module TypeGuessr::Core::Inference
  class Result
    attr_reader :type,    # Types::Type
                :reason,  # Reason
                :source   # :gem | :project | :stdlib
  end

  class Reason
    attr_reader :strategy,  # "literal" | "rbs" | "call_result" | ...
                :evidence,  # "assigned from User.new"
                :location   # "app/models/user.rb:42"
  end
end
```

---

## 구현 단계

### Phase 1: IR 기반 구축
- [ ] `ir/nodes.rb` - IR 노드 타입 정의
- [ ] `ir/loc.rb` - 위치 정보 구조
- [ ] `converter/prism_converter.rb` - Prism → IR 변환
- [ ] `index/location_index.rb` - 위치 기반 인덱스

### Phase 2: 타입 시스템 정비
- [ ] `types/` 디렉토리 재구성
- [ ] `types/type_variable.rb` 추가 (RBS 치환용)
- [ ] `converter/rbs_converter.rb` - RBS → 내부 타입 변환
- [ ] `rbs_provider.rb` 수정 - 내부 타입만 반환

### Phase 3: 추론 엔진 마이그레이션
- [ ] `inference/resolver.rb` - IR 노드 기반으로 수정
- [ ] 기존 Chain 로직을 IR 그래프 탐색으로 변환
- [ ] FlowAnalyzer 통합

### Phase 4: Integration Layer 수정
- [ ] `hover/provider.rb` - Prism 노드에서 위치만 추출
- [ ] LocationIndex 사용하여 IR 노드 조회
- [ ] Prism 직접 참조 제거

### Phase 5: 레거시 정리
- [ ] 기존 Chain 배열 구조 삭제
- [ ] Prism 직접 참조하던 코드 삭제
- [ ] RBS 타입 직접 사용하던 코드 삭제

### Phase 6: 검증 및 문서화
- [ ] 전체 테스트 통과
- [ ] CLAUDE.md 업데이트

---

## 성공 기준

1. **Prism 격리**: Core layer에서 Prism 참조 0건
2. **RBS 격리**: Core layer에서 RBS::Types 참조 0건
3. **위치 인덱스**: (file, line, col) → IR 노드 조회 동작
4. **IR 그래프**: 메서드 체인에서 중간 위치 호버 지원
5. **추론 근거**: 모든 추론 결과에 reason 포함
6. **테스트 통과**: 기존 테스트 전체 통과
