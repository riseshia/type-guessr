---
description: Evaluate TypeGuessr type inference quality on its own codebase
allowed-tools: mcp__type-guessr__infer_type, mcp__type-guessr__get_method_signature, mcp__type-guessr__search_methods, Read, Glob, Grep, Edit
---

## Context

Self-evaluation of TypeGuessr's type inference quality. Uses MCP tools to test inference on the TypeGuessr codebase itself, identifying incorrect inferences, missed opportunities, and Unknown types.

## Your task

Evaluate type inference quality and update `todo.md` with findings.

### Step 1: Collect Key Methods

Use `search_methods` to gather project method definitions from both layers:

1. **Core layer** (`lib/type_guessr/core/`):
   - Search for methods in key classes: `Resolver`, `PrismConverter`, `SignatureRegistry`, `MethodRegistry`, `VariableRegistry`, `TypeSimplifier`, `SignatureBuilder`
2. **Integration layer** (`lib/ruby_lsp/type_guessr/`):
   - Search for methods in: `RuntimeAdapter`, `Hover`, `GraphBuilder`, `TypeInferrer`

Example queries:
```
search_methods("Resolver#")
search_methods("PrismConverter#")
search_methods("RuntimeAdapter#")
```

### Step 2: Evaluate Method Signatures

For each key method found in Step 1:

1. Call `get_method_signature` to retrieve the inferred signature
2. Classify each result:
   - **Complete**: All parameter types and return type are known
   - **Partial**: Some types are Unknown
   - **Missing**: No signature available

Track methods with Unknown types - these are inference improvement candidates.

### Step 3: Point-wise Type Inference Tests

For critical files, test `infer_type` at specific locations. Focus on:

1. **Method parameters** - Can we infer the type of parameters from usage?
2. **Local variables** - Are assignment types correctly propagated?
3. **Method calls** - Do we resolve return types properly?
4. **Instance variables** - Are @ivar types tracked correctly?

Use `Read` to examine source files and identify interesting test points (lines with assignments, method calls, etc.), then call `infer_type` with the file path, line, and column.

Classify results into 3 categories:
- ✅ **Correct**: Inferred type matches the expected type
- ❌ **Wrong**: Inferred type is clearly incorrect
- ⚠️ **Unknown**: Returns Unknown or errors (missed inference opportunity)

### Step 4: Summarize and Update todo.md

**Report format:**

```
## Self-Eval Report

### Method Signature Coverage
- Total methods evaluated: N
- Complete signatures: N (X%)
- Partial (has Unknown): N (X%)
- Missing: N (X%)

### Point-wise Inference
- Total points tested: N
- ✅ Correct: N
- ❌ Wrong: N
- ⚠️ Unknown: N

### Notable Findings
1. [Specific finding with file:line reference]
2. ...

### Improvement Candidates
- [Prioritized list of inference gaps]
```

**Update `todo.md`:**
1. Read existing `todo.md` to check for duplicates
2. Add new findings under appropriate priority sections
3. Each item should reference the specific method/location
4. Skip items that overlap with existing entries

## Tips

- Start with a broad `search_methods("*")` to understand the scope, then drill into specific classes
- Focus `infer_type` tests on non-trivial code (skip simple literals and constructors)
- When testing `infer_type`, check both the receiver and arguments of method calls
- Compare `get_method_signature` results against the actual code to verify correctness
- Prioritize findings by impact: methods called frequently matter more than rarely-used helpers
