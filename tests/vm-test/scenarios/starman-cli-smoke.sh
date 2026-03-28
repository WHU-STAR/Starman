#!/usr/bin/env bash
#
# 宿主机冒烟：tmux 会话中运行 starman（需已 cargo build -p starman）。
# 不销毁持久 VM 会话（vm-ubuntu 等）；使用临时会话。
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BIN="${STARMAN_BIN:-$ROOT/target/debug/starman}"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/target/release/starman"
fi
if [[ ! -x "$BIN" ]]; then
  echo "找不到 starman 二进制，请先: cd $ROOT && cargo build -p starman" >&2
  exit 1
fi

SESSION="starman-smoke-$$"
tmux new-session -d -s "$SESSION" "$BIN" version
sleep 0.3
OUT=$(tmux capture-pane -t "$SESSION" -p -S -20 || true)
tmux kill-session -t "$SESSION" 2>/dev/null || true

if [[ "$OUT" != *"starman"* ]]; then
  echo "FAIL: expected version output, got:" >&2
  echo "$OUT" >&2
  exit 1
fi

echo "PASS: starman version in tmux"
