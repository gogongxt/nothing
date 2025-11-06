#!/bin/bash

# MODEL_PATH="/nfs/ofs-llm-ssd/user/gogongxt/models/Qwen3-8B"
# MODEL_PATH="/data1/jianshu-models/DeepSeek-R1"
# MODEL_PATH="/nfs/volume-1615-2/models/DeepSeek-R1"
MODEL_PATH="/tmp-data/models/DeepSeek-V2-Lite-Chat"
BENCH_SCRIPT="bench_serving.py"
DATASET_PATH="ShareGPT_V3_unfiltered_cleaned_split.json"

# Set custom headers via environment variable
# export CUSTOM_HEADERS='{"Host": "k8s-rsv-jnqjc5-1758863996385-jianshu.serving"}'

BASE_CMD=(
  python3 "$BENCH_SCRIPT"
  --backend sglang-oai-chat
  --port 30000
  --host 127.0.0.1
  --model "$MODEL_PATH"
  --dataset-path "$DATASET_PATH"
  --dataset-name random
  --random-input-len 2048
  --random-output-len 1024
  --random-range-ratio 1
  --seed 1234
  --extra-request-body '{"stream_options": {"include_usage": true}}'
)

# test concurrency table
CONCURRENCIES=(1 2 4 8 16 32 64 128)

for MAX_CONCURRENCY in "${CONCURRENCIES[@]}"; do
    NUM_PROMPTS=$((20 * MAX_CONCURRENCY)) # num-prompts = max-concurrency * 20

    echo "=============================================="
    echo "Running benchmark with:"
    echo "  --max-concurrency: $MAX_CONCURRENCY"
    echo "  --num-prompts: $NUM_PROMPTS"
    echo "=============================================="

    # complete cmd
    CMD=("${BASE_CMD[@]}" --max-concurrency "$MAX_CONCURRENCY" --num-prompts "$NUM_PROMPTS")
    echo "${CMD[@]}"
    echo "----------------------------------------------"
    "${CMD[@]}"

    sleep 1
done

echo "All benchmark tests completed!"
