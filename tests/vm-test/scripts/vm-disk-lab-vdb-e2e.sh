#!/bin/bash
#
# 在 vm-ubuntu（ubuntu22-test）上对附加数据盘 /dev/vdb 做 disk_lab 端到端测试（tmux 发键，禁止 wget/curl|bash）。
#
# 用法（仓库根目录）：
#   bash tests/vm-test/scripts/vm-disk-lab-vdb-e2e.sh
#
# 前提：域 ubuntu22-test 已挂 virtio 数据盘（见 scripts/vm/attach-ubuntu-data-disk.sh）；虚拟机 running。
# 破坏性：将 mkfs.ext4 /dev/vdb 并挂载 /data；测前建议 bash scripts/vm/backup-vm.sh ubuntu22-test。
#
# 依赖：192.168.122.1 可访问；tmux 会话 vm-ubuntu。
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SESSION="${STARMAN_VDB_E2E_SESSION:-vm-ubuntu}"
SNAP_NAME="starman-snapshot.tgz"
SNAP_PATH="/tmp/${SNAP_NAME}"
GUEST_SRC="${REPO_ROOT}/tests/vm-test/scripts/guest-disk-lab-vdb-e2e.sh"
GUEST_HTTP_NAME="guest-disk-lab-vdb-e2e.sh"
HOST_HTTP="${STARMAN_SMOKE_HTTP_HOST:-192.168.122.1}"
PORT="${STARMAN_VDB_E2E_PORT:-8767}"
UBUNTU_PASS="${STARMAN_UBUNTU_PASS:-ubuntu123}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

_plain() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\]0;[^\x07]*\x07//g' 2>/dev/null || cat
}

_capture() {
    tmux capture-pane -t "$SESSION" -p -S -320 2>/dev/null | _plain
}

make_snapshot() {
    log "打包仓库 -> ${SNAP_PATH}"
    tar czf "${SNAP_PATH}" -C "${REPO_ROOT}" .
    cp -a "${GUEST_SRC}" "/tmp/${GUEST_HTTP_NAME}"
    chmod +x "/tmp/${GUEST_HTTP_NAME}"
}

http_start() {
    cd /tmp
    python3 -m http.server "${PORT}" --bind "${HOST_HTTP}" >/tmp/starman-vdb-e2e-http.log 2>&1 &
    echo $!
}

http_stop() {
    local pid="$1"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
}

drive_vdb_e2e() {
    local sid="$1"
    local needle="STARMAN_DISK_LAB_VDB_E2E_DONE_${sid}"
    local sent_j=0
    local sent_dev=0
    local sent_fs=0
    local sent_mp=0
    local sent_yes=0
    local max=$((40 * 60))
    local i=0

    while [ "$i" -lt "$max" ]; do
        sleep 1
        local p
        p="$(_capture)"

        if echo "$p" | grep -qiE '\[sudo\]|password for ubuntu'; then
            tmux send-keys -t "$SESSION" "$UBUNTU_PASS" Enter
            sleep 0.5
            continue
        fi

        # 勿匹配 log_info；radio 模式：下移光标后需 Space 勾选当前项，再 Enter（见 tui.sh）
        if [ "$sent_j" -eq 0 ] && echo "$p" | grep -q '跳过（不格式化'; then
            sleep 0.6
            tmux send-keys -t "$SESSION" j
            sleep 0.45
            tmux send-keys -t "$SESSION" Space
            sleep 0.35
            tmux send-keys -t "$SESSION" Enter
            sent_j=1
            log "${SESSION}: 已选「配置未挂载数据盘」（j + Space + Enter）"
            continue
        fi

        if [ "$sent_j" -eq 1 ] && [ "$sent_dev" -eq 0 ]; then
            if echo "$p" | grep -qE '选择要格式化的块设备|/dev/vdb'; then
                sleep 0.45
                if echo "$p" | grep -qE '1\).*vdb'; then
                    tmux send-keys -t "$SESSION" 1 Enter
                else
                    tmux send-keys -t "$SESSION" Enter
                fi
                sent_dev=1
                log "${SESSION}: 已确认块设备选择"
                continue
            fi
        fi

        if [ "$sent_dev" -eq 1 ] && [ "$sent_fs" -eq 0 ]; then
            if echo "$p" | grep -q '文件系统类型'; then
                sleep 0.4
                tmux send-keys -t "$SESSION" Enter
                sent_fs=1
                log "${SESSION}: 已选文件系统（默认 ext4）"
                continue
            fi
        fi

        if [ "$sent_fs" -eq 1 ] && [ "$sent_mp" -eq 0 ]; then
            if echo "$p" | grep -q '挂载点'; then
                sleep 0.35
                tmux send-keys -t "$SESSION" Enter
                sent_mp=1
                log "${SESSION}: 已确认挂载点（默认 /data）"
                continue
            fi
        fi

        if [ "$sent_mp" -eq 1 ] && [ "$sent_yes" -eq 0 ]; then
            if echo "$p" | grep -q '大写 YES'; then
                sleep 0.35
                tmux send-keys -t "$SESSION" Y E S Enter
                sent_yes=1
                log "${SESSION}: 已发送 YES 确认格式化"
                continue
            fi
        fi

        if echo "$p" | grep -qF "$needle"; then
            return 0
        fi
        if echo "$p" | grep -qF "STARMAN_DISK_LAB_VDB_E2E_FAIL_${sid}"; then
            log "客体报告失败标记"
            return 1
        fi

        i=$((i + 1))
    done
    return 1
}

