#!/usr/bin/env bash
set -euo pipefail

######################################
# 配置区
######################################
HEALTH_URL="http://127.0.0.1:30000/health"
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
        logfile="${2:a}"
        [[ "$2" != /* && "$2" != ~* ]] && logfile="$(pwd)/$2"
        local log_dir
        log_dir="$(dirname "$logfile")"
        [[ "$log_dir" != "." ]] && mkdir -p "$log_dir"
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

######################################
# 主流程
######################################
main() {
    start_sglang -- sglang-qwen3-32b-tp2-2k1k.log -- python3 -m sglang.launch_server --model-path /data/jianshu-models/Qwen3-32B --tp 2
    log "bash bench.sh 2k1k"
    bash bench.sh --model-path /data/jianshu-models/Qwen3-32B --random-input-len 2048 --random-output-len 1024 --dataset-path /data/jianshu-models/ShareGPT_V3_unfiltered_cleaned_split.json >qwen3-32b-tp2-2k1k.txt 2>&1

    sleep 5
    kill_sglang
    sleep 5

    start_sglang -- sglang-qwen3-32b-tp2-8k2k.log -- python3 -m sglang.launch_server --model-path /data/jianshu-models/Qwen3-32B --tp 2
    log "bash bench.sh 8k2k"
    bash bench.sh --model-path /data/jianshu-models/Qwen3-32B --random-input-len 8192 --random-output-len 2048 --dataset-path /data/jianshu-models/ShareGPT_V3_unfiltered_cleaned_split.json >qwen3-32b-tp2-8k2k.txt 2>&1

    sleep 5
    kill_sglang

    log "All tests finished"
}

main "$@"
