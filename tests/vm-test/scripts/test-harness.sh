#!/bin/bash
#
# TUI Test Harness - TUI 测试执行器
#
# 用途：提供测试场景 DSL、断言库、测试执行器和人工介入点
#
# 用法示例：
#
#   source tests/vm-test/scripts/test-harness.sh
#
#   # 运行单个测试
#   run_test test_root_user_guide
#
#   # 运行所有测试
#   run_all_tests
#
# 依赖：vm-manager.sh, tmux-driver.sh
#

set -u

# ============================================================================
# 全局变量
# ============================================================================

TEST_PASS=0
TEST_FAIL=0
TEST_CURRENT=""
TEST_OUTPUT_LOG="/tmp/vm-test-output.log"

# ============================================================================
# 初始化
# ============================================================================

# 初始化测试环境
test_init() {
    # 获取脚本所在目录
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Source 依赖
    source "$script_dir/vm-manager.sh"
    source "$script_dir/tmux-driver.sh"

    # 重置计数器
    TEST_PASS=0
    TEST_FAIL=0

    # 清空日志
    > "$TEST_OUTPUT_LOG"

    echo "=== TUI Test Harness 初始化完成 ==="
}

# 清理测试环境
test_cleanup() {
    tmux_session_cleanup
    echo "=== 测试环境已清理 ==="
}

# ============================================================================
# 断言库
# ============================================================================

# 断言：文本包含
# 用法：assert_contains <text> [message]
assert_contains() {
    local text="$1"
    local message="${2:-文本包含检查}"
    local content
    content=$(tmux_capture_plain "$TUX_LAST_SESSION" 100)

    if echo "$content" | grep -qF "$text"; then
        log_assert_pass "$message"
        return 0
    else
        log_assert_fail "$message" "期望包含：$text"
        return 1
    fi
}

# 断言：正则匹配
# 用法：assert_matches <regex> [message]
assert_matches() {
    local regex="$1"
    local message="${2:-正则匹配检查}"
    local content
    content=$(tmux_capture_plain "$TUX_LAST_SESSION" 100)

    if echo "$content" | grep -qE "$regex"; then
        log_assert_pass "$message"
        return 0
    else
        log_assert_fail "$message" "期望匹配：$regex"
        return 1
    fi
}

# 断言：TUI 菜单项数量
# 用法：assert_tui_menu_count <count> [message]
assert_tui_menu_count() {
    local expected="$1"
    local message="${2:-菜单项数量检查}"
    local content
    content=$(tmux_capture_plain "$TUX_LAST_SESSION" 100)
    local count
    count=$(echo "$content" | grep -cE "^(> |  ) \[.\]" || echo "0")

    if [ "$count" -eq "$expected" ]; then
        log_assert_pass "$message (数量：$count)"
        return 0
    else
        log_assert_fail "$message" "期望：$expected, 实际：$count"
        return 1
    fi
}

# 断言：会话存在
# 用法：assert_session_exists [message]
assert_session_exists() {
    local message="${1:-会话存在检查}"

    if tmux has-session -t "$TUX_LAST_SESSION" 2>/dev/null; then
        log_assert_pass "$message"
        return 0
    else
        log_assert_fail "$message" "会话不存在"
        return 1
    fi
}

# 日志：断言通过
log_assert_pass() {
    local message="$1"
    echo "  ✓ $message" | tee -a "$TEST_OUTPUT_LOG"
}

# 日志：断言失败
log_assert_fail() {
    local message="$1"
    local reason="$2"
    echo "  ✗ $message - $reason" | tee -a "$TEST_OUTPUT_LOG"
}

# ============================================================================
# 测试执行器
# ============================================================================

