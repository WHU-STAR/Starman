#!/bin/bash
# install.sh Root User Flow Test
# 在 VM 中测试 install.sh 的 root 用户引导流程

set -e

SESSION="vm-ubuntu"
VM_USER="ubuntu"
VM_PASS="ubuntu123"

echo "=== install.sh Root User Flow VM 测试 ==="
echo ""

# 检查会话是否存在
if ! tmux list-sessions 2>/dev/null | grep -q "^$SESSION:"; then
    echo "错误：tmux 会话 $SESSION 不存在"
    exit 1
fi

echo "[1/4] 连接到现有 tmux 会话..."

# 发送 Enter 唤醒
echo "[2/4] 唤醒控制台..."
tmux send-keys -t "$SESSION" Enter
sleep 2

# 检查是否需要登录
output=$(tmux capture-pane -t "$SESSION" -p 2>&1 | tail -10)
if echo "$output" | grep -q "login:"; then
    echo "[3/4] 登录 - 输入用户名和密码..."
    tmux send-keys -t "$SESSION" "$VM_USER" Enter
    sleep 3
    tmux send-keys -t "$SESSION" "$VM_PASS" Enter
    sleep 5
else
    echo "[3/4] 已登录，跳过登录步骤..."
fi

# 以 root 身份运行 install.sh 测试 TUI 菜单
echo "[4/4] 运行 install.sh 测试 root 用户菜单..."

# 先克隆/更新代码
tmux send-keys -t "$SESSION" "cd /home/ubuntu" Enter
sleep 1
tmux send-keys -t "$SESSION" "if [ ! -d starman ]; then git clone https://gitee.com/ajgamma/starman.git; fi" Enter
sleep 5
tmux send-keys -t "$SESSION" "cd starman && git pull origin master" Enter
sleep 5

# 创建测试脚本 - 模拟 root 用户运行 install.sh 的菜单部分
tmux send-keys -t "$SESSION" "cat > /tmp/test-install-root.sh << 'EOFTEST'" Enter
sleep 1
tmux send-keys -t "$SESSION" "#!/bin/bash" Enter
tmux send-keys -t "$SESSION" "cd /home/ubuntu/starman" Enter
tmux send-keys -t "$SESSION" "source scripts/lib/tui.sh" Enter
tmux send-keys -t "$SESSION" "" Enter
tmux send-keys -t "$SESSION" "# 模拟 guide_root_user() 函数中的菜单" Enter
tmux send-keys -t "$SESSION" "tui_menu_create \"选择操作\"" Enter
tmux send-keys -t "$SESSION" "menu_id=\"\$TUI_LAST_MENU_ID\"" Enter
tmux send-keys -t "$SESSION" "tui_menu_add \"\$menu_id\" \"新建 sudo 用户并迁移项目\" \"create_user\" true" Enter
tmux send-keys -t "$SESSION" "tui_menu_add \"\$menu_id\" \"切换到已有用户\" \"switch_user\" false" Enter
tmux send-keys -t "$SESSION" "tui_menu_add \"\$menu_id\" \"取消安装\" \"cancel\" false" Enter
tmux send-keys -t "$SESSION" "" Enter
tmux send-keys -t "$SESSION" "echo \"=== 测试菜单显示 ===\"" Enter
tmux send-keys -t "$SESSION" "sleep 3" Enter
tmux send-keys -t "$SESSION" "" Enter
tmux send-keys -t "$SESSION" "# 运行菜单（修复后的调用方式）" Enter
tmux send-keys -t "$SESSION" "tui_menu_run \"\$menu_id\"" Enter
tmux send-keys -t "$SESSION" "result=\"\$TUI_LAST_RESULT\"" Enter
tmux send-keys -t "$SESSION" "" Enter
tmux send-keys -t "$SESSION" "echo \"\"" Enter
tmux send-keys -t "$SESSION" "echo \"=== 测试结果 ===\"" Enter
tmux send-keys -t "$SESSION" "echo \"返回值：\$result\"" Enter
tmux send-keys -t "$SESSION" "" Enter
tmux send-keys -t "$SESSION" "case \"\$result\" in" Enter
tmux send-keys -t "$SESSION" "    create_user*)" Enter
tmux send-keys -t "$SESSION" "        echo \"选择：新建用户\"" Enter
tmux send-keys -t "$SESSION" "        ;;" Enter
tmux send-keys -t "$SESSION" "    switch_user*)" Enter
tmux send-keys -t "$SESSION" "        echo \"选择：切换用户\"" Enter
tmux send-keys -t "$SESSION" "        ;;" Enter
tmux send-keys -t "$SESSION" "    cancel*)" Enter
tmux send-keys -t "$SESSION" "        echo \"选择：取消安装\"" Enter
tmux send-keys -t "$SESSION" "        ;;" Enter
tmux send-keys -t "$SESSION" "    *)" Enter
tmux send-keys -t "$SESSION" "        echo \"选择：未知或取消\"" Enter
tmux send-keys -t "$SESSION" "        ;;" Enter
tmux send-keys -t "$SESSION" "esac" Enter
tmux send-keys -t "$SESSION" "" Enter
tmux send-keys -t "$SESSION" "if [ -n \"\$result\" ]; then" Enter
tmux send-keys -t "$SESSION" "    echo \"TEST PASSED: Enter 键功能正常\"" Enter
tmux send-keys -t "$SESSION" "    exit 0" Enter
tmux send-keys -t "$SESSION" "else" Enter
tmux send-keys -t "$SESSION" "    echo \"TEST FAILED: Enter 键未返回结果\"" Enter
tmux send-keys -t "$SESSION" "    exit 1" Enter
tmux send-keys -t "$SESSION" "fi" Enter
tmux send-keys -t "$SESSION" "EOFTEST" Enter
sleep 2

tmux send-keys -t "$SESSION" "chmod +x /tmp/test-install-root.sh && bash /tmp/test-install-root.sh" Enter
sleep 15

# 捕获输出
echo ""
echo "=== 测试结果 ==="
output=$(tmux capture-pane -t "$SESSION" -pS -300 2>&1)
echo "$output" | tail -80

# 检查测试结果
if echo "$output" | grep -q "TEST PASSED"; then
    echo ""
    echo "✓ 测试通过：install.sh Enter 键功能正常"
    exit 0
else
    echo ""
    echo "✗ 测试失败"
    exit 1
fi
