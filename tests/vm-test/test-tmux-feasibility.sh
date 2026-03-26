#!/bin/bash
#
# Tmux TUI 可行性测试脚本
#
# 测试目标：
# 1. 创建 tmux 会话运行交互式脚本
# 2. 向会话发送按键事件
# 3. 捕获窗口内容验证响应
#

set -e

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# 测试脚本：一个简单的 TUI 菜单
create_test_tui_script() {
    local script="$1"
    cat > "$script" << 'EOF'
#!/bin/bash
# 简单的 TUI 菜单测试脚本

items=("选项 A" "选项 B" "选项 C")
cursor=0

show_menu() {
    clear
    echo "=== TUI 测试菜单 ==="
    echo ""
    for i in "${!items[@]}"; do
        if [ "$i" -eq "$cursor" ]; then
            echo "> ${items[$i]}"
        else
            echo "  ${items[$i]}"
        fi
    done
    echo ""
    echo "操作：j/↓ 下移，k/↑ 上移，Enter 确认"
}

while true; do
    show_menu

    # 读取单个字符
    read -rn1 key

    case "$key" in
        $'\x1b')  # ESC 序列
            read -rn1 -t 0.1 seq1
            read -rn1 -t 0.1 seq2
            case "${seq1}${seq2}" in
                '[A') cursor=$((cursor - 1)); [ "$cursor" -lt 0 ] && cursor=2 ;;
                '[B') cursor=$((cursor + 1)); [ "$cursor" -gt 2 ] && cursor=0 ;;
            esac
            ;;
        j|J) cursor=$((cursor + 1)); [ "$cursor" -gt 2 ] && cursor=0 ;;
        k|K) cursor=$((cursor - 1)); [ "$cursor" -lt 0 ] && cursor=2 ;;
        $'\n'|$'\r'|'')
            echo ""
            echo "选中：${items[$cursor]}"
            break
            ;;
    esac
done
EOF
    chmod +x "$script"
}

# 测试主流程
run_test() {
    local session="tui-test-$$"
    local test_script="/tmp/tui-test-script-$$.sh"
    local output_file="/tmp/tui-output-$$.txt"

    log_info "=== Tmux TUI 可行性测试 ==="
    echo ""

    # 1. 创建测试脚本
    log_info "步骤 1: 创建测试 TUI 脚本"
    create_test_tui_script "$test_script"
    echo "  脚本位置：$test_script"

    # 2. 创建 tmux 会话
    log_info "步骤 2: 创建 tmux 会话 '$session'"
    if command -v tmux &>/dev/null; then
        tmux new-session -d -s "$session" "bash $test_script"
        echo "  会话创建成功"
    else
        log_error "tmux 未安装，测试无法继续"
        return 1
    fi

    # 等待脚本启动
    sleep 1

    # 3. 捕获初始窗口内容
    log_info "步骤 3: 捕获初始窗口内容"
    tmux capture-pane -t "$session" -p -S -100 > "$output_file"
    echo "  --- 初始内容 ---"
    cat "$output_file"
    echo "  ---------------"

    # 检查是否包含菜单标题
    if grep -q "TUI 测试菜单" "$output_file"; then
        log_info "✓ 菜单标题显示正确"
    else
        log_warn "✗ 菜单标题未找到"
    fi

    # 4. 发送按键 'j' (下移)
    log_info "步骤 4: 发送按键 'j' (下移)"
    tmux send-keys -t "$session" "j"
    sleep 0.5

    tmux capture-pane -t "$session" -p -S -100 > "$output_file"
    echo "  --- 发送 'j' 后 ---"
    cat "$output_file"
    echo "  ---------------"

    # 5. 再次发送 'j'
    log_info "步骤 5: 再次发送 'j'"
    tmux send-keys -t "$session" "j"
    sleep 0.5

    tmux capture-pane -t "$session" -p -S -100 > "$output_file"
    echo "  --- 再次发送 'j' 后 ---"
    cat "$output_file"
    echo "  ---------------"

    # 6. 发送 Enter 确认
    log_info "步骤 6: 发送 Enter 确认"
    tmux send-keys -t "$session" "Enter"
    sleep 0.5

    tmux capture-pane -t "$session" -p -S -100 > "$output_file"
    echo "  --- 发送 Enter 后 ---"
    cat "$output_file"
    echo "  ---------------"

    # 检查是否显示选中结果
    if grep -q "选中：" "$output_file"; then
        log_info "✓ Enter 确认成功，选中结果显示"
    else
        log_warn "✗ 未找到选中结果"
    fi

    # 7. 清理
    log_info "步骤 7: 清理 tmux 会话"
    tmux kill-session -t "$session" 2>/dev/null || true
    rm -f "$test_script" "$output_file"
    echo "  会话已销毁"

    echo ""
    log_info "=== 测试完成 ==="
}

# 检查 tmux 版本
check_tmux_version() {
    if command -v tmux &>/dev/null; then
        local version
        version=$(tmux -V 2>&1)
        log_info "tmux 版本：$version"
    else
        log_warn "tmux 未安装"
    fi
}

# 运行测试
check_tmux_version
echo ""
run_test
