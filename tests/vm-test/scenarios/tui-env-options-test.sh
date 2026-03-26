#!/bin/bash
#
# 测试场景：TUI 配置式选项左右键切换测试
#
# 用途：测试配置式选项（时区、语言、编辑器）的左右键切换功能
#
# 运行：bash tests/vm-test/scenarios/tui-env-options-test.sh
#

set -u

# ============================================================================
# 初始化
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/tmux-driver.sh"
source "$SCRIPT_DIR/../scripts/test-harness.sh"

SESSION_NAME="test-tui-env-$$"
DEMO_SCRIPT="$SCRIPT_DIR/../../../examples/tui-env-demo.sh"

# ============================================================================
# 测试辅助函数
# ============================================================================

# 设置测试：启动 TUI 演示脚本
setup_test() {
    echo "正在启动 TUI 演示脚本..."
    tmux_session_create "$SESSION_NAME" "bash $DEMO_SCRIPT"
    sleep 1  # 等待 TUI 渲染
}

# 清理测试
cleanup_test() {
    echo "正在清理测试会话..."
    tmux_session_destroy "$SESSION_NAME"
}

# 等待 TUI 渲染
wait_tui_render() {
    sleep 0.8
}

# ============================================================================
# 测试用例
# ============================================================================

# 测试 1：初始渲染检查
test_initial_render() {
    echo "测试：初始渲染检查"

    local content
    content=$(tmux_capture_plain "$SESSION_NAME" 50)

    # 检查菜单标题
    if echo "$content" | grep -q "系统配置选项"; then
        echo "  ✓ 菜单标题显示正确"
    else
        echo "  ✗ 菜单标题未显示"
        return 1
    fi

    # 检查勾选式选项
    if echo "$content" | grep -q "Docker"; then
        echo "  ✓ Docker 选项显示正确"
    else
        echo "  ✗ Docker 选项未显示"
        return 1
    fi

    # 检查配置式选项
    if echo "$content" | grep -q "时区"; then
        echo "  ✓ 时区选项显示正确"
    else
        echo "  ✗ 时区选项未显示"
        return 1
    fi

    if echo "$content" | grep -q "Asia/Shanghai"; then
        echo "  ✓ 时区默认值显示正确 (Asia/Shanghai)"
    else
        echo "  ✗ 时区默认值未显示"
        return 1
    fi

    # 检查语言选项
    if echo "$content" | grep -q "语言"; then
        echo "  ✓ 语言选项显示正确"
    else
        echo "  ✗ 语言选项未显示"
        return 1
    fi

    # 检查编辑器选项
    if echo "$content" | grep -q "编辑器"; then
        echo "  ✓ 编辑器选项显示正确"
    else
        echo "  ✗ 编辑器选项未显示"
        return 1
    fi

    # 检查底部提示
    if echo "$content" | grep -q "切换"; then
        echo "  ✓ 底部操作提示显示正确"
    else
        echo "  ✗ 底部操作提示未显示"
        return 1
    fi

    return 0
}

# 测试 2：下移导航到配置式选项
test_down_navigation() {
    echo "测试：下移导航到配置式选项"

    # 初始光标在第 0 项（Docker）
    # 下移 3 次到达时区选项（索引 3）
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render

    local content
    content=$(tmux_capture_plain "$SESSION_NAME" 50)

    # 检查光标是否在时区选项行（> 前缀）
    if echo "$content" | grep -q "> .*时区"; then
        echo "  ✓ 光标移动到时区选项"
    else
        echo "  ✗ 光标未移动到时区选项"
        return 1
    fi

    return 0
}

# 测试 3：右移切换时区值
test_right_switch_timezone() {
    echo "测试：右移切换时区值"

    # 确保光标在时区选项（从初始位置下移 3 次）
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render

    # 初始值应为 Asia/Shanghai
    # 按右移切换到下一个值
    tmux_send_key "$SESSION_NAME" "l"  # 使用 l 键代替 Right
    wait_tui_render

    local content
    content=$(tmux_capture_plain "$SESSION_NAME" 50)

    # 检查时区值是否变为 America/New_York
    if echo "$content" | grep -q "America/New_York"; then
        echo "  ✓ l 键切换时区到 America/New_York"
    else
        echo "  ✗ l 键切换时区失败"
        echo "  捕获内容："
        echo "$content" | grep -i "时区" | head -5
        return 1
    fi

    return 0
}

