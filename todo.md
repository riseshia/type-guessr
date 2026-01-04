# TypeGuessr TODO

## Current Bugs (2026-01-04)

### 1. File Reindexing Broken on Save

**Symptom:** After saving a file, type inference shows `untyped` for everything.

**Root Cause Analysis:**
- `workspace_did_change_watched_files` calls `reindex_file`
- `reindex_file` was trying to get document from `@global_state.index[key]`
- But `RubyIndexer` doesn't store documents, it stores index entries
- Changed to read file directly and call `index_source`, but still broken
- Need to investigate: URI → file_path conversion may be wrong

**Affected Files:**
- `lib/ruby_lsp/type_guessr/addon.rb:114-124` - `reindex_file` method

**Status:** Investigating

---

### 2. Hash Mixed Key Type Widening

**Symptom:**
```ruby
bb = { a: "1" }
bb[:e] = "a"
bb["f"] = "a"  # Should be Hash[Symbol | String, String], but shows wrong type
```

**Root Cause Analysis:**
- Core logic works correctly (verified with debug script)
- Integration layer (LSP) doesn't show correct type
- Likely related to Bug #1 (reindexing broken)

**Affected Files:**
- `lib/type_guessr/core/converter/prism_converter.rb:381-423` - `widen_to_hash_type`

**Status:** Core fixed, LSP integration broken (depends on Bug #1)

---

### 3. Block Parameter Type Inference

**Symptom:**
```ruby
a = [1, 2, 3]
b = a.map do |num|
  num * 2
end
# a, b, num all show as untyped
```

**Root Cause Analysis:**
- Core logic works correctly (verified with debug script)
- `index_file` was missing Context and `index_node_recursively`
- Fixed to match `index_source` behavior
- But still broken due to Bug #1 (reindexing broken)

**Affected Files:**
- `lib/ruby_lsp/type_guessr/runtime_adapter.rb:30-57` - `index_file`

**Status:** Core fixed, LSP integration broken (depends on Bug #1)

---

### 4. Stale Data After Incremental Update

**Symptom:** After file save, old indexed data persists and causes wrong inference.

**Root Cause Analysis:**
- Related to Bug #1
- `remove_file` may not be clearing data correctly
- Or file_path mismatch between add and remove operations

**Status:** Investigating (part of Bug #1)

---

## Investigation Notes

### URI → file_path Conversion

Need to verify:
1. What format is `uri` in `reindex_file`? (URI object? String?)
2. Does `uri.path` return correct path?
3. Does `index_source` extract same file_path format as initial indexing?

### Key Insight

Tests pass because they use `index_source` directly with known URI format.
Real LSP uses different flow:
1. Initial indexing: `start_indexing` → `traverse_file` (reads from disk)
2. File change: `workspace_did_change_watched_files` → `reindex_file` → `index_source`

The file_path format may differ between these two paths.
