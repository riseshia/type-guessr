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

  # Run claude and capture session_id for tool usage extraction
  cd "$PROJECT_DIR"
  env -u CLAUDECODE claude "${extra_args[@]}" "$task_prompt" > "$result_file" 2>/dev/null || true

  # Extract tool usage from session JSONL
  if [[ -f "$result_file" ]] && ! $DRY_RUN; then
    local session_id
    session_id=$(python3 -c "import json; print(json.load(open('$result_file')).get('session_id',''))" 2>/dev/null || echo "")
    if [[ -n "$session_id" ]]; then
      local session_jsonl
      session_jsonl=$(find ~/.claude/projects -name "${session_id}.jsonl" 2>/dev/null | head -1)
      if [[ -n "$session_jsonl" && -f "$session_jsonl" ]]; then
        # Extract tool usage counts and save alongside result
        python3 "$SCRIPT_DIR/extract_tools.py" "$session_jsonl" > "${result_file%.json}_tools.json" 2>/dev/null || true
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
  python3 -c "
import json, sys
try:
    d = json.load(open('$result_file'))
    mu = d.get('modelUsage', {})
    first_model = list(mu.values())[0] if mu else {}
    print(json.dumps({
        'success': not d.get('is_error', True),
        'duration_ms': d.get('duration_ms', 0),
        'num_turns': d.get('num_turns', 0),
        'total_cost_usd': d.get('total_cost_usd', 0),
        'input_tokens': first_model.get('inputTokens', 0),
        'output_tokens': first_model.get('outputTokens', 0),
        'cache_read': first_model.get('cacheReadInputTokens', 0),
        'cache_creation': first_model.get('cacheCreationInputTokens', 0),
        'result_length': len(d.get('result', '')),
        'stop_reason': d.get('stop_reason', 'unknown'),
    }, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null
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
        cost=$(python3 -c "import json; d=json.load(open('$result_file')); print(f\"\${d.get('total_cost_usd', 0):.4f}\")" 2>/dev/null || echo "?")
        duration=$(python3 -c "import json; d=json.load(open('$result_file')); print(f\"{d.get('duration_ms', 0)/1000:.1f}s\")" 2>/dev/null || echo "?")
        turns=$(python3 -c "import json; d=json.load(open('$result_file')); print(d.get('num_turns', '?'))" 2>/dev/null || echo "?")
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
echo "task,condition,trial,success,duration_ms,num_turns,total_cost_usd,input_tokens,output_tokens,cache_read,cache_creation,result_length,stop_reason,total_tool_calls,standard_calls,lsp_calls,mcp_calls,lsp_ratio,mcp_ratio,first_tool,tool_sequence" > "$SUMMARY_CSV"

for result_file in "$RESULTS_DIR"/*.json; do
  [[ -f "$result_file" ]] || continue
  basename_noext=$(basename "$result_file" .json)

  # Skip _tools.json files
  [[ "$basename_noext" == *_tools ]] && continue

  # Parse: task_condition_tN
  task_id=$(echo "$basename_noext" | sed 's/_[ABC]_P[01]_t[0-9]*$//')
  condition=$(echo "$basename_noext" | grep -oP '[ABC]_P[01]')
  trial=$(echo "$basename_noext" | grep -oP 't\K[0-9]+$')

  tools_file="${result_file%.json}_tools.json"

  python3 -c "
import json, sys
try:
    d = json.load(open('$result_file'))
    mu = d.get('modelUsage', {})
    fm = list(mu.values())[0] if mu else {}

    # Tool usage data
    t = {}
    try:
        t = json.load(open('$tools_file'))
    except:
        pass

    cats = t.get('categories', {})
    seq = t.get('tool_sequence', [])
    seq_str = ';'.join(seq) if seq else ''

    fields = [
        '$task_id', '$condition', '$trial',
        not d.get('is_error', True),
        d.get('duration_ms', 0),
        d.get('num_turns', 0),
        round(d.get('total_cost_usd', 0), 6),
        fm.get('inputTokens', 0),
        fm.get('outputTokens', 0),
        fm.get('cacheReadInputTokens', 0),
        fm.get('cacheCreationInputTokens', 0),
        len(d.get('result', '')),
        d.get('stop_reason', 'unknown'),
        t.get('total_tool_calls', 0),
        cats.get('standard', 0),
        cats.get('lsp', 0),
        cats.get('type_guessr', 0),
        round(t.get('lsp_ratio', 0), 3),
        round(t.get('mcp_ratio', 0), 3),
        t.get('first_tool', ''),
        seq_str,
    ]
    print(','.join(map(str, fields)))
except Exception as e:
    print(f'$task_id,$condition,$trial,False,0,0,0,0,0,0,0,0,error,0,0,0,0,0,0,,')
" >> "$SUMMARY_CSV" 2>/dev/null
done

echo "Summary CSV: $SUMMARY_CSV"