# 测试 4：左移切换时区值
test_left_switch_timezone() {
    echo "测试：左移切换时区值"

    # 确保光标在时区选项
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render

    # 先右移一次
    tmux_send_key "$SESSION_NAME" "l"
    wait_tui_render

    # 再左移切换回上一个值
    tmux_send_key "$SESSION_NAME" "h"
    wait_tui_render

    local content
    content=$(tmux_capture_plain "$SESSION_NAME" 50)

    # 检查时区值是否回到 Asia/Shanghai
    if echo "$content" | grep -q "Asia/Shanghai"; then
        echo "  ✓ h 键切换时区回到 Asia/Shanghai"
    else
        echo "  ✗ h 键切换时区失败"
        return 1
    fi

    return 0
}

# 测试 5：循环切换（从第一项到最后一项）
test_wrap_around_left() {
    echo "测试：循环切换（左移从第一项到最后一项）"

    # 确保光标在时区选项
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render

    # 直接按左移（当前是 Asia/Shanghai，第一项）
    # 应该循环到最后一项 Asia/Tokyo
    tmux_send_key "$SESSION_NAME" "h"
    wait_tui_render

    local content
    content=$(tmux_capture_plain "$SESSION_NAME" 50)

    # 应该循环到最后一项 Asia/Tokyo
    if echo "$content" | grep -q "Asia/Tokyo"; then
        echo "  ✓ h 键循环到最后一项 Asia/Tokyo"
    else
        echo "  ✗ 循环切换失败"
        echo "  捕获内容："
        echo "$content" | grep -i "时区" | head -5
        return 1
    fi

    return 0
}

# 测试 6：h/l 键切换测试
test_h_l_switch() {
    echo "测试：h/l 键切换"

    # 确保光标在时区选项
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render

    # 使用 l 键右移
    tmux_send_key "$SESSION_NAME" "l"
    wait_tui_render

    local content
    content=$(tmux_capture_plain "$SESSION_NAME" 50)

    if echo "$content" | grep -q "America/New_York"; then
        echo "  ✓ l 键切换时区到 America/New_York"
    else
        echo "  ✗ l 键切换失败"
        return 1
    fi

    # 使用 h 键左移
    tmux_send_key "$SESSION_NAME" "h"
    wait_tui_render

    content=$(tmux_capture_plain "$SESSION_NAME" 50)

    if echo "$content" | grep -q "Asia/Shanghai"; then
        echo "  ✓ h 键切换时区回到 Asia/Shanghai"
    else
        echo "  ✗ h 键切换失败"
        return 1
    fi

    return 0
}

# 测试 7：语言选项切换
test_language_switch() {
    echo "测试：语言选项切换"

    # 下移到语言选项（索引 4，需要下移 4 次）
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render

    # 初始值应为 zh_CN.UTF-8
    # 按右移切换到下一个值
    tmux_send_key "$SESSION_NAME" "l"
    wait_tui_render

    local content
    content=$(tmux_capture_plain "$SESSION_NAME" 50)

    if echo "$content" | grep -q "en_US.UTF-8"; then
        echo "  ✓ l 键切换语言到 en_US.UTF-8"
    else
        echo "  ✗ 语言切换失败"
        echo "  捕获内容："
        echo "$content" | grep -i "语言" | head -5
        return 1
    fi

    return 0
}

# 测试 8：编辑器选项切换
test_editor_switch() {
    echo "测试：编辑器选项切换"

    # 下移到编辑器选项（索引 5，需要下移 5 次）
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render

    # 初始值应为 vim
    # 按右移切换到下一个值
    tmux_send_key "$SESSION_NAME" "l"
    wait_tui_render

    local content
    content=$(tmux_capture_plain "$SESSION_NAME" 50)

    if echo "$content" | grep -q "neovim"; then
        echo "  ✓ l 键切换编辑器到 neovim"
    else
        echo "  ✗ 编辑器切换失败"
        echo "  捕获内容："
        echo "$content" | grep -i "编辑器" | head -5
        return 1
    fi

    return 0
}

