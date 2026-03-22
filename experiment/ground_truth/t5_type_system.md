# T5: Type System Catalog - Ground Truth

**File:** `lib/type_guessr/core/types.rb`

## Base Class: Type

All types inherit from `Type`. Key interface:
- `substitute(substitutions)` → apply type variable substitutions, returns new Type or self
- `type_variable_substitutions` → returns Hash{Symbol => Type} for this type's type params
- `rbs_class_name` → returns String class name for RBS lookup, or nil
- `eql?/hash` → structural equality
- `to_s` → human-readable representation

## Type Classes (13 total)

### 1. Unknown (Singleton)
- **Attributes:** none (Singleton)
- **substitute:** returns self
- **to_s:** `"untyped"`
- **Produced by:** Resolver when inference fails (circular ref, max depth, unknown node, etc.)

### 2. Unguessed (Singleton)
- **Attributes:** none (Singleton)
- **to_s:** `"unguessed"`
- **Produced by:** Gem cache for methods not yet inferred (lazy inference)

### 3. ClassInstance
- **Attributes:** name (String), type_params (Hash{Symbol => Type}|nil)
- **substitute:** substitutes type_params values recursively
- **type_variable_substitutions:** returns type_params or {}
- **rbs_class_name:** returns name
- **Factory:** `ClassInstance.for(name, type_params)` with caching (CACHE, GENERIC_CACHE)
- **to_s:** `"ClassName"` or `"ClassName[Param]"`; special: NilClass→"nil", TrueClass→"true", FalseClass→"false"
- **Produced by:** infer_call (.new → ClassInstance), infer_literal (String, Integer, etc.), infer_self, duck typing

### 4. SingletonType
- **Attributes:** name (String)
- **substitute:** returns self
- **rbs_class_name:** returns name
- **to_s:** `"singleton(ClassName)"`
- **Produced by:** infer_constant (class/module references), infer_self with singleton=true

### 5. Union
- **Attributes:** types (Array<Type>)
- **substitute:** substitutes all member types
- **Normalization:** flattens nested Unions, deduplicates, simplifies if Unknown present, cutoff at 10
- **to_s:** `"Type1 | Type2"`, or `"bool"` for TrueClass|FalseClass, or `"?Type"` for Type|NilClass
- **Produced by:** infer_merge (branch convergence), infer_or (mixed case), classes_to_type (multiple candidates)

### 6. ArrayType
- **Attributes:** element_type (Type, default Unknown)
- **substitute:** substitutes element_type
- **type_variable_substitutions:** `{ Elem: element_type }`
- **rbs_class_name:** `"Array"`
- **to_s:** `"Array[ElementType]"`
- **Produced by:** infer_literal (array literals)

### 7. TupleType
- **Attributes:** element_types (Array<Type>)
- **MAX_ELEMENTS:** 8 (exceeding → widens to ArrayType)
- **substitute:** substitutes each element type
- **type_variable_substitutions:** `{ Elem: Union of unique element types }`
- **rbs_class_name:** `"Array"`
- **to_s:** `"[Type1, Type2, ...]"`
- **Produced by:** infer_literal (small mixed-type array literals)

### 8. HashType
- **Attributes:** key_type (Type), value_type (Type)
- **substitute:** substitutes key_type and value_type
- **type_variable_substitutions:** `{ K: key_type, V: value_type }`
- **rbs_class_name:** `"Hash"`
- **to_s:** `"Hash[KeyType, ValueType]"`
- **Produced by:** HashShape widening, infer_literal (hash with non-symbol keys)

### 9. RangeType
- **Attributes:** element_type (Type, default Unknown)
- **substitute:** substitutes element_type
- **type_variable_substitutions:** `{ Elem: element_type }`
- **rbs_class_name:** `"Range"`
- **to_s:** `"Range[ElementType]"`
- **Produced by:** infer_literal (range literals like `1..10`)

### 10. HashShape
- **Attributes:** fields (Hash{Symbol => Type})
- **max_fields:** 15 (exceeding → widens to HashType)
- **substitute:** substitutes all field values
- **type_variable_substitutions:** `{ K: Symbol, V: Union of field value types }`
- **rbs_class_name:** `"Hash"`
- **to_s:** `"{ key: Type, ... }"`
- **merge_field:** creates new HashShape with added field
- **Produced by:** infer_literal (hash with symbol keys)

### 11. TypeVariable
- **Attributes:** name (Symbol)
- **substitute:** `substitutions[name] || self`
- **to_s:** name as string
- **Produced by:** RBS parsing (type parameters like Elem, K, V, U)

### 12. SelfType (Singleton)
- **Attributes:** none (Singleton)
- **substitute:** `substitutions[:self] || self`
- **to_s:** `"self"`
- **Produced by:** RBS parsing (methods returning self)

### 13. ForwardingArgs (Singleton)
- **Attributes:** none (Singleton)
- **to_s:** `"..."`
- **Produced by:** converter for forwarding parameters

## Structural Types (not Type subclasses)

### ParamSignature (Data.define)
- **Fields:** name (Symbol), kind (Symbol), type (Type)
- **Purpose:** Parameter in a MethodSignature

### MethodSignature (Type subclass)
- **Attributes:** params (Array<ParamSignature>), return_type (Type)
- **substitute:** substitutes params and return_type
- **to_s:** `"(param_list) -> return_type"`
- **Produced by:** SignatureBuilder from DefNode
