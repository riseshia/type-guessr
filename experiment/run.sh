#!/usr/bin/env bash
# type-guessr experiment runner
# 3 conditions × N tasks × M trials
#
# Usage:
#   ./experiment/run.sh                          # run all
#   ./experiment/run.sh --dry-run                # preview without running
#   ./experiment/run.sh --task t1_call_chain     # single task
#   ./experiment/run.sh --condition TG_GUIDED    # single condition
#   ./experiment/run.sh --trials 5               # 5 trials per combo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$SCRIPT_DIR/results/runs/${TIMESTAMP}"
ACCUMULATED_DIR="$SCRIPT_DIR/results/accumulated"
TASKS_DIR="$SCRIPT_DIR/tasks"
PROMPTS_DIR="$SCRIPT_DIR/prompts"

# Defaults
DRY_RUN=false
FILTER_TASK=""
FILTER_CONDITION=""
TRIALS=1
MAX_BUDGET=""
MODEL="sonnet"
PARALLEL=3

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --task) FILTER_TASK="$2"; shift 2 ;;
    --condition) FILTER_CONDITION="$2"; shift 2 ;;
    --trials) TRIALS="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --budget) MAX_BUDGET="$2"; shift 2 ;;
    --parallel) PARALLEL="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Conditions:
#   BASE:       standard tools only, no guidance
#   LSP:        standard tools + ruby-lsp plugin, no guidance
#   LSP_GUIDED: standard tools + ruby-lsp plugin, with guidance prompt
#   TG_NATURAL: standard tools + MCP type-guessr, no guidance
#   TG_GUIDED:  standard tools + MCP type-guessr, with guidance prompt
CONDITIONS=(BASE LSP LSP_GUIDED TG_NATURAL TG_GUIDED)

mkdir -p "$RUN_DIR"
mkdir -p "$ACCUMULATED_DIR"

# --- Helper functions ---

run_claude() {
  local condition="$1"
  local task_prompt="$2"
  local system_prompt="$3"
  local result_file="$4"
  local extra_args=()

  # Base args
  extra_args+=(--print)
  extra_args+=(--output-format json)
  if [[ -n "$MAX_BUDGET" ]]; then
    extra_args+=(--max-budget-usd "$MAX_BUDGET")
  fi
  extra_args+=(--model "$MODEL")
  extra_args+=(--dangerously-skip-permissions)
  extra_args+=(--disable-slash-commands)

  # Tool restrictions per condition
  case "$condition" in
    BASE)
      extra_args+=(--setting-sources "")
      extra_args+=(--tools "Bash,Read,Grep,Glob")
      extra_args+=(--strict-mcp-config)
      extra_args+=(--mcp-config '{"mcpServers":{}}')
      ;;
    LSP|LSP_GUIDED)
      # Use default tools (includes ruby-lsp plugin's LSP tool)
      # Keep local settings for plugin access, disable MCP
      extra_args+=(--tools "default")
      extra_args+=(--strict-mcp-config)
      extra_args+=(--mcp-config '{"mcpServers":{}}')
      ;;
    TG_NATURAL|TG_GUIDED)
      extra_args+=(--setting-sources "")
      extra_args+=(--tools "Bash,Read,Grep,Glob")
      extra_args+=(--strict-mcp-config)
      extra_args+=(--mcp-config "$SCRIPT_DIR/mcp-type-guessr.json")
      ;;
  esac

  # System prompt
  if [[ -n "$system_prompt" ]]; then
    extra_args+=(--system-prompt "$system_prompt")
  fi

  # Warmup instruction
  extra_args+=(--append-system-prompt "CRITICAL: You MUST run \`bash experiment/warmup.sh\` as your very first action before doing anything else. This is required for tools to function correctly.")

  if $DRY_RUN; then
    echo '{"type":"result","subtype":"success","is_error":false,"duration_ms":0,"num_turns":0,"result":"dry run","total_cost_usd":0,"session_id":"dry-run","modelUsage":{}}' > "$result_file"
    return 0
  fi

  cd "$PROJECT_DIR"

  # Measure wall clock time
  local start_epoch_ms
  start_epoch_ms=$(date +%s%3N)

  env -u CLAUDECODE claude "${extra_args[@]}" "$task_prompt" > "$result_file" 2>/dev/null || true

  local end_epoch_ms wall_ms
  end_epoch_ms=$(date +%s%3N)
  wall_ms=$((end_epoch_ms - start_epoch_ms))

  # Inject wall_ms into result JSON
  if [[ -f "$result_file" ]]; then
    ruby -rjson -e '
      d = JSON.parse(File.read("'"$result_file"'", encoding: "UTF-8"))
      d["wall_ms"] = '"$wall_ms"'
      File.write("'"$result_file"'", JSON.pretty_generate(d))
    ' 2>/dev/null || true
  fi

  # Extract tool usage from session JSONL
  if [[ -f "$result_file" ]]; then
    local session_id
    session_id=$(ruby -rjson -e "puts JSON.parse(File.read('$result_file', encoding: 'UTF-8')).fetch('session_id','')" 2>/dev/null || echo "")
    if [[ -n "$session_id" ]]; then
      local session_jsonl
      session_jsonl=$(find ~/.claude/projects -name "${session_id}.jsonl" 2>/dev/null | head -1)
      if [[ -n "$session_jsonl" && -f "$session_jsonl" ]]; then
        ruby "$SCRIPT_DIR/extract_tools.rb" "$session_jsonl" > "${result_file%.json}_tools.json" 2>/dev/null || true
      fi
    fi
  fi
}