# 测试 9：Enter 确认并检查返回值
test_enter_confirm() {
    echo "测试：Enter 确认并检查返回值"

    # 下移到时区选项
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render
    tmux_send_key "$SESSION_NAME" "j"
    wait_tui_render

    # 发送 l 键切换时区
    tmux_send_key "$SESSION_NAME" "l"
    wait_tui_render

    # 发送 Enter 确认（脚本会退出）
    tmux_send_key "$SESSION_NAME" "Enter"
    sleep 3

    # Enter 后脚本退出，会话会被销毁
    # 所以这里只检查会话是否已退出（正常行为）
    if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo "  ✓ Enter 后脚本正常退出"
        return 0
    else
        # 如果会话还在，捕获内容检查结果
        local content
        content=$(tmux_capture_plain "$SESSION_NAME" 50)

        if echo "$content" | grep -q "VALUE:"; then
            echo "  ✓ Enter 后显示 VALUE 结果"
        elif echo "$content" | grep -q "选择结果"; then
            echo "  ✓ Enter 后显示选择结果"
        else
            echo "  ✗ Enter 后未显示结果"
            echo "  捕获内容："
            echo "$content" | tail -20
            return 1
        fi
    fi

    return 0
}

# 测试 10：混合菜单渲染（勾选式 + 配置式）
test_mixed_menu_render() {
    echo "测试：混合菜单渲染"

    # 重新启动会话以获取初始状态
    tmux_session_destroy "$SESSION_NAME"
    tmux_session_create "$SESSION_NAME" "bash $DEMO_SCRIPT"
    sleep 1

    local content
    content=$(tmux_capture_plain "$SESSION_NAME" 50)

    # 检查勾选式标记
    if echo "$content" | grep -qE "\[.\].*Docker"; then
        echo "  ✓ 勾选式选项格式正确"
    else
        echo "  ✗ 勾选式选项格式错误"
        return 1
    fi

    # 检查配置式标记格式 [标签] 值
    if echo "$content" | grep -qE "\[时区\].*Asia/Shanghai"; then
        echo "  ✓ 配置式选项格式正确"
    else
        echo "  ✗ 配置式选项格式错误"
        echo "  捕获内容："
        echo "$content" | head -20
        return 1
    fi

    return 0
}

# ============================================================================
# 主测试流程
# ============================================================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     TUI 配置式选项左右键切换测试                     ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo ""

    # 初始化
    test_init

    # 设置测试
    setup_test

    # 运行测试
    local pass=0
    local fail=0

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if test_initial_render; then
        ((pass++))
    else
        ((fail++))
    fi
    echo ""

    # 重启会话以获取干净状态
    cleanup_test
    setup_test

    if test_down_navigation; then
        ((pass++))
    else
        ((fail++))
    fi
    echo ""

    # 重启会话以获取干净状态
    cleanup_test
    setup_test

    if test_right_switch_timezone; then
        ((pass++))
    else
        ((fail++))
    fi
    echo ""

    # 重启会话以获取干净状态
    cleanup_test
    setup_test

    if test_left_switch_timezone; then
        ((pass++))
    else
        ((fail++))
    fi
    echo ""

    # 重启会话以获取干净状态
    cleanup_test
    setup_test

    if test_wrap_around_left; then
        ((pass++))
    else
        ((fail++))
    fi
    echo ""

    # 重启会话以获取干净状态
    cleanup_test
    setup_test

    if test_h_l_switch; then
        ((pass++))
    else
        ((fail++))
    fi
    echo ""

    # 重启会话以获取干净状态
    cleanup_test
    setup_test

    if test_language_switch; then
        ((pass++))
    else
        ((fail++))
    fi
    echo ""

    # 重启会话以获取干净状态
    cleanup_test
    setup_test

    if test_editor_switch; then
        ((pass++))
    else
        ((fail++))
    fi
    echo ""

    # 重启会话以获取干净状态
    cleanup_test
    setup_test

    if test_enter_confirm; then
        ((pass++))
    else
        ((fail++))
    fi
    echo ""

    # 重启会话以获取干净状态
    cleanup_test
    setup_test

    if test_mixed_menu_render; then
        ((pass++))
    else
        ((fail++))
    fi
    echo ""

    # 清理
    cleanup_test

    # 输出汇总
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "测试汇总"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "通过：$pass"
    echo "失败：$fail"
    echo "总计：$((pass + fail))"
    echo ""

    if [ "$fail" -eq 0 ]; then
        echo "所有测试通过！✓"
        return 0
    else
        echo "有测试失败！✗"
        return 1
    fi
}

# 运行主流程
main "$@"
