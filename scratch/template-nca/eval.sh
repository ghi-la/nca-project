#!/bin/bash

# Config adapted file from:
# https://github.com/swe-agent/mini-swe-agent/blob/main/src/minisweagent/config/benchmarks/swebench.yaml
# https://mini-swe-agent.com/latest/models/quickstart/#__tabbed_1_2
# Default values for the parameters: https://www.swebench.com/verified.html


export LITELLM_SUPPRESS_DEBUG_INFO="True"
export MINISWEAGENT_LOG_LEVEL="DEBUG"
export MSWEA_COST_TRACKING='ignore_errors'
export MSWEA_SINGULARITY_EXECUTABLE=apptainer

# Set model parameters
HF_MODEL_NAME="Qwen/Qwen3.8-27B"
MODEL_CACHE="/models/hub/models--Qwen--Qwen3.8-27B"
REVISION=$(cat "$MODEL_CACHE/refs/main")
LOCAL_MODEL_PATH="$MODEL_CACHE/snapshots/$REVISION"

MODEL_NAME="hosted_vllm/$HF_MODEL_NAME"
SAFE_MODEL_NAME=$(echo "$HF_MODEL_NAME" | tr '/' '_')

# Set agent parameters
TEMPERATURE=1.0
REASONING_EFFORT="medium"
STEP_LIMIT=75

# Other parameters
ITERATIONS=1
BENCHMARK_PATH="verified"
BENCHMARK_SPLIT="test"
BENCHMARK_SLICE="${BENCHMARK_SLICE:-0:10}"
RESULTS_DIR="results"
mkdir -p "$RESULTS_DIR"

# Set vLLM parameters
VLLM_PORT=8200
VLLM_HOSTNAME="localhost"
VLLM_API_BASE="http://$VLLM_HOSTNAME:$VLLM_PORT/v1"
VLLM_STARTUP_TIMEOUT=600
MAX_MODEL_LEN=32768

# Start vLLM
EXTRACTED_MODEL_NAME=$(echo "$HF_MODEL_NAME" | tr '/' '-')

vllm serve "$LOCAL_MODEL_PATH" \
    --served-model-name "$HF_MODEL_NAME" \
    --port "$VLLM_PORT" \
    --max-model-len "$MAX_MODEL_LEN" \
    --max-num-seqs 16 \
    --reasoning-parser qwen3 \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    > "vllm_$EXTRACTED_MODEL_NAME.log" 2>&1 &

VLLM_PID=$!
echo "vLLM PID: $VLLM_PID"

# Shut down vLLM when the script exits (including failures).
cleanup() {
    echo "Shutting down vLLM for model: $HF_MODEL_NAME ..."
    kill "$VLLM_PID" 2>/dev/null || true
    wait "$VLLM_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Wait until the API endpoint is ready
echo -n "Waiting for vLLM to be ready"
STARTUP_START=$(date +%s)
until curl -fsS "$VLLM_API_BASE/models" > /dev/null 2>&1; do
    if ! kill -0 "$VLLM_PID" 2>/dev/null; then
        echo "vLLM exited during startup."
        tail -100 "vllm_$EXTRACTED_MODEL_NAME.log"
        exit 1
    fi
    if (( $(date +%s) - STARTUP_START >= VLLM_STARTUP_TIMEOUT )); then
        echo "vLLM startup timed out."
        tail -100 "vllm_$EXTRACTED_MODEL_NAME.log"
        exit 1
    fi
    echo -n "."
    sleep 3
done
echo "... vLLM is ready!"


# Run the evaluation for the specified number of iterations
for i in $(seq 1 "$ITERATIONS"); do
    echo "--------- Iteration $i/$ITERATIONS ---------"

    OUTPUT_DIR="./$RESULTS_DIR/${SAFE_MODEL_NAME}/iter_$i"
    mkdir -p "$OUTPUT_DIR"

    # Inference
    START_TIME=$(date +%s)

    TRAJECTORIES_DIR="$OUTPUT_DIR/trajectories"
    mini-extra swebench \
      -c swebench.yaml \
      -c "model.model_name=$MODEL_NAME" \
      -c "model.model_kwargs.api_base=$VLLM_API_BASE" \
      -c model.model_kwargs.drop_params=false \
      -c "model.model_kwargs.temperature=$TEMPERATURE" \
      -c "model.model_kwargs.reasoning_effort=$REASONING_EFFORT" \
      -c agent.step_limit=$STEP_LIMIT \
      --subset "$BENCHMARK_PATH" \
      --split "$BENCHMARK_SPLIT" \
      --output "$TRAJECTORIES_DIR" \
      --workers 1 \
      --slice "$BENCHMARK_SLICE" \
      --environment-class singularity

    END_TIME=$(date +%s)
    ELAPSED_TIME=$((END_TIME - START_TIME))
    echo "Total time taken for inference: $ELAPSED_TIME seconds"
    
done
