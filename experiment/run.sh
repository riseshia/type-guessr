#!/usr/bin/env bash
# type-guessr experiment runner
# 3 conditions × N tasks × M trials
# Usage: ./experiment/run.sh [--dry-run] [--task TASK_ID] [--condition CONDITION]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESULTS_DIR="$SCRIPT_DIR/results/$(date +%Y%m%d_%H%M%S)"
TASKS_DIR="$SCRIPT_DIR/tasks"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

# Defaults
DRY_RUN=false
FILTER_TASK=""
FILTER_CONDITION=""
TRIALS=1
MAX_BUDGET="0.50"
MODEL="sonnet"

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --task) FILTER_TASK="$2"; shift 2 ;;
    --condition) FILTER_CONDITION="$2"; shift 2 ;;
    --trials) TRIALS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --budget) MAX_BUDGET="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Conditions:
#   A_P0: baseline, no guidance
#   B_P0: LSP enabled, no guidance
#   B_P1: LSP enabled, with guidance
#   C_P0: MCP enabled, no guidance
#   C_P1: MCP enabled, with guidance
CONDITIONS=(A_P0 B_P0 B_P1 C_P0 C_P1)

mkdir -p "$RESULTS_DIR"

# --- Helper functions ---

run_claude() {
  local condition="$1"
  local task_prompt="$2"
  local system_prompt="$3"
  local result_file="$4"
  local extra_args=()

  # Unset CLAUDECODE to allow nested execution
  unset CLAUDECODE 2>/dev/null || true

  # Base args
  extra_args+=(--print)
  extra_args+=(--output-format json)
  extra_args+=(--max-budget-usd "$MAX_BUDGET")
  extra_args+=(--model "$MODEL")
  extra_args+=(--dangerously-skip-permissions)

  # Disable skills to reduce noise
  extra_args+=(--disable-slash-commands)

  # Tool restrictions per condition
  case "$condition" in
    A_P0|A_P1)
      # Baseline: only standard tools, no plugins
      extra_args+=(--setting-sources "")
      extra_args+=(--tools "Bash,Read,Grep,Glob,Write,Edit")
      ;;
    B_P0|B_P1)
      # LSP: standard tools + ruby-lsp plugin
      # Use local settings (which has ruby-lsp plugin installed)
      extra_args+=(--tools "default")
      # Disable MCP servers that might be configured
      extra_args+=(--strict-mcp-config)
      extra_args+=(--mcp-config '{"mcpServers":{}}')
      ;;
    C_P0|C_P1)
      # MCP: standard tools + type-guessr MCP
      extra_args+=(--tools "Bash,Read,Grep,Glob,Write,Edit")
      extra_args+=(--strict-mcp-config)
      extra_args+=(--mcp-config "$SCRIPT_DIR/mcp-type-guessr.json")
      ;;
  esac

  # System prompt (append guidance if P1)
  if [[ -n "$system_prompt" ]]; then
    extra_args+=(--system-prompt "$system_prompt")
  fi

  if $DRY_RUN; then
    echo "[DRY RUN] claude ${extra_args[*]} \"$task_prompt\"" > "$result_file"
    echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":0,"num_turns":0,"result":"dry run","total_cost_usd":0,"usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}' > "$result_file"
    return 0
  fi

  cd "$PROJECT_DIR"

  # LSP warmup: run a sleep prompt first so LSP has time to initialize,
  # then resume the same session for the actual task
  if [[ "$condition" == B_* ]]; then
    local warmup_file="${result_file%.json}_warmup.json"
    env -u CLAUDECODE claude "${extra_args[@]}" \
      "Run: sleep 60. Do nothing else. Just wait." \
      > "$warmup_file" 2>/dev/null || true

    local warmup_session_id
    warmup_session_id=$(ruby -rjson -e "puts JSON.parse(File.read('$warmup_file')).fetch('session_id','')" 2>/dev/null || echo "")

    if [[ -n "$warmup_session_id" ]]; then
      env -u CLAUDECODE claude "${extra_args[@]}" \
        --resume "$warmup_session_id" \
        "$task_prompt" > "$result_file" 2>/dev/null || true
    else
      # Fallback: run without warmup
      env -u CLAUDECODE claude "${extra_args[@]}" "$task_prompt" > "$result_file" 2>/dev/null || true
    fi
  else
    env -u CLAUDECODE claude "${extra_args[@]}" "$task_prompt" > "$result_file" 2>/dev/null || true
  fi

  # Extract tool usage from session JSONL
  if [[ -f "$result_file" ]] && ! $DRY_RUN; then
    local session_id
    session_id=$(ruby -rjson -e "puts JSON.parse(File.read('$result_file')).fetch('session_id','')" 2>/dev/null || echo "")
    if [[ -n "$session_id" ]]; then
      local session_jsonl
      session_jsonl=$(find ~/.claude/projects -name "${session_id}.jsonl" 2>/dev/null | head -1)
      if [[ -n "$session_jsonl" && -f "$session_jsonl" ]]; then
        # Extract tool usage counts and save alongside result
        ruby "$SCRIPT_DIR/extract_tools.rb" "$session_jsonl" > "${result_file%.json}_tools.json" 2>/dev/null || true
      fi
    fi
  fi
}

