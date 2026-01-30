#!/usr/bin/env bash
set -euo pipefail

######################################
# 配置区
######################################
HEALTH_URL="http://127.0.0.1:58888/health"
HEALTH_TIMEOUT=600 # 10 min
HEALTH_INTERVAL=5  # 每 5s 检查一次
RESTART_WAIT=3     # kill 后等待几秒再重启

######################################
# 工具函数
######################################
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

kill_sglang() {
    log "Killing sglang..."
    if [[ "$(id -u)" -eq 0 ]]; then
        pkill -f sglang || true
    else
        sudo pkill -f sglang || true
    fi
}

wait_for_health_or_restart() {
    local start_ts now elapsed
    start_ts=$(date +%s)
    while true; do
        if curl -sf "$HEALTH_URL" >/dev/null; then
            log "Health check OK"
            return 0
        fi
        now=$(date +%s)
        elapsed=$((now - start_ts))
        if ((elapsed >= HEALTH_TIMEOUT)); then
            log "Health check timeout (${HEALTH_TIMEOUT}s), restarting sglang"
            kill_sglang
            sleep "$RESTART_WAIT"
            return 1
        fi
        sleep "$HEALTH_INTERVAL"
    done
}

######################################
# 核心函数
######################################
start_sglang() {
    local logfile
    local cmd=()
    ######################################
    # 参数解析：-- logfile -- cmd...
    ######################################
    if [[ "$1" == "--" ]]; then
        [[ $# -lt 4 ]] && {
            echo "Usage: start_sglang -- <logfile> -- <command> [args...]" >&2
            return 1
        }
        [[ "$3" != "--" ]] && {
            echo "Error: third argument must be '--'" >&2
            return 1
        }

        logfile="$2"
        # 展开 ~ 和 $VAR（允许 eval，输入可信）
        eval "logfile=\"$logfile\""
        # 转绝对路径（不要求存在）
        if [[ "$logfile" != /* ]]; then
            logfile="$PWD/$logfile"
        fi
        log_dir="$(dirname "$logfile")"
        mkdir -p "$log_dir"

        cmd=("${@:4}")
    else
        echo "Error: start_sglang requires '-- <logfile> -- <command>'" >&2
        return 1
    fi
    ######################################
    # 启动 + health check + 重启循环
    ######################################
    while true; do
        log "Starting sglang"
        log "Command: ${cmd[*]}"
        log "Log file: $logfile"
        "${cmd[@]}" >"$logfile" 2>&1 &
        local sglang_pid=$!
        log "sglang pid: $sglang_pid"
        if wait_for_health_or_restart; then
            return 0
        fi
        log "Retrying sglang start..."
        sleep 1
    done
}

bash_bench() {
    mkdir -p ./logs
    bash bench.sh --model-path $1 --dataset-path $DATASET_PATH --host 127.0.0.1 --port 58888 --random-input-len $3 --random-output-len $4 >./logs/$2 2>&1
}

######################################
# 变量设置
DATASET_PATH="/nfs/ofs-llm-ssd/user/gogongxt/datasets/ShareGPT_V3_unfiltered_cleaned_split.json"
QWEN3_8B="/data/models/Qwen3-8B"
QWEN3_32B="/data/models/Qwen3-32B"
DEEPSEEK="/data/models/DeepSeek-R1"
######################################
# 测试配置数组: name model tp input_len output_len
######################################
# 格式: model_base|model_path|tp|input_len|output_len
TEST_CONFIGS=(
    "qwen3-8b|$QWEN3_8B|1|2048|1024"
    "qwen3-8b|$QWEN3_8B|1|8192|2048"
    "qwen3-32b|$QWEN3_32B|2|2048|1024"
    "qwen3-32b|$QWEN3_32B|2|8192|2048"
    "deepseek|$DEEPSEEK|8|2048|1024"
    "deepseek|$DEEPSEEK|8|8192|2048"
)

run_test() {
    local model_base="$1"
    local model="$2"
    local tp="$3"
    local input_len="$4"
    local output_len="$5"

    # 自动生成测试名称，如: qwen3-8b-2048-1024
    local name="${model_base}-${input_len}-${output_len}"

    log "Starting test: $name"
    start_sglang -- ./logs/${name}.log -- python3 -m sglang.launch_server --model-path "$model" --tp "$tp"
    log "Running benchmark: $name"
    bash_bench "$model" "${name}.txt" "$input_len" "$output_len"
    sleep 5
    kill_sglang
    sleep 5
    log "Finished test: $name"
}

######################################
# 主流程
######################################
main() {
    for config in "${TEST_CONFIGS[@]}"; do
        IFS='|' read -r name model tp input_len output_len <<<"$config"
        run_test "$name" "$model" "$tp" "$input_len" "$output_len"
    done
    log "All tests finished"
}

main "$@"