main() {
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        log "错误：tmux 会话不存在：$SESSION"
        exit 1
    fi

    if ! virsh -c qemu:///session dominfo ubuntu22-test &>/dev/null; then
        log "错误：域 ubuntu22-test 不存在"
        exit 1
    fi

    make_snapshot
    HTTP_PID="$(http_start)"
    log "HTTP ${HOST_HTTP}:${PORT} PID=${HTTP_PID}"
    sleep 1
    trap 'http_stop "${HTTP_PID}"' EXIT

    local sid
    sid="$(date +%s)-${RANDOM}-${RANDOM}"

    log "========== ${SESSION} disk_lab vdb e2e (id=${sid}) =========="
    tmux clear-history -t "$SESSION" 2>/dev/null || true
    tmux send-keys -t "$SESSION" C-c
    sleep 0.3
    tmux send-keys -t "$SESSION" 'clear' Enter
    sleep 0.3

    tmux send-keys -t "$SESSION" "cd /tmp && export STARMAN_SMOKE_ID=${sid} STARMAN_SMOKE_HTTP_PORT=${PORT} STARMAN_SMOKE_SNAP=${SNAP_NAME} STARMAN_UBUNTU_PASS=${UBUNTU_PASS}" Enter
    sleep 0.2
    tmux send-keys -t "$SESSION" "wget -qO /tmp/${GUEST_HTTP_NAME} http://${HOST_HTTP}:${PORT}/${GUEST_HTTP_NAME} || curl -fsSL http://${HOST_HTTP}:${PORT}/${GUEST_HTTP_NAME} -o /tmp/${GUEST_HTTP_NAME}" Enter
    sleep 4
    tmux send-keys -t "$SESSION" "chmod +x /tmp/${GUEST_HTTP_NAME}" Enter
    sleep 0.3
    tmux send-keys -t "$SESSION" "bash /tmp/${GUEST_HTTP_NAME}" Enter

    if drive_vdb_e2e "$sid"; then
        log "检测到 STARMAN_DISK_LAB_VDB_E2E_DONE_${sid}"
        _capture | tail -n 45
    else
        log "超时或失败（未看到 STARMAN_DISK_LAB_VDB_E2E_DONE_${sid}）"
        _capture | tail -n 80
        http_stop "${HTTP_PID}"
        trap - EXIT
        exit 1
    fi

    http_stop "${HTTP_PID}"
    trap - EXIT
    log "vm-ubuntu 数据盘 disk_lab e2e 完成。"
}

main "$@"