build_system_prompt() {
  local condition="$1"

  case "$condition" in
    A_P0)
      echo "You are analyzing a Ruby codebase. Use the available tools to answer the question."
      ;;
    B_P0)
      echo "You are analyzing a Ruby codebase. Use the available tools to answer the question."
      ;;
    B_P1)
      cat "$PROMPTS_DIR/lsp_guided.txt"
      ;;
    C_P0)
      echo "You are analyzing a Ruby codebase. Use the available tools to answer the question."
      ;;
    C_P1)
      cat "$PROMPTS_DIR/mcp_guided.txt"
      ;;
  esac
}

# --- Summary extraction ---

summarize_result() {
  local result_file="$1"
  if [[ ! -f "$result_file" ]]; then
    echo "MISSING"
    return
  fi

  # Extract key metrics from JSON
  ruby -rjson -e '
    d = JSON.parse(File.read("'"$result_file"'"))
    mu = d["modelUsage"] || {}
    fm = mu.values.first || {}
    puts JSON.pretty_generate({
      success: !d.fetch("is_error", true),
      duration_ms: d.fetch("duration_ms", 0),
      num_turns: d.fetch("num_turns", 0),
      total_cost_usd: d.fetch("total_cost_usd", 0),
      input_tokens: fm.fetch("inputTokens", 0),
      output_tokens: fm.fetch("outputTokens", 0),
      cache_read: fm.fetch("cacheReadInputTokens", 0),
      cache_creation: fm.fetch("cacheCreationInputTokens", 0),
      result_length: d.fetch("result", "").size,
      stop_reason: d.fetch("stop_reason", "unknown"),
    })
  ' 2>/dev/null
}

# --- Main loop ---

echo "========================================="
echo "type-guessr Experiment Runner"
echo "========================================="
echo "Results dir: $RESULTS_DIR"
echo "Trials: $TRIALS"
echo "Model: $MODEL"
echo "Budget per run: \$$MAX_BUDGET"
echo "Dry run: $DRY_RUN"
echo ""

