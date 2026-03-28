#!/bin/bash
#
# 在三台 libvirt 测试虚拟机（tmux：vm-ubuntu / vm-fedora / vm-centos）上
# 验证 install-script-disk-lab：交互式终端（禁止 curl|bash 管道），见 starman-vm-tmux-test。
#
# 用法：在仓库根目录执行
#   bash tests/vm-test/scripts/vm-disk-lab-smoke.sh
#
# 依赖：宿主机 virbr0=192.168.122.1；虚拟机可访问该地址；tmux 会话 vm-* 已 attach 串口。
# 流程：curl -o 脚本 → chmod → bash /tmp/...；轮询屏显「数据盘与 lab」后发 Enter 确认默认「跳过」；
#       不进行磁盘格式化。
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SNAP_NAME="starman-snapshot.tgz"
SNAP_PATH="/tmp/${SNAP_NAME}"
GUEST_SCRIPT_SRC="${REPO_ROOT}/tests/vm-test/scripts/guest-disk-lab-smoke.sh"
GUEST_SCRIPT_DST="/tmp/guest-disk-lab-smoke.sh"
HOST_HTTP="192.168.122.1"
PORT=8765

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

_plain() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\]0;[^\x07]*\x07//g' 2>/dev/null || cat
}

_capture() {
    tmux capture-pane -t "$1" -p -S -220 2>/dev/null | _plain
}

make_snapshot() {
    log "打包仓库 -> ${SNAP_PATH}"
    tar czf "${SNAP_PATH}" -C "${REPO_ROOT}" .
    cp -a "${GUEST_SCRIPT_SRC}" "${GUEST_SCRIPT_DST}"
    chmod +x "${GUEST_SCRIPT_DST}"
}

http_start() {
    cd /tmp
    python3 -m http.server "${PORT}" --bind "${HOST_HTTP}" >/tmp/starman-vm-disk-lab-http.log 2>&1 &
    echo $!
}

http_stop() {
    local pid="$1"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
}

# 下发：落地脚本后以 bash 文件方式执行（交互式 TTY）；出现数据盘 TUI 时发 Enter 跳过
drive_disk_lab_interactive() {
    local session="$1"
    local sid="$2"
    local needle="STARMAN_DISK_LAB_VM_DONE_${sid}"
    local sent_menu=0
    local max=$((45 * 60))
    local i=0

    while [ "$i" -lt "$max" ]; do
        sleep 1
        local pane
        pane="$(_capture "$session")"

        # 仅匹配菜单项，避免命中 log_info「数据盘与 lab 共享步骤」
        if [ "$sent_menu" -eq 0 ] && echo "$pane" | grep -q '跳过（不格式化'; then
            sleep 0.4
            tmux send-keys -t "$session" Enter
            sent_menu=1
            log "${session}: 已在「数据盘与 lab」TUI 发送 Enter（确认跳过）"
        fi

        if echo "$pane" | grep -qF "$needle"; then
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

run_one() {
    local session="$1"
    local sid
    sid="$(date +%s)-${RANDOM}-${RANDOM}"
    local needle="STARMAN_DISK_LAB_VM_DONE_${sid}"

    log "========== ${session} (id=${sid}) =========="
    tmux clear-history -t "$session" 2>/dev/null || true
    tmux send-keys -t "$session" C-c
    sleep 0.3
    tmux send-keys -t "$session" 'clear' Enter
    sleep 0.3

    tmux send-keys -t "$session" "cd /tmp && export STARMAN_SMOKE_ID=${sid}" Enter
    sleep 0.2
    tmux send-keys -t "$session" "curl -fsSL http://${HOST_HTTP}:${PORT}/guest-disk-lab-smoke.sh -o /tmp/guest-disk-lab-smoke.sh" Enter
    sleep 3
    tmux send-keys -t "$session" "chmod +x /tmp/guest-disk-lab-smoke.sh" Enter
    sleep 0.3
    tmux send-keys -t "$session" "bash /tmp/guest-disk-lab-smoke.sh" Enter

    if drive_disk_lab_interactive "$session" "$sid"; then
        log "${session}: 检测到 ${needle}"
        _capture "$session" | tail -n 40 | grep -E "STARMAN_DISK_LAB_VM_DONE_${sid}|DISK_LAB_VM_FAIL|已跳过数据盘" | tail -20 || true
    else
        log "${session}: 超时（未看到 ${needle}）"
        _capture "$session" | tail -60
        return 1
    fi
}

main() {
    make_snapshot
    HTTP_PID="$(http_start)"
    log "HTTP ${HOST_HTTP}:${PORT} PID=${HTTP_PID}"
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
    log "三台虚拟机 disk_lab 交互式冒烟测试已执行完毕。"
}

main "$@"
