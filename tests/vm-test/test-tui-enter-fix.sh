#!/bin/bash
# TUI Enter Key VM Test - 使用现有会话
# 验证 install.sh 修复后的 Enter 键功能

set -e

SESSION="vm-ubuntu"
VM_USER="ubuntu"
VM_PASS="ubuntu123"

echo "=== TUI Enter Key VM 自动化测试 (使用现有会话) ==="
echo ""

# 检查会话是否存在
if ! tmux list-sessions 2>/dev/null | grep -q "^$SESSION:"; then
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

# 准备测试环境
echo "[4/5] 准备测试环境..."
tmux send-keys -t "$SESSION" "cd /home/ubuntu/starman && git pull origin master" Enter
sleep 5

# 创建并运行测试脚本
echo "[5/5] 运行 Enter 键测试..."

# 发送测试脚本
tmux send-keys -t "$SESSION" "cat > /tmp/test-enter.sh << 'EOFTEST'" Enter
sleep 1
tmux send-keys -t "$SESSION" "#!/bin/bash" Enter
tmux send-keys -t "$SESSION" "cd /home/ubuntu/starman" Enter
tmux send-keys -t "$SESSION" "source scripts/lib/tui.sh" Enter
tmux send-keys -t "$SESSION" "tui_menu_create \"测试 Enter 键\"" Enter
tmux send-keys -t "$SESSION" "menu_id=\"\$TUI_LAST_MENU_ID\"" Enter
tmux send-keys -t "$SESSION" "tui_menu_add \"\$menu_id\" \"选项 1\" \"opt1\" true" Enter
tmux send-keys -t "$SESSION" "tui_menu_add \"\$menu_id\" \"选项 2\" \"opt2\" false" Enter
tmux send-keys -t "$SESSION" "tui_menu_add \"\$menu_id\" \"取消\" \"cancel\" false" Enter
tmux send-keys -t "$SESSION" "echo \"=== 菜单已显示，等待 2 秒 ===\"" Enter
tmux send-keys -t "$SESSION" "sleep 2" Enter
tmux send-keys -t "$SESSION" "tui_menu_run \"\$menu_id\"" Enter
tmux send-keys -t "$SESSION" "echo \"TUI_LAST_RESULT=\$TUI_LAST_RESULT\"" Enter
tmux send-keys -t "$SESSION" "if [ -n \"\$TUI_LAST_RESULT\" ]; then" Enter
tmux send-keys -t "$SESSION" "  echo \"TEST PASSED: Enter 键返回结果：\$TUI_LAST_RESULT\"" Enter
tmux send-keys -t "$SESSION" "  exit 0" Enter
tmux send-keys -t "$SESSION" "else" Enter
tmux send-keys -t "$SESSION" "  echo \"TEST FAILED: TUI_LAST_RESULT 为空\"" Enter
tmux send-keys -t "$SESSION" "  exit 1" Enter
tmux send-keys -t "$SESSION" "fi" Enter
tmux send-keys -t "$SESSION" "EOFTEST" Enter
sleep 2

tmux send-keys -t "$SESSION" "chmod +x /tmp/test-enter.sh && bash /tmp/test-enter.sh" Enter
sleep 8

# 捕获输出
echo ""
echo "=== 测试结果 ==="
output=$(tmux capture-pane -t "$SESSION" -pS -200 2>&1)
echo "$output" | tail -60

# 检查测试结果
if echo "$output" | grep -q "TEST PASSED"; then
    echo ""
    echo "✓ 测试通过：Enter 键功能正常"
else
    echo ""
    echo "✗ 测试失败：Enter 键未返回结果"
    echo ""
    echo "检查是否包含 TUI_LAST_RESULT=..."
    if echo "$output" | grep "TUI_LAST_RESULT="; then
        echo "检测到 TUI_LAST_RESULT 输出"
    else
        echo "未检测到 TUI_LAST_RESULT 输出"
    fi
fi
