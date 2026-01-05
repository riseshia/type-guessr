# TypeGuessr TODO

## Future Features

- [ ] Array mutation tracking (`<<`, `push`, etc.)
  - Track type changes when elements are added via mutation methods
  - Conservative approach: downgrade to `Array[untyped]` when mutation detected
  - Advanced approach: infer argument type and compute union type
  - Example: `arr = [1]; arr << bb` → `Array[untyped]` or `Array[Integer | T]`
