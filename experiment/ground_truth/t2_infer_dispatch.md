# T2: Resolver infer_* Dispatch Table - Ground Truth

## infer_node dispatch (resolver.rb lines ~109-148)

| IR Node Type | infer_* Method | Line Range | Return Type Logic |
|---|---|---|---|
| LiteralNode | infer_literal | ~150-152 | Returns `Result.new(node.type, "literal", :literal)` directly from node's type field |
| LocalWriteNode | infer_local_write | ~154-159 | Infers value node, wraps with "assigned from" reason |
| LocalReadNode | infer_local_read | ~161-170 | Infers write_node dependency; if nil, uses duck typing via resolve_called_methods |
| InstanceVariableWriteNode | infer_instance_variable_write | ~172-178 | Infers value node, wraps with "ivar assigned from" reason |
| InstanceVariableReadNode | infer_instance_variable_read | ~180-205 | Looks up write_node via ivar_registry if not linked; falls back to duck typing |
| ClassVariableWriteNode | infer_class_variable_write | ~207-213 | Infers value node, wraps with "cvar assigned from" reason |
| ClassVariableReadNode | infer_class_variable_read | ~215-240 | Looks up write_node via cvar_registry if not linked; falls back to duck typing |
| ParamNode | infer_param | ~242-296 | Complex: tries default_value, duck typing (resolve_called_methods), naming conventions, RBS |
| ConstantNode | infer_constant | ~298-308 | Returns SingletonType for class/module constants |
| CallNode | infer_call | ~310-495 | Most complex: 4 phases (constant receiver, dynamic receiver by type, unknown receiver, no receiver) |
| BlockParamSlot | infer_block_param_slot | ~497-550 | Infers call_node receiver → gets RBS block param types via signature_registry |
| OrNode | infer_or | ~556-579 | Infers both sides; removes falsy types from LHS, unions truthy LHS with RHS |
| MergeNode | infer_merge | ~581-610 | Infers all branches, unions their types |
| DefNode | infer_def | ~612-630 | Infers return_node to get method return type |
| SelfNode | infer_self | ~632-645 | Returns ClassInstance or SingletonType based on singleton flag |
| NarrowNode | infer_narrow | ~647-665 | Infers value, then removes falsy types (truthy narrowing) |
| ReturnNode | infer_return | ~667-675 | Infers value node, wraps with "explicit return" reason |

## Notes

- All infer_* methods are private
- All return `Inference::Result` (type, reason, source)
- infer_call is by far the most complex (~185 lines)
- infer_param has multiple fallback strategies
- infer_block_param_slot depends on receiver type resolution + RBS lookup