build_system_prompt() {
  local condition="$1"

  case "$condition" in
    BASE|LSP|TG_NATURAL)
      echo "You are analyzing a Ruby codebase. Use the available tools to answer the question."
      ;;
    LSP_GUIDED)
      cat "$PROMPTS_DIR/lsp_guided.txt"
      ;;
    TG_GUIDED)
      cat "$PROMPTS_DIR/mcp_guided.txt"
      ;;
  esac
}

# --- Main loop ---

echo "========================================="
echo "type-guessr Experiment Runner"
echo "========================================="
echo "Run dir:   $RUN_DIR"
echo "Trials:    $TRIALS"
echo "Model:     $MODEL"
echo "Budget:    ${MAX_BUDGET:+\$${MAX_BUDGET}}${MAX_BUDGET:-unlimited}"
echo "Parallel:  $PARALLEL"
echo "Dry run:   $DRY_RUN"
echo ""

# Load tasks
TASK_FILES=("$TASKS_DIR"/*.txt)
if [[ ${#TASK_FILES[@]} -eq 0 ]]; then
  echo "ERROR: No task files found in $TASKS_DIR"
  exit 1
fi

# Collect all jobs
declare -a JOB_SPECS=()
TOTAL=0

for task_file in "${TASK_FILES[@]}"; do
  task_id=$(basename "$task_file" .txt)
  [[ -n "$FILTER_TASK" && "$task_id" != "$FILTER_TASK" ]] && continue

  for condition in "${CONDITIONS[@]}"; do
    [[ -n "$FILTER_CONDITION" && "$condition" != "$FILTER_CONDITION" ]] && continue

    for trial in $(seq 1 "$TRIALS"); do
      JOB_SPECS+=("${task_id}|${condition}|${trial}")
      TOTAL=$((TOTAL + 1))
    done
  done
done

echo "Total runs: $TOTAL (parallel=$PARALLEL)"
echo ""

# Run jobs with concurrency limit
SUCCESS=0
FAILED=0
declare -A PIDS=()
declare -a PENDING_SPECS=("${JOB_SPECS[@]}")
declare -a ACTIVE_SPECS=()

report_result() {
  local spec="$1"
  IFS='|' read -r task_id condition trial <<< "$spec"
  local result_file="$RUN_DIR/${task_id}_${condition}_t${trial}.json"

  if [[ -f "$result_file" ]]; then
    cost=$(ruby -rjson -e 'd=JSON.parse(File.read("'"$result_file"'", encoding: "UTF-8")); printf "$%.4f", d.fetch("total_cost_usd", 0)' 2>/dev/null || echo "?")
    duration=$(ruby -rjson -e 'd=JSON.parse(File.read("'"$result_file"'", encoding: "UTF-8")); printf "%.1fs", d.fetch("wall_ms", d.fetch("duration_ms", 0)) / 1000.0' 2>/dev/null || echo "?")
    turns=$(ruby -rjson -e 'd=JSON.parse(File.read("'"$result_file"'", encoding: "UTF-8")); print d.fetch("num_turns", "?")' 2>/dev/null || echo "?")
    echo "  [${condition}] ${task_id} t${trial} ... done ($duration, $cost, ${turns} turns)"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  [${condition}] ${task_id} t${trial} ... FAILED"
    FAILED=$((FAILED + 1))
  fi
}

launch_job() {
  local spec="$1"
  IFS='|' read -r task_id condition trial <<< "$spec"
  local task_file="$TASKS_DIR/${task_id}.txt"
  local task_prompt
  task_prompt=$(cat "$task_file")
  local system_prompt
  system_prompt=$(build_system_prompt "$condition")
  local result_file="$RUN_DIR/${task_id}_${condition}_t${trial}.json"

  echo "  [${condition}] ${task_id} t${trial} ... started"

  (
    run_claude "$condition" "$task_prompt" "$system_prompt" "$result_file"
  ) &
  PIDS["$spec"]=$!
  ACTIVE_SPECS+=("$spec")
}

# Main scheduling loop
idx=0
while [[ $idx -lt ${#PENDING_SPECS[@]} || ${#ACTIVE_SPECS[@]} -gt 0 ]]; do
  # Launch jobs up to PARALLEL limit
  while [[ $idx -lt ${#PENDING_SPECS[@]} && ${#ACTIVE_SPECS[@]} -lt $PARALLEL ]]; do
    launch_job "${PENDING_SPECS[$idx]}"
    idx=$((idx + 1))
  done

  # Wait for any one job to finish
  if [[ ${#ACTIVE_SPECS[@]} -gt 0 ]]; then
    wait -n 2>/dev/null || true

    # Check which jobs finished
    local_remaining=()
    for spec in "${ACTIVE_SPECS[@]}"; do
      pid=${PIDS["$spec"]}
      if ! kill -0 "$pid" 2>/dev/null; then
        wait "$pid" 2>/dev/null || true
        report_result "$spec"
        unset "PIDS[$spec]"
      else
        local_remaining+=("$spec")
      fi
    done
    ACTIVE_SPECS=("${local_remaining[@]}")
  fi
done

echo ""
echo "========================================="
echo "Complete: $SUCCESS/$TOTAL succeeded, $FAILED failed"
echo "========================================="

# --- Generate per-run summary CSV ---

RUN_CSV="$RUN_DIR/summary.csv"
CSV_HEADER="run_id,task,condition,trial,success,wall_ms,duration_api_ms,num_turns,total_cost_usd,input_tokens,output_tokens,cache_read,cache_creation,result_length,stop_reason,total_tool_calls,standard_calls,lsp_calls,mcp_calls,lsp_ratio,mcp_ratio,first_tool,tool_sequence"
echo "$CSV_HEADER" > "$RUN_CSV"

for result_file in "$RUN_DIR"/*.json; do
  [[ -f "$result_file" ]] || continue
  basename_noext=$(basename "$result_file" .json)
  [[ "$basename_noext" == *_tools ]] && continue
  [[ "$basename_noext" == *_answer ]] && continue

  task_id=$(echo "$basename_noext" | sed 's/_\(BASE\|LSP_GUIDED\|LSP\|TG_NATURAL\|TG_GUIDED\)_t[0-9]*$//')
  condition=$(echo "$basename_noext" | grep -oP '(BASE|LSP_GUIDED|LSP|TG_NATURAL|TG_GUIDED)')
  trial=$(echo "$basename_noext" | grep -oP 't\K[0-9]+$')
  tools_file="${result_file%.json}_tools.json"

  ruby -rjson -e '
    d = JSON.parse(File.read("'"$result_file"'", encoding: "UTF-8"))
    mu = d["modelUsage"] || {}
    fm = mu.values.first || {}

    t = begin
      JSON.parse(File.read("'"$tools_file"'", encoding: "UTF-8"))
    rescue
      {}
    end

    cats = t["categories"] || {}
    seq = (t["tool_sequence"] || []).join(";")
    wall_ms = d.fetch("wall_ms", d.fetch("duration_ms", 0))

    fields = [
      "'"$TIMESTAMP"'",
      "'"$task_id"'", "'"$condition"'", "'"$trial"'",
      !d.fetch("is_error", true),
      wall_ms,
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
  ' >> "$RUN_CSV" 2>/dev/null
done

echo "Run CSV: $RUN_CSV"

# --- Append to accumulated summary ---

ACCUMULATED_CSV="$ACCUMULATED_DIR/summary.csv"
if [[ ! -f "$ACCUMULATED_CSV" ]]; then
  echo "$CSV_HEADER" > "$ACCUMULATED_CSV"
fi

# Append data rows (skip header)
tail -n +2 "$RUN_CSV" >> "$ACCUMULATED_CSV"
echo "Accumulated CSV: $ACCUMULATED_CSV ($(( $(wc -l < "$ACCUMULATED_CSV") - 1 )) total rows)"
echo "Results saved to: $RUN_DIR"
