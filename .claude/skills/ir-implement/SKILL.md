# IR Node Implementation

When implementing changes to IR nodes:
1. List ALL spec files that reference the interface
2. Check for shared state between nodes (e.g., LocalReadNode ↔ BlockParamSlot)
3. Update interface, then specs, then implementation
4. Run full test suite before marking complete
