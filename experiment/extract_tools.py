#!/usr/bin/env python3
"""Extract tool usage from a Claude Code session JSONL file."""

import json
import sys
from collections import Counter, defaultdict


def extract_tool_usage(jsonl_path: str) -> dict:
    tool_calls = []
    tool_counts = Counter()
    tool_categories = defaultdict(int)

    with open(jsonl_path) as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue

            if d.get("type") != "assistant":
                continue

            content = d.get("message", {}).get("content", [])
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") != "tool_use":
                    continue

                name = block.get("name", "unknown")
                tool_calls.append(name)
                tool_counts[name] += 1

                # Categorize
                if name.startswith("lsp_"):
                    tool_categories["lsp"] += 1
                elif name.startswith("mcp__type"):
                    tool_categories["type_guessr"] += 1
                elif name in ("Bash", "Read", "Grep", "Glob", "Write", "Edit"):
                    tool_categories["standard"] += 1
                else:
                    tool_categories["other"] += 1

    total = len(tool_calls)
    return {
        "total_tool_calls": total,
        "tool_counts": dict(tool_counts.most_common()),
        "tool_sequence": tool_calls,
        "categories": dict(tool_categories),
        "lsp_ratio": tool_categories["lsp"] / total if total > 0 else 0,
        "mcp_ratio": tool_categories["type_guessr"] / total if total > 0 else 0,
        "standard_ratio": tool_categories["standard"] / total if total > 0 else 0,
        "first_tool": tool_calls[0] if tool_calls else None,
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <session.jsonl>", file=sys.stderr)
        sys.exit(1)

    result = extract_tool_usage(sys.argv[1])
    print(json.dumps(result, indent=2))
