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
    bash bench.sh --model-path /data/models/Qwen3-Next-80B-A3B-Instruct --dataset-path ./llab_qwen3next_dataset_3k.json --use-custom-dataset --concurrency 1 --num-prompt-times 100 --port 58888 -- --output-details >./logs/$@ 2>&1
}

######################################
# 主流程
######################################
main() {
    LOG_LOG="plain"
    start_sglang -- ./logs/sglang-qwen3next-tp4-${LOG_LOG}.log -- bash /nfs/ofs-llm-ssd/user/gogongxt/Projects/qwen3-next/start.sh
    log "bash bench.sh ${LOG_LOG}"
    bash_bench qwen3-${LOG_LOG}.txt
    sleep 5
    kill_sglang
    sleep 5

    LOG_LOG="pcg-extra-buffer-spec"
    start_sglang -- ./logs/sglang-qwen3next-tp4-${LOG_LOG}.log -- bash /nfs/ofs-llm-ssd/user/gogongxt/Projects/qwen3-next/start.sh --pcg --extra-buffer --spec-v2
    log "bash bench.sh ${LOG_LOG}"
    bash_bench qwen3-${LOG_LOG}.txt
    sleep 5
    kill_sglang
    sleep 5

    LOG_LOG="pcg-extra-buffer-bf16-spec"
    start_sglang -- ./logs/sglang-qwen3next-tp4-${LOG_LOG}.log -- bash /nfs/ofs-llm-ssd/user/gogongxt/Projects/qwen3-next/start.sh --pcg --extra-buffer --extra-buffer-bf16 --spec-v2
    log "bash bench.sh ${LOG_LOG}"
    bash_bench qwen3-${LOG_LOG}.txt
    sleep 5
    kill_sglang
    sleep 5

    LOG_LOG="pcg"
    start_sglang -- ./logs/sglang-qwen3next-tp4-${LOG_LOG}.log -- bash /nfs/ofs-llm-ssd/user/gogongxt/Projects/qwen3-next/start.sh --pcg
    log "bash bench.sh ${LOG_LOG}"
    bash_bench qwen3-${LOG_LOG}.txt
    sleep 5
    kill_sglang
    sleep 5

    LOG_LOG="spec"
    start_sglang -- ./logs/sglang-qwen3next-tp4-${LOG_LOG}.log -- bash /nfs/ofs-llm-ssd/user/gogongxt/Projects/qwen3-next/start.sh --spec-v2
    log "bash bench.sh ${LOG_LOG}"
    bash_bench qwen3-${LOG_LOG}.txt
    sleep 5
    kill_sglang
    sleep 5

    LOG_LOG="extra-buffer"
    start_sglang -- ./logs/sglang-qwen3next-tp4-${LOG_LOG}.log -- bash /nfs/ofs-llm-ssd/user/gogongxt/Projects/qwen3-next/start.sh --extra-buffer
    log "bash bench.sh ${LOG_LOG}"
    bash_bench qwen3-${LOG_LOG}.txt
    sleep 5
    kill_sglang
    sleep 5

    LOG_LOG="extra-buffer-bf16"
    start_sglang -- ./logs/sglang-qwen3next-tp4-${LOG_LOG}.log -- bash /nfs/ofs-llm-ssd/user/gogongxt/Projects/qwen3-next/start.sh --extra-buffer --extra-buffer-bf16
    log "bash bench.sh ${LOG_LOG}"
    bash_bench qwen3-${LOG_LOG}.txt
    sleep 5
    kill_sglang
    sleep 5

    LOG_LOG="pcg-extra-buffer"
    start_sglang -- ./logs/sglang-qwen3next-tp4-${LOG_LOG}.log -- bash /nfs/ofs-llm-ssd/user/gogongxt/Projects/qwen3-next/start.sh --pcg --extra-buffer
    log "bash bench.sh ${LOG_LOG}"
    bash_bench qwen3-${LOG_LOG}.txt
    sleep 5
    kill_sglang
    sleep 5

    LOG_LOG="pcg-spec"
    start_sglang -- ./logs/sglang-qwen3next-tp4-${LOG_LOG}.log -- bash /nfs/ofs-llm-ssd/user/gogongxt/Projects/qwen3-next/start.sh --pcg --spec-v2
    log "bash bench.sh ${LOG_LOG}"
    bash_bench qwen3-${LOG_LOG}.txt
    sleep 5
    kill_sglang
    sleep 5

    LOG_LOG="extra-buffer-spec"
    start_sglang -- ./logs/sglang-qwen3next-tp4-${LOG_LOG}.log -- bash /nfs/ofs-llm-ssd/user/gogongxt/Projects/qwen3-next/start.sh --extra-buffer --spec-v2
    log "bash bench.sh ${LOG_LOG}"
    bash_bench qwen3-${LOG_LOG}.txt
    sleep 5
    kill_sglang
    sleep 5

    log "All tests finished"
}

main "$@"
