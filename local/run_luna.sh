#!/bin/bash
# Run mini-SWE-agent with OpenAI Luna on a SWE-bench sample (local Mac + Docker),
# then optionally evaluate the predictions with the SWE-bench harness.
#
# Usage examples:
#   FILTER='^(sympy__sympy-20590|django__django-11099)$' OUT=luna_pilot ./run_luna.sh
#   SLICE=0:3 OUT=luna_slice03 ./run_luna.sh
#   DRY_RUN=1 SLICE=0:3 OUT=test ./run_luna.sh       # print the commands, spend nothing
#   ITERATIONS=3 ...                                # repeat the run (each iteration costs again!)
#   EVAL=0 ...                                      # inference only, no harness eval
#   SUBSET=/path/to/dataset SPLIT=test ...          # our own tasks (need image_name per instance)
#   our benchmark: SUBSET=<nca-tasks>/dataset SPLIT=test TASK_REPO=<nca-tasks> SLICE=0:25 OUT=luna_nca ./run_luna.sh
#
# Based on the TA template (nca-project/scratch/template-nca/eval.sh) and Alessandro's
# 1_evaluation/run_gpt_5_mini.sh:
#  - model via API instead of vLLM, docker instead of singularity
#  - MSWEA_COST_TRACKING is NOT set to ignore_errors: costs must be tracked so the limits work
#  - per-instance cost limit + hard global cap per iteration (strict $10 budget for the project)
#  - eval with the new `swebench eval` CLI (+ --task-repo, images built locally on Mac)

set -euo pipefail

# ---------- Paths ----------
NCA_ROOT="${NCA_ROOT:-$HOME/3rd_Semester/NCA}"
TOOLS="$NCA_ROOT/tools"
MSWEA_DIR="$TOOLS/mini-swe-agent"
SWEB_DIR="$TOOLS/SWE-bench"
RUNS_DIR="${RUNS_DIR:-$NCA_ROOT/nca-project/local/runs}"

# ---------- Parameters ----------
MODEL="${MODEL:-openai/gpt-6-luna}"
REASONING_EFFORT="${REASONING_EFFORT:-low}"   # course asks for low-medium
TEMPERATURE="${TEMPERATURE:-}"                # empty = model default (Alessandro: null)
VERBOSITY="${VERBOSITY:-}"                    # empty = not sent (Alessandro: medium, gpt-5 param)
STEP_LIMIT="${STEP_LIMIT:-75}"                # same as the TA template
INSTANCE_COST_LIMIT="${INSTANCE_COST_LIMIT:-0.30}"   # $ per instance
GLOBAL_COST_LIMIT="${GLOBAL_COST_LIMIT:-1.00}"       # $ per iteration (one mini-extra process)
ITERATIONS="${ITERATIONS:-1}"
WORKERS="${WORKERS:-2}"
SUBSET="${SUBSET:-verified}"
SPLIT="${SPLIT:-test}"
FILTER="${FILTER:-}"
SLICE="${SLICE:-}"
OUT="${OUT:-}"
EVAL="${EVAL:-1}"
EVAL_JOBS="${EVAL_JOBS:-2}"
DRY_RUN="${DRY_RUN:-0}"
# task repo the harness builds images from: swe-bench-tasks for Verified,
# <nca-project>/local/validation/nca-tasks for our benchmark
TASK_REPO="${TASK_REPO:-$SWEB_DIR/swe-bench-tasks}"

if [[ -z "$OUT" ]]; then
  echo "ERROR: set OUT=<run name> (results go to $RUNS_DIR/<OUT>)" >&2; exit 1
fi
if [[ -z "$FILTER" && -z "$SLICE" ]]; then
  echo "ERROR: set FILTER=<regex> or SLICE=<a:b> (refusing to run the whole dataset)" >&2; exit 1
fi
if [[ "${MSWEA_COST_TRACKING:-default}" != "default" ]]; then
  echo "ERROR: MSWEA_COST_TRACKING=$MSWEA_COST_TRACKING disables cost limits; unset it" >&2; exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"   # harness caches by run-id: keep run-ids unique

# ---------- Environment ----------
export DOCKER_DEFAULT_PLATFORM=linux/amd64
export LITELLM_SUPPRESS_DEBUG_INFO="True"
export MSWEA_GLOBAL_COST_LIMIT="$GLOBAL_COST_LIMIT"
if [[ -z "${OPENAI_API_KEY:-}" && -f "$HOME/.nca_openai" ]]; then
  set -a; source "$HOME/.nca_openai"; set +a
fi
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "ERROR: OPENAI_API_KEY not set (expected in ~/.nca_openai)" >&2; exit 1
fi

