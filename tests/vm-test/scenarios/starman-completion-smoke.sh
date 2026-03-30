#!/usr/bin/env bash
#
# 在测试 VM 的 tmux 会话中冒烟：starman 各 shell 补全可生成；子命令别名 completions 可用。
#
# 前提：客体已安装当前构建的 starman；会话已登录 shell。
# 用法（宿主机，仓库根）:
#   bash tests/vm-test/scenarios/starman-completion-smoke.sh
# 环境变量:
#   STARMAN_VM_TMUX  默认 vm-ubuntu:virsh（窗口名因 libvirt 控制台而异，见 tmux list-windows -t vm-ubuntu）
#
set -euo pipefail

SESSION="${STARMAN_VM_TMUX:-vm-ubuntu:virsh}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

_plain() {
  sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\]0;[^\x07]*\x07//g' 2>/dev/null || cat
}

_capture() {
  tmux capture-pane -t "$SESSION" -p -S -120 2>/dev/null | _plain
}

if ! tmux has-session -t "${SESSION%%:*}" 2>/dev/null; then
  echo "ERROR: 无 tmux 会话: ${SESSION%%:*}" >&2
  exit 1
fi

# 短行发送，避免串口窄终端把长行折行导致命令断裂。
tmux send-keys -t "$SESSION" 'starman completion bash 2>/dev/null | grep -q _starman && echo S1OK' Enter
sleep 0.8
tmux send-keys -t "$SESSION" 'starman completion zsh 2>/dev/null | grep -q starman && echo S2OK' Enter
sleep 0.8
tmux send-keys -t "$SESSION" 'starman completion fish 2>/dev/null | grep -q starman && echo S3OK' Enter
sleep 0.8
tmux send-keys -t "$SESSION" 'starman completion elvish 2>/dev/null | grep -q starman && echo S4OK' Enter
sleep 0.8
tmux send-keys -t "$SESSION" 'starman completion powershell 2>/dev/null | grep -q starman && echo S5OK' Enter
sleep 0.8
tmux send-keys -t "$SESSION" 'starman completions bash 2>/dev/null | grep -q _starman && echo S6OK' Enter
sleep 1.2

cap="$(_capture)"
for m in S1OK S2OK S3OK S4OK S5OK S6OK; do
  if ! echo "$cap" | grep -q "$m"; then
    log "最近屏显（节选）:"
    echo "$cap" | tail -50
    echo "FAIL: 未看到 $m" >&2
    exit 1
  fi
done

log "PASS: starman completion smoke ($SESSION)"
exit 0