# Load tasks
TASK_FILES=("$TASKS_DIR"/*.txt)
if [[ ${#TASK_FILES[@]} -eq 0 ]]; then
  echo "ERROR: No task files found in $TASKS_DIR"
  exit 1
fi

TOTAL=0
SUCCESS=0
FAILED=0

for task_file in "${TASK_FILES[@]}"; do
  task_id=$(basename "$task_file" .txt)

  # Filter
  if [[ -n "$FILTER_TASK" && "$task_id" != "$FILTER_TASK" ]]; then
    continue
  fi

  task_prompt=$(cat "$task_file")
  echo "--- Task: $task_id ---"

  for condition in "${CONDITIONS[@]}"; do
    # Filter
    if [[ -n "$FILTER_CONDITION" && "$condition" != "$FILTER_CONDITION" ]]; then
      continue
    fi

    system_prompt=$(build_system_prompt "$condition")

    for trial in $(seq 1 "$TRIALS"); do
      result_file="$RESULTS_DIR/${task_id}_${condition}_t${trial}.json"
      TOTAL=$((TOTAL + 1))

      echo -n "  [$condition] trial $trial ... "

      run_claude "$condition" "$task_prompt" "$system_prompt" "$result_file"

      # Quick summary
      if [[ -f "$result_file" ]]; then
        cost=$(ruby -rjson -e 'd=JSON.parse(File.read("'"$result_file"'")); printf "$%.4f", d.fetch("total_cost_usd", 0)' 2>/dev/null || echo "?")
        duration=$(ruby -rjson -e 'd=JSON.parse(File.read("'"$result_file"'")); printf "%.1fs", d.fetch("duration_ms", 0) / 1000.0' 2>/dev/null || echo "?")
        turns=$(ruby -rjson -e 'd=JSON.parse(File.read("'"$result_file"'")); print d.fetch("num_turns", "?")' 2>/dev/null || echo "?")
        echo "done ($duration, $cost, ${turns} turns)"
        SUCCESS=$((SUCCESS + 1))
      else
        echo "FAILED"
        FAILED=$((FAILED + 1))
      fi
    done
  done
done

echo ""
echo "========================================="
echo "Complete: $SUCCESS/$TOTAL succeeded, $FAILED failed"
echo "Results saved to: $RESULTS_DIR"
echo "========================================="

# Generate summary CSV
SUMMARY_CSV="$RESULTS_DIR/summary.csv"
echo "task,condition,trial,success,duration_ms,duration_api_ms,num_turns,total_cost_usd,input_tokens,output_tokens,cache_read,cache_creation,result_length,stop_reason,total_tool_calls,standard_calls,lsp_calls,mcp_calls,lsp_ratio,mcp_ratio,first_tool,tool_sequence" > "$SUMMARY_CSV"

for result_file in "$RESULTS_DIR"/*.json; do
  [[ -f "$result_file" ]] || continue
  basename_noext=$(basename "$result_file" .json)

  # Skip _tools.json and _warmup.json files
  [[ "$basename_noext" == *_tools ]] && continue
  [[ "$basename_noext" == *_warmup ]] && continue

  # Parse: task_condition_tN
  task_id=$(echo "$basename_noext" | sed 's/_[ABC]_P[01]_t[0-9]*$//')
  condition=$(echo "$basename_noext" | grep -oP '[ABC]_P[01]')
  trial=$(echo "$basename_noext" | grep -oP 't\K[0-9]+$')

  tools_file="${result_file%.json}_tools.json"

  ruby -rjson -e '
    d = JSON.parse(File.read("'"$result_file"'"))
    mu = d["modelUsage"] || {}
    fm = mu.values.first || {}

    t = begin
      JSON.parse(File.read("'"$tools_file"'"))
    rescue
      {}
    end

    cats = t["categories"] || {}
    seq = (t["tool_sequence"] || []).join(";")

    fields = [
      "'"$task_id"'", "'"$condition"'", "'"$trial"'",
      !d.fetch("is_error", true),
      d.fetch("duration_ms", 0),
      d.fetch("duration_api_ms", 0),
      d.fetch("num_turns", 0),
      d.fetch("total_cost_usd", 0).round(6),
      fm.fetch("inputTokens", 0),
      fm.fetch("outputTokens", 0),
      fm.fetch("cacheReadInputTokens", 0),
      fm.fetch("cacheCreationInputTokens", 0),
      d.fetch("result", "").size,
      d.fetch("stop_reason", "unknown"),
      t.fetch("total_tool_calls", 0),
      cats.fetch("standard", 0),
      cats.fetch("lsp", 0),
      cats.fetch("type_guessr", 0),
      t.fetch("lsp_ratio", 0).round(3),
      t.fetch("mcp_ratio", 0).round(3),
      t.fetch("first_tool", ""),
      seq,
    ]
    puts fields.join(",")
  ' >> "$SUMMARY_CSV" 2>/dev/null
done

echo "Summary CSV: $SUMMARY_CSV"
