#!/bin/bash
#
# 测试场景：root 用户安装引导流程
#
# 测试内容：
# 1. root 用户执行 install.sh 时显示安全警告和 TUI 菜单
# 2. 新建用户流程（用户名输入、密码设置、自动重执行）
# 3. 切换已有用户流程
# 4. --from-root 参数跳过 root 引导
#
# 运行方式：在 VM 中以 root 执行
#   bash tests/vm-test/scenarios/root-install-guard-test.sh
#
# 前置条件：
# - 在 CentOS/Ubuntu 测试虚拟机中运行
# - 以 root 用户执行
# - 项目代码已同步到 VM
#

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../../.."

source "$SCRIPT_DIR/../scripts/tmux-driver.sh"

SESSION_PREFIX="test-root-guard"
INSTALL_SCRIPT="$PROJECT_ROOT/installers/install.sh"

pass=0
fail=0

# ============================================================================
# 辅助函数
# ============================================================================

wait_render() { sleep 1.5; }
wait_key() { sleep 0.5; }

report_result() {
    local name="$1" result="$2"
    if [ "$result" -eq 0 ]; then
        echo "  ✓ $name"
        ((pass++))
    else
        echo "  ✗ $name"
        ((fail++))
    fi
}

# ============================================================================
# 测试 1：root 执行时显示安全警告和 TUI 菜单
# ============================================================================

test_root_shows_menu() {
    echo ""
    echo "测试 1：root 执行时显示安全警告和 TUI 菜单"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local session="${SESSION_PREFIX}-menu-$$"
    tmux_session_create "$session" "bash $INSTALL_SCRIPT"
    wait_render

    local content
    content=$(tmux_capture_plain "$session" 50)

    # 检查安全警告
    echo "$content" | grep -qF "安全警告"
    report_result "显示安全警告" $?

    # 检查菜单选项
    echo "$content" | grep -q "新建 sudo 用户"
    report_result "显示'新建 sudo 用户'选项" $?

    echo "$content" | grep -q "切换到已有用户"
    report_result "显示'切换到已有用户'选项" $?

    echo "$content" | grep -q "取消安装"
    report_result "显示'取消安装'选项" $?

    # 发送 ESC 退出
    tmux_send_key "$session" "Escape"
    sleep 0.5
    tmux_session_destroy "$session"
}

# ============================================================================
# 测试 2：新建用户流程 — 用户名验证
# ============================================================================

test_create_user_invalid_name() {
    echo ""
    echo "测试 2：新建用户流程 — 用户名验证"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local session="${SESSION_PREFIX}-invalid-$$"
    tmux_session_create "$session" "bash $INSTALL_SCRIPT"
    wait_render

    # 选择"新建 sudo 用户"（第一项已选中，直接 Enter）
    tmux_send_key "$session" "Enter"
    wait_render

    # 输入无效用户名（含大写字母）
    tmux_send_string "$session" "BadUser"
    tmux_send_key "$session" "Enter"
    wait_render

    local content
    content=$(tmux_capture_plain "$session" 50)

    echo "$content" | grep -q "无效的用户名"
    report_result "无效用户名时显示错误" $?

    tmux_send_key "$session" "Enter"
    sleep 0.3
    tmux_send_key "$session" "Escape"
    sleep 0.3
    tmux_session_destroy "$session"
}

# ============================================================================
# 测试 3：新建用户完整流程（创建+密码+自动重执行）
# ============================================================================

test_create_user_full_flow() {
    echo ""
    echo "测试 3：新建用户完整流程"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local testuser="startest$$"
    local session="${SESSION_PREFIX}-create-$$"

    # 确保测试用户不存在
    userdel -r "$testuser" 2>/dev/null || true

    tmux_session_create "$session" "bash $INSTALL_SCRIPT"
    wait_render

    # 选择"新建 sudo 用户"
    tmux_send_key "$session" "Enter"
    wait_render

    # 输入用户名
    tmux_send_string "$session" "$testuser"
    tmux_send_key "$session" "Enter"
    wait_render

    # 输入密码（两次）
    tmux_send_string "$session" "Test1234"
    tmux_send_key "$session" "Enter"
    wait_render
    tmux_send_string "$session" "Test1234"
    tmux_send_key "$session" "Enter"
    sleep 3

    local content
    content=$(tmux_capture_plain "$session" 100)

    # 检查用户是否被创建
    id "$testuser" &>/dev/null
    report_result "用户 $testuser 已创建" $?

    # 检查是否触发了自动重执行（--from-root 标志生效）
    echo "$content" | grep -q "root 用户引导切换"
    report_result "自动重执行触发（--from-root 生效）" $?

    # 清理
    tmux_session_destroy "$session" 2>/dev/null
    userdel -r "$testuser" 2>/dev/null || true
}

# ============================================================================
# 测试 4：切换已有用户流程
# ============================================================================

test_switch_user_flow() {
    echo ""
    echo "测试 4：切换已有用户流程"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 确保至少有一个非 root 用户（检查 /home 下的目录）
    local has_users=false
    for dir in /home/*/; do
        [ -d "$dir" ] && has_users=true && break
    done

    if [ "$has_users" = false ]; then
        echo "  跳过：无可用非 root 用户"
        return
    fi

    local session="${SESSION_PREFIX}-switch-$$"
    tmux_session_create "$session" "bash $INSTALL_SCRIPT"
    wait_render

    # 下移到"切换到已有用户"
    tmux_send_key "$session" "j"
    wait_key
    tmux_send_key "$session" "Enter"
    wait_render

    local content
    content=$(tmux_capture_plain "$session" 50)

    # 检查是否显示用户列表菜单
    echo "$content" | grep -q "选择用户"
    report_result "显示用户选择菜单" $?

    # 发送 ESC 退出
    tmux_send_key "$session" "Escape"
    sleep 0.5
    tmux_session_destroy "$session"
}

# ============================================================================
# 测试 5：--from-root 参数跳过 root 引导
# ============================================================================

test_from_root_flag() {
    echo ""
    echo "测试 5：--from-root 参数跳过 root 引导"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local session="${SESSION_PREFIX}-flag-$$"
    tmux_session_create "$session" "bash $INSTALL_SCRIPT --from-root"
    sleep 3

    local content
    content=$(tmux_capture_plain "$session" 100)

    # 不应出现安全警告（已跳过 guide_root_user）
    ! echo "$content" | grep -qF "安全警告"
    report_result "--from-root 跳过安全警告" $?

    # 应出现引导切换成功的提示
    echo "$content" | grep -q "root 用户引导切换"
    report_result "显示引导切换成功提示" $?

    tmux_session_destroy "$session" 2>/dev/null
}

# ============================================================================
# 主流程
# ============================================================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     Root 用户安装引导流程测试                       ║"
    echo "╚════════════════════════════════════════════════════╝"

    # 检查是否以 root 运行
    if [ "$(id -u)" != "0" ]; then
        echo "错误：此测试脚本需要以 root 用户运行"
        echo "  sudo bash $0"
        exit 1
    fi

    test_root_shows_menu
    test_create_user_invalid_name
    test_create_user_full_flow
    test_switch_user_flow
    test_from_root_flag

    # 汇总
    echo ""
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

main "$@"