# 运行单个测试
# 用法：run_test <test-name>
run_test() {
    local test_name="$1"
    local func_name="test_$test_name"

    TEST_CURRENT="$test_name"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "运行测试：$test_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 检查函数是否存在
    if ! type "$func_name" &>/dev/null; then
        echo "ERROR: 测试函数 '$func_name' 不存在" >&2
        TEST_FAIL=$((TEST_FAIL + 1))
        return 1
    fi

    # 执行测试
    set +e
    "$func_name"
    local result=$?
    set -e

    if [ "$result" -eq 0 ]; then
        echo ""
        echo "结果：PASS ✓"
        TEST_PASS=$((TEST_PASS + 1))
        return 0
    else
        echo ""
        echo "结果：FAIL ✗"
        TEST_FAIL=$((TEST_FAIL + 1))
        return 1
    fi
}

# 运行所有测试
# 用法：run_all_tests
run_all_tests() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║       运行所有 TUI 测试                  ║"
    echo "╚════════════════════════════════════════╝"

    test_init

    # 查找所有测试场景文件
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local scenarios_dir="$script_dir/../scenarios"

    if [ ! -d "$scenarios_dir" ]; then
        echo "ERROR: 测试场景目录不存在：$scenarios_dir" >&2
        return 1
    fi

    # 执行每个测试场景
    for scenario in "$scenarios_dir"/*.sh; do
        if [ -f "$scenario" ]; then
            # Source 测试场景文件
            source "$scenario"

            # 查找所有 test_* 函数
            local functions
            functions=$(declare -F | awk '/^test_/ {print $3}')

            for func in $functions; do
                run_test "${func#test_}"
            done
        fi
    done

    # 输出汇总
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "测试汇总"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "通过：$TEST_PASS"
    echo "失败：$TEST_FAIL"
    echo "总计：$((TEST_PASS + TEST_FAIL))"

    if [ "$TEST_FAIL" -eq 0 ]; then
        echo ""
        echo "所有测试通过！✓"
        return 0
    else
        echo ""
        echo "有测试失败！✗"
        return 1
    fi
}

# ============================================================================
# 人工介入点
# ============================================================================

# 请求人工介入（通过 notify-send 发送桌面通知）
# 用法：require_manual <message>
require_manual() {
    local message="$1"
    local marker_file="/tmp/vm-test-human-done"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "需要人工介入"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$message"
    echo ""
    echo "已发送桌面通知，请在完成后创建标记文件："
    echo "  touch $marker_file"
    echo ""

    # 发送桌面通知
    notify-send -u critical -t 0 "VM TUI 测试 - 需要人工介入" "$message"

    # 等待用户完成
    echo "等待用户操作..."
    while [ ! -f "$marker_file" ]; do
        sleep 2
    done

    # 清理标记文件
    rm -f "$marker_file"

    echo "用户操作完成，继续测试..."
    echo ""
}

# ============================================================================
# 测试结果报告
# ============================================================================

# 生成测试报告
# 用法：generate_test_report [output-file]
generate_test_report() {
    local output_file="${1:-/tmp/vm-test-report.txt}"

    {
        echo "╔════════════════════════════════════════╗"
        echo "║         TUI 测试报告                    ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        echo "日期：$(date)"
        echo ""
        echo "────────────────────────────────────────"
        echo "结果汇总"
        echo "────────────────────────────────────────"
        echo "通过：$TEST_PASS"
        echo "失败：$TEST_FAIL"
        echo "总计：$((TEST_PASS + TEST_FAIL))"
        echo ""
        echo "────────────────────────────────────────"
        echo "详细日志"
        echo "────────────────────────────────────────"
        cat "$TEST_OUTPUT_LOG"
    } > "$output_file"

    echo "测试报告已生成：$output_file"
}

# ============================================================================
# 测试场景示例（供参考）
# ============================================================================

# 测试示例：root 用户引导流程
# test_root_user_guide() {
#     vm_snapshot_restore "clean"
#     tmux_session_create "test" "./install.sh"
#     sleep 2
#
#     assert_contains "安全警告"
#     tmux_send_key "Enter"
#     assert_contains "请输入新用户名"
#     tmux_send_string "testuser"
#     tmux_send_key "Enter"
#     assert_contains "用户 testuser 创建成功"
#
#     tmux_session_destroy "test"
# }
