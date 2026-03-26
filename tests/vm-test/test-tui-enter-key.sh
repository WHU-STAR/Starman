#!/bin/bash
# 简化的 TUI TMux 测试脚本

set -e

SESSION="tui-test-$$"
VM_NAME="ubuntu22-test"
VM_USER="ubuntu"
VM_PASS="ubuntu123"

echo "=== TUI Menu TMux 自动化测试 ==="
echo ""

# 创建 tmux 会话连接到 VM 控制台
echo "[1/6] 创建 tmux 会话连接到 $VM_NAME..."
tmux new-session -d -s "$SESSION" "virsh -c qemu:///session console $VM_NAME"
sleep 8

# 发送 Enter 唤醒登录提示
echo "[2/6] 唤醒登录提示..."
tmux send-keys -t "$SESSION" Enter
sleep 2

# 输入用户名
echo "[3/6] 登录 - 输入用户名..."
tmux send-keys -t "$SESSION" "$VM_USER" Enter
sleep 3

# 输入密码
echo "[4/6] 登录 - 输入密码..."
tmux send-keys -t "$SESSION" "$VM_PASS" Enter
sleep 5

# 运行 TUI 测试脚本
echo "[5/6] 运行 TUI 菜单测试..."
tmux send-keys -t "$SESSION" "bash -s" Enter
sleep 2

# 发送测试脚本内容
tmux send-keys -t "$SESSION" 'source /home/adrian/code/misc/starman/scripts/lib/tui.sh' Enter
sleep 1
tmux send-keys -t "$SESSION" 'tui_menu_create "测试菜单"' Enter
sleep 1
tmux send-keys -t "$SESSION" 'menu_id="$TUI_LAST_MENU_ID"' Enter
sleep 1
tmux send-keys -t "$SESSION" 'tui_menu_add "$menu_id" "选项 1" "opt1" true' Enter
sleep 1
tmux send-keys -t "$SESSION" 'tui_menu_add "$menu_id" "选项 2" "opt2" false' Enter
sleep 1
tmux send-keys -t "$SESSION" 'tui_menu_add "$menu_id" "选项 3" "opt3" false' Enter
sleep 2

# 等待菜单渲染
echo "[6/6] 等待菜单渲染并发送按键..."
sleep 3

# 发送下移键（j）
echo "     -> 发送下移键 (j)..."
tmux send-keys -t "$SESSION" "j"
sleep 2

# 再发送一次下移
echo "     -> 再次发送下移键 (j)..."
tmux send-keys -t "$SESSION" "j"
sleep 2

# 发送 Enter 确认
echo "     -> 发送 Enter 确认..."
tmux send-keys -t "$SESSION" Enter
sleep 3

# 捕获输出
echo ""
echo "=== 捕获测试结果 ==="
output=$(tmux capture-pane -t "$SESSION" -pS -500 2>&1)
echo "$output" | tail -100

# 检查是否有结果输出
if echo "$output" | grep -q "结果:"; then
    echo ""
    echo "✓ 测试通过：TUI 菜单返回了结果"
    echo "$output" | grep "结果:"
else
    echo ""
    echo "✗ 测试失败：未检测到 TUI 菜单结果"
fi

# 清理
echo ""
echo "=== 清理 ==="
tmux kill-session -t "$SESSION" 2>/dev/null || true
echo "tmux 会话已销毁"
