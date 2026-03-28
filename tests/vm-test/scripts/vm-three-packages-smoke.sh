#!/bin/bash
#
# 在三台 libvirt 测试虚拟机（tmux：vm-ubuntu / vm-fedora / vm-centos）上
# 从宿主机 192.168.122.1 拉取 guest-smoke.sh 与仓库快照并执行 install.sh。
#
# 用法：在仓库根目录执行
#   bash tests/vm-test/scripts/vm-three-packages-smoke.sh
#
# 依赖：宿主机 virbr0=192.168.122.1；虚拟机可 ping 通该地址；tmux 会话已 attach 串口控制台。
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SNAP_NAME="starman-snapshot.tgz"
SNAP_PATH="/tmp/${SNAP_NAME}"
GUEST_SCRIPT_SRC="${REPO_ROOT}/tests/vm-test/scripts/guest-smoke.sh"
GUEST_SCRIPT_DST="/tmp/guest-smoke.sh"
HOST_HTTP="192.168.122.1"
PORT=8765
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

make_snapshot() {
    log "打包仓库 -> ${SNAP_PATH}"
    tar czf "${SNAP_PATH}" -C "${REPO_ROOT}" .
    cp -a "${GUEST_SCRIPT_SRC}" "${GUEST_SCRIPT_DST}"
    chmod +x "${GUEST_SCRIPT_DST}"
}

http_start() {
    cd /tmp
    python3 -m http.server "${PORT}" --bind "${HOST_HTTP}" >/tmp/starman-vm-http.log 2>&1 &
    echo $!
}

http_stop() {
    local pid="$1"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
}

# 短命令 + 唯一 ID；先 cd /tmp，避免 cwd 落在已删除的 /tmp/starman-smoke 上导致 bash 启动失败（exit 127）
guest_one_liner() {
    local sid="$1"
    printf '%s' "cd /tmp && export STARMAN_SMOKE_ID=${sid} && curl -fsSL http://${HOST_HTTP}:${PORT}/guest-smoke.sh -o /tmp/guest-smoke-run.sh && chmod +x /tmp/guest-smoke-run.sh && bash /tmp/guest-smoke-run.sh"
}

wait_for_marker() {
    local session="$1"
    local needle="$2"
    local max_rounds="${3:-900}"
    local i=0
    while [ "$i" -lt "$max_rounds" ]; do
        if tmux capture-pane -t "$session" -p -S -400 2>/dev/null | grep -qF "${needle}"; then
            return 0
        fi
        sleep 2
        i=$((i + 1))
    done
    return 1
}

run_one() {
    local session="$1"
    local sid
    sid="$(date +%s)-${RANDOM}-${RANDOM}"
    local needle="STARMAN_GUEST_SMOKE_DONE_${sid}"

    log "========== ${session} (id=${sid}) =========="
    tmux clear-history -t "$session" 2>/dev/null || true
    tmux send-keys -t "$session" C-c
    sleep 0.3
    tmux send-keys -t "$session" 'clear' Enter
    sleep 0.3
    tmux send-keys -t "$session" "$(guest_one_liner "$sid")" Enter
    if wait_for_marker "$session" "$needle"; then
        log "${session}: 检测到 ${needle}"
        tmux capture-pane -t "$session" -p -S -200 | grep -E "STARMAN_GUEST_SMOKE_DONE_${sid}|ERROR|error|失败|Could not retrieve|SUCCESS.*软件包|基础工具包" | tail -30
    else
        log "${session}: 超时（未看到 ${needle}）"
        tmux capture-pane -t "$session" -p -S -120 | tail -50
        return 1
    fi
}

main() {
    make_snapshot
    HTTP_PID="$(http_start)"
    log "HTTP ${HOST_HTTP}:${PORT} PID=${HTTP_PID}（/tmp 下：${SNAP_NAME} guest-smoke.sh）"
    sleep 1
    trap 'http_stop "${HTTP_PID}"' EXIT

    local failed=0
    run_one vm-ubuntu || failed=1
    run_one vm-fedora || failed=1
    run_one vm-centos || failed=1

    http_stop "${HTTP_PID}"
    trap - EXIT
    if [ "$failed" -ne 0 ]; then
        log "部分会话超时或失败（见上文）。"
        exit 1
    fi
    log "三台虚拟机顺序测试已执行完毕。"
}

main "$@"