# ---------- Commands ----------
infer_cmd() {  # $1 = output dir
  INFER_CMD=(
    "$MSWEA_DIR/.venv/bin/mini-extra" swebench
    -c swebench.yaml
    -m "$MODEL"
    -c "model.model_kwargs.reasoning_effort=$REASONING_EFFORT"
    -c "agent.step_limit=$STEP_LIMIT"
    -c "agent.cost_limit=$INSTANCE_COST_LIMIT"
    --subset "$SUBSET" --split "$SPLIT"
    -w "$WORKERS"
    --environment-class docker
    -o "$1"
  )
  [[ -n "$TEMPERATURE" ]] && INFER_CMD+=(-c "model.model_kwargs.temperature=$TEMPERATURE")
  [[ -n "$VERBOSITY"   ]] && INFER_CMD+=(-c "model.model_kwargs.verbosity=$VERBOSITY")
  [[ -n "$FILTER"      ]] && INFER_CMD+=(--filter "$FILTER")
  [[ -n "$SLICE"       ]] && INFER_CMD+=(--slice "$SLICE")
  return 0
}

eval_cmd() {  # $1 = output dir, $2 = run id
  EVAL_CMD=(
    "$SWEB_DIR/.venv/bin/swebench" eval "$SUBSET"
    -p "$1/preds.json"
    --run-id "$2"
    -j "$EVAL_JOBS"
    --task-repo "$TASK_REPO"
  )
}

cost_summary() {  # $1 = output dir
  "$MSWEA_DIR/.venv/bin/python" -I - "$1" <<'EOF' | tee "$1/cost_summary.txt"
import json, sys, pathlib
out = pathlib.Path(sys.argv[1])
rows = []
for f in sorted(out.glob("*/*.traj.json")):
    info = json.loads(f.read_text()).get("info", {})
    st = info.get("model_stats", {})
    rows.append((f.parent.name, st.get("instance_cost", 0.0), st.get("api_calls", 0), info.get("exit_status")))
print(f"{'instance':45} {'cost $':>8} {'calls':>6}  exit_status")
for iid, c, n, ex in rows:
    print(f"{iid:45} {c:8.4f} {n:6d}  {ex}")
if rows:
    tot = sum(r[1] for r in rows)
    print(f"TOTAL {len(rows)} instances: ${tot:.4f}  mean ${tot/len(rows):.4f}/instance")
EOF
}

echo "== Config"
echo "  model=$MODEL effort=$REASONING_EFFORT temperature='${TEMPERATURE}' verbosity='${VERBOSITY}' steps=$STEP_LIMIT"
echo "  cost: \$$INSTANCE_COST_LIMIT/instance, \$$GLOBAL_COST_LIMIT cap per iteration, iterations=$ITERATIONS"
echo "  subset=$SUBSET split=$SPLIT filter='${FILTER}' slice='${SLICE}' workers=$WORKERS"
echo "  out=$RUNS_DIR/$OUT  eval=$EVAL  task_repo=$TASK_REPO"

for i in $(seq 1 "$ITERATIONS"); do
  OUT_DIR="$RUNS_DIR/$OUT"
  RUN_ID="${OUT}_${STAMP}"
  if (( ITERATIONS > 1 )); then OUT_DIR="$OUT_DIR/iter_$i"; RUN_ID="${RUN_ID}_iter$i"; fi
  infer_cmd "$OUT_DIR"; eval_cmd "$OUT_DIR" "$RUN_ID"

  echo "--------- Iteration $i/$ITERATIONS ---------"
  echo "== Inference command"; printf '  %q' "${INFER_CMD[@]}"; echo
  [[ "$EVAL" == "1" ]] && { echo "== Eval command"; printf '  %q' "${EVAL_CMD[@]}"; echo; }
  if [[ "$DRY_RUN" == "1" ]]; then continue; fi

  mkdir -p "$OUT_DIR"

  START=$(date +%s)
  "${INFER_CMD[@]}"
  echo "Inference time: $(( $(date +%s) - START )) s"

  cost_summary "$OUT_DIR"

  if [[ "$EVAL" == "1" ]]; then
    if [[ ! -s "$OUT_DIR/preds.json" ]]; then
      echo "No preds.json in $OUT_DIR, skipping evaluation" >&2; continue
    fi
    # limit the harness to the predicted instances (otherwise it reports the whole dataset as incomplete)
    while read -r iid; do EVAL_CMD+=(-i "$iid"); done < <(
      "$MSWEA_DIR/.venv/bin/python" -I -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))))' "$OUT_DIR/preds.json")
    START=$(date +%s)
    (cd "$SWEB_DIR" && "${EVAL_CMD[@]}")   # harness writes logs/evaluation/<run_id>/ there
    cp "$SWEB_DIR/logs/evaluation/$RUN_ID/results.json" "$OUT_DIR/results_${RUN_ID}.json" && \
      echo "Results copied to $OUT_DIR/results_${RUN_ID}.json"
    echo "Evaluation time: $(( $(date +%s) - START )) s"
  fi
done

[[ "$DRY_RUN" == "1" ]] && echo "DRY_RUN=1: nothing executed."
exit 0
