#!/bin/bash
# 简化的 TUI TMux 测试脚本 - 复用现有会话

set -e

SESSION="vm-ubuntu"
VM_USER="ubuntu"
VM_PASS="ubuntu123"

echo "=== TUI Menu TMux 自动化测试 ==="
echo ""

# 检查会话是否存在
if ! tmux list-sessions | grep -q "^$SESSION:"; then
    echo "错误：tmux 会话 $SESSION 不存在"
    exit 1
fi

echo "[1/5] 连接到现有 tmux 会话..."

# 发送 Enter 唤醒
echo "[2/5] 唤醒控制台..."
tmux send-keys -t "$SESSION" Enter
sleep 2

# 检查是否需要登录
output=$(tmux capture-pane -t "$SESSION" -p 2>&1 | tail -10)
if echo "$output" | grep -q "login:"; then
    echo "[3/5] 登录 - 输入用户名和密码..."
    tmux send-keys -t "$SESSION" "$VM_USER" Enter
    sleep 3
    tmux send-keys -t "$SESSION" "$VM_PASS" Enter
    sleep 5
else
    echo "[3/5] 已登录，跳过登录步骤..."
fi

# 运行 TUI 测试
echo "[4/5] 运行 TUI 菜单测试..."

# 通过 here-doc 方式运行测试脚本
tmux send-keys -t "$SESSION" "bash << 'TESTSCRIPT'" Enter
sleep 1
tmux send-keys -t "$SESSION" "source scripts/lib/tui.sh || source /home/adrian/code/misc/starman/scripts/lib/tui.sh" Enter
sleep 2
tmux send-keys -t "$SESSION" "tui_menu_create \"测试菜单\"" Enter
sleep 1
tmux send-keys -t "$SESSION" "menu_id=\"\$TUI_LAST_MENU_ID\"" Enter
sleep 1
tmux send-keys -t "$SESSION" "tui_menu_add \"\$menu_id\" \"选项 1\" \"opt1\" true" Enter
sleep 1
tmux send-keys -t "$SESSION" "tui_menu_add \"\$menu_id\" \"选项 2\" \"opt2\" false" Enter
sleep 1
tmux send-keys -t "$SESSION" "tui_menu_add \"\$menu_id\" \"选项 3\" \"opt3\" false" Enter
sleep 3

# 等待菜单渲染
echo "[5/5] 等待菜单渲染并测试按键..."
sleep 5

# 捕获菜单显示
echo ""
echo "=== 菜单显示状态 ==="
tmux capture-pane -t "$SESSION" -pS -100 2>&1 | tail -30

# 发送下移键
echo ""
echo "=== 发送下移键 (j) x2 ==="
tmux send-keys -t "$SESSION" "j"
sleep 2
tmux send-keys -t "$SESSION" "j"
sleep 2

# 捕获
echo "菜单选择后状态:"
tmux capture-pane -t "$SESSION" -pS -100 2>&1 | tail -30

# 发送 Enter
echo ""
echo "=== 发送 Enter 确认 ==="
tmux send-keys -t "$SESSION" Enter
sleep 5

# 最终捕获
echo ""
echo "=== 最终结果 ==="
tmux capture-pane -t "$SESSION" -pS -200 2>&1 | tail -50

echo ""
echo "=== 测试完成 ==="
