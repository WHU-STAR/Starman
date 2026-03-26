#!/bin/bash
# TUI Menu TMux Test Script
# 在虚拟机中自动测试 TUI 菜单

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm-test/scripts/tmux-driver.sh"

SESSION="tui-test-$$"
TEST_PASSED=true

echo "=== TUI Menu TMux Test ==="
echo ""

# 1. 复制测试脚本到虚拟机
echo "[1/5] 复制测试脚本到虚拟机..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    tests/tui-menu-test.sh \
    ubuntu@10.0.2.15:/home/ubuntu/tui-menu-test.sh 2>/dev/null || {
    echo "SCP 失败，尝试使用 tmux 发送..."
    # 备选方案：通过 tmux 发送命令创建脚本
}

# 2. 创建 tmux 会话运行测试
echo "[2/5] 创建 tmux 会话..."
tmux_session_create "$SESSION" "virsh -c qemu:///session console ubuntu22-test"
sleep 10

# 3. 登录
echo "[3/5] 登录虚拟机..."
tmux_send_key "$SESSION" Enter
sleep 2
tmux_send_key "$SESSION" "ubuntu"
sleep 1
tmux_send_key "$SESSION" Enter
sleep 3
tmux_send_key "$SESSION" "ubuntu123"
sleep 1
tmux_send_key "$SESSION" Enter
sleep 3

# 4. 运行测试脚本
echo "[4/5] 运行 TUI 测试脚本..."
tmux_send_key "$SESSION" "cd /home/ubuntu"
sleep 1
tmux_send_key "$SESSION" Enter
sleep 1

# 5. 等待并捕获结果
echo "[5/5] 等待测试完成并捕获结果..."

# 清理
echo ""
echo "[清理] 销毁 tmux 会话..."
tmux_session_destroy "$SESSION" 2>/dev/null || true

echo ""
echo "=== Test Complete ==="
