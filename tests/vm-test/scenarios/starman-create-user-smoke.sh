#!/usr/bin/env bash
#
# 在 ubuntu22-test（tmux vm-ubuntu:virsh）中冒烟 starman create-user：建用户、组、标记块（--no-brew 跳过 brew）。
#
# 用法（宿主机）:
#   bash tests/vm-test/scenarios/starman-create-user-smoke.sh
# 环境变量:
#   STARMAN_VM_TMUX  默认 vm-ubuntu:virsh
#   STARMAN_TEST_USER 默认 starman_smoke_u1
#
set -euo pipefail

SESSION="${STARMAN_VM_TMUX:-vm-ubuntu:virsh}"
TUSER="${STARMAN_TEST_USER:-starman_smoke_u1}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

_plain() {
  sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' 2>/dev/null || cat
}

_capture() {
  tmux capture-pane -t "$SESSION" -p -S -120 2>/dev/null | _plain
}

if ! tmux has-session -t "${SESSION%%:*}" 2>/dev/null; then
  echo "ERROR: 无 tmux 会话: ${SESSION%%:*}" >&2
  exit 1
fi

# 使用 sudo -S 避免多次交互式密码（测试用户密码见 starman-vm-tmux-test skill）
tmux send-keys -t "$SESSION" "bash -lc 'echo ubuntu123 | sudo -S userdel -r ${TUSER} 2>/dev/null || true; echo ubuntu123 | sudo -S starman create-user ${TUSER} -g lab --no-brew'" Enter
sleep 6

ok=0
for _ in $(seq 1 30); do
  if _capture | grep -q "已创建用户 ${TUSER}"; then
    ok=1
    break
  fi
  sleep 0.5
done

if [[ "$ok" -ne 1 ]]; then
  log "未看到成功提示，最近屏显:"
  _capture | tail -45
  exit 1
fi

tmux send-keys -t "$SESSION" "grep -q 'starman user init' /home/${TUSER}/.bashrc && echo MARK_OK" Enter
sleep 1
tmux send-keys -t "$SESSION" "groups ${TUSER} | grep -q lab && echo GROUP_OK" Enter
sleep 1

cap="$(_capture)"
if ! echo "$cap" | grep -q MARK_OK; then
  log "未找到 .bashrc 标记块"
  _capture | tail -30
  exit 1
fi
if ! echo "$cap" | grep -q GROUP_OK; then
  log "用户未在 lab 组"
  _capture | tail -30
  exit 1
fi

log "PASS: create-user smoke (${TUSER})"
exit 0
