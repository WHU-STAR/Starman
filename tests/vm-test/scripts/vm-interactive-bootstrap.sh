#!/bin/bash
#
# 在 Ubuntu / Fedora 测试 VM（tmux：vm-ubuntu、vm-fedora）上验证「wget 落地 + bash 交互」安装流程。
#
# 宿主机在 192.168.122.1 提供与仓库根目录一致的 HTTP，通过环境变量把安装源指到该镜像：
#   STARMAN_INSTALLER_URL / STARMAN_GITEE_RAW
# 自动化在 tmux 中发送 sudo 密码与 TUI 的 Enter（可选包 / 模板 / 编辑器）。
#
# 用法（在仓库根目录）:
#   bash tests/vm-test/scripts/vm-interactive-bootstrap.sh
#
# 依赖：virbr0=192.168.122.1；VM 可访问该地址；已登录 shell 的 tmux 会话。
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HOST_HTTP="${STARMAN_TEST_HTTP_HOST:-192.168.122.1}"
PORT="${STARMAN_TEST_HTTP_PORT:-8765}"
BASE_URL="http://${HOST_HTTP}:${PORT}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

http_start() {
    cd "$REPO_ROOT"
    python3 -m http.server "${PORT}" --bind "${HOST_HTTP}" >/tmp/starman-interactive-http.log 2>&1 &
    echo $!
}

http_stop() {
    local pid="$1"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi
}

# 去除常见 ANSI，便于 grep
_plain() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\]0;[^\x07]*\x07//g' 2>/dev/null || cat
}

_capture() {
    tmux capture-pane -t "$1" -p -S -200 2>/dev/null | _plain
}

# 驱动交互：sudo 密码、可选包 TUI、模板 TUI、编辑器 TUI，直到总装完成
drive_interactive_install() {
    local session="$1"
    local sudo_pass="$2"
    local sent_pw=0
    local sent_opt=0
    local sent_tpl=0
    local sent_ed=0
    local max=$((90 * 30)) # 约 90 分钟（每轮 2s）
    local i=0

    while [ "$i" -lt "$max" ]; do
        sleep 2
        local pane
        pane="$(_capture "$session")"

        if [ "$sent_pw" -lt 25 ] && echo "$pane" | grep -qiE '\[sudo\]|password for'; then
            tmux send-keys -t "$session" "$sudo_pass" Enter
            sent_pw=$((sent_pw + 1))
            sleep 1
        fi

        if [ "$sent_opt" -eq 0 ] && echo "$pane" | grep -q '可选软件包'; then
            sleep 0.6
            tmux send-keys -t "$session" Enter
            sent_opt=1
            log "${session}: 已确认「可选软件包」TUI"
            sleep 1
        fi

        if [ "$sent_tpl" -eq 0 ] && echo "$pane" | grep -qE '配置模板|是否写入配置'; then
            sleep 0.6
            tmux send-keys -t "$session" Enter
            sent_tpl=1
            log "${session}: 已确认「配置模板」TUI"
            sleep 1
        fi

        if [ "$sent_ed" -eq 0 ] && echo "$pane" | grep -qE '默认编辑器|vim \(you'; then
            sleep 0.6
            tmux send-keys -t "$session" Enter
            sent_ed=1
            log "${session}: 已确认「默认编辑器」TUI"
            sleep 1
        fi

        # 仅在捕获区**末尾**判断完成，避免长滚动区内旧次 Complete 误判；匹配当前 install 日志关键词
        local tailpane
        tailpane="$(echo "$pane" | tail -n 50)"
        if echo "$tailpane" | grep -q '=== Installation Complete ===' \
            && echo "$tailpane" | grep -qE '基础工具包已处理|软件包与配置步骤完成'; then
            log "${session}: 检测到 Installation Complete（窗口末尾与本轮日志一致）"
            return 0
        fi

        # 重定向到文件时便于观察：每约 60s 打一行心跳
        if [ $((i % 30)) -eq 0 ] && [ "$i" -gt 0 ]; then
            log "${session}: 仍等待安装/TUI… (${i}/${max} 轮)"
        fi

        i=$((i + 1))
    done
    log "${session}: 等待超时"
    _capture "$session" | tail -40
    return 1
}

run_vm() {
    local session="$1"
    local sudo_pass="$2"

    log "========== ${session} =========="
    tmux clear-history -t "$session" 2>/dev/null || true
    tmux send-keys -t "$session" C-c
    sleep 0.4
    tmux send-keys -t "$session" 'cd /tmp' Enter
    sleep 0.3
    tmux send-keys -t "$session" 'reset' Enter
    sleep 0.8
    tmux send-keys -t "$session" 'clear' Enter
    sleep 0.3

    # 与文档一致：wget 落地再 bash；非管道。环境变量指向宿主机 HTTP 仓库镜像。
    # 必须拆成多行 send-keys：单行过长会在 tmux 窗格内折行，导致 URL 断裂、wget 失败或 bash 报 Permission denied。
    if [ "$session" = "vm-fedora" ]; then
        tmux send-keys -t "$session" "command -v wget >/dev/null || echo ${sudo_pass} | sudo -S dnf install -y wget" Enter
        sleep 3
    fi

    tmux send-keys -t "$session" "export STARMAN_INSTALLER_URL=${BASE_URL}/installers/install.sh" Enter
    sleep 0.15
    tmux send-keys -t "$session" "export STARMAN_GITEE_RAW=${BASE_URL}" Enter
    sleep 0.15
    tmux send-keys -t "$session" "export STARMAN_SKIP_OPTIONAL_FZF=1" Enter
    sleep 0.15
    tmux send-keys -t "$session" "wget -qO /tmp/bootstrap.sh ${BASE_URL}/installers/bootstrap.sh" Enter
    sleep 2
    tmux send-keys -t "$session" "bash /tmp/bootstrap.sh" Enter

    if drive_interactive_install "$session" "$sudo_pass"; then
        log "${session}: PASS"
        return 0
    fi
    log "${session}: FAIL"
    return 1
}

main() {
    HTTP_PID="$(http_start)"
    log "HTTP ${BASE_URL} PID=${HTTP_PID}（仓库根：${REPO_ROOT}）"
    sleep 1
    trap 'http_stop "${HTTP_PID}"' EXIT

    local failed=0
    run_vm vm-ubuntu ubuntu123 || failed=1
    run_vm vm-fedora fedora123 || failed=1

    http_stop "${HTTP_PID}"
    trap - EXIT

    if [ "$failed" -ne 0 ]; then
        log "存在失败的会话。"
        exit 1
    fi
    log "Ubuntu + Fedora 交互式安装测试完成。"
}

main "$@"
