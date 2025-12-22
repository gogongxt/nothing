#!/bin/bash

MODEL_PATH="/nfs/ofs-llm-ssd/user/gogongxt/models/Qwen3-8B"
BENCH_SCRIPT="bench_serving.py"
DATASET_PATH="/nfs/ofs-llm-ssd/user/gogongxt/datasets/ShareGPT_V3_unfiltered_cleaned_split.json"
HOST="127.0.0.1"
PORT="58888"
RANDOM_INPUT_LEN="2048"
RANDOM_OUTPUT_LEN="1024"
# Set custom headers via environment variable
# export CUSTOM_HEADERS='{"Host": "k8s-rsv-jnqjc5-1758863996385-jianshu.serving"}'

# Array to store passthrough arguments
PASSTHROUGH_ARGS=()

# Usage function
usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  --model-path PATH        设置模型路径 (默认: $MODEL_PATH)"
    echo "  --bench-script SCRIPT    设置基准测试脚本 (默认: $BENCH_SCRIPT)"
    echo "  --dataset-path PATH      设置数据集路径 (默认: $DATASET_PATH)"
    echo "  --host HOST              设置主机地址 (默认: $HOST)"
    echo "  --port PORT              设置端口 (默认: $PORT)"
    echo "  --random-input-len LEN   设置随机输入长度 (默认: $RANDOM_INPUT_LEN)"
    echo "  --random-output-len LEN  设置随机输出长度 (默认: $RANDOM_OUTPUT_LEN)"
    echo "  -h, --help               显示帮助信息"
    echo ""
    echo "透传参数:"
    echo "  使用 '--' 分隔符，后面的所有参数将被直接传递给 bench_serving.py"
    echo "  例如: -- --request-rate 10 --backend vllm --dataset-name sharegpt"
    echo ""
    echo "示例:"
    echo "  $0 --model-path /path/to/model --host localhost --port 30000 --random-input-len 1024 --random-output-len 512"
    echo "  $0 -- --request-rate 5 --backend vllm # 透传参数给 bench_serving.py"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        --model-path)
            MODEL_PATH="$2"
            shift 2
            ;;
        --bench-script)
            BENCH_SCRIPT="$2"
            shift 2
            ;;
        --dataset-path)
            DATASET_PATH="$2"
            shift 2
            ;;
        --host)
            HOST="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --random-input-len)
            RANDOM_INPUT_LEN="$2"
            shift 2
            ;;
        --random-output-len)
            RANDOM_OUTPUT_LEN="$2"
            shift 2
            ;;
        --)
            shift
            PASSTHROUGH_ARGS=("$@")
            break
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            usage
            exit 1
            ;;
        esac
    done
}

# Parse command line arguments FIRST
parse_args "$@"

BASE_CMD=(
    python3 "$BENCH_SCRIPT"
    --backend sglang-oai-chat
    --port "$PORT"
    --host "$HOST"
    --model "$MODEL_PATH"
    --dataset-path "$DATASET_PATH"
    --dataset-name random
    --random-input-len "$RANDOM_INPUT_LEN"
    --random-output-len "$RANDOM_OUTPUT_LEN"
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
    CMD=("${BASE_CMD[@]}" --max-concurrency "$MAX_CONCURRENCY" --num-prompts "$NUM_PROMPTS" "${PASSTHROUGH_ARGS[@]}")
    echo "${CMD[@]}"
    echo "----------------------------------------------"
    "${CMD[@]}"

    sleep 1
done

echo "All benchmark tests completed!"
