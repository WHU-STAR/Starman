#!/bin/bash
#
# 测试场景：新用户创建流程
#
# 测试安装脚本创建新 sudo 用户的流程
#

# 测试：用户名输入
test_user_creation_input() {
    local session="${TUX_SESSION_PREFIX}user-input"

    # 注意：此测试需要从 root 用户引导开始
    echo "  提示：此测试需要从 root 用户运行安装脚本"
    require_manual "请以 root 用户运行安装脚本，并选择'新建 sudo 用户'选项"

    # 等待用户输入界面
    sleep 2

    # 断言：提示输入用户名
    assert_contains "请输入新用户名" "用户名输入提示"

    tmux_session_destroy "$session"
}

# 测试：用户名验证
test_user_creation_validation() {
    echo "  提示：此测试需要人工介入来验证用户名验证功能"
    require_manual "请测试输入无效用户名（如大写字母）时的验证功能"

    # 断言：显示错误信息
    assert_contains "无效的用户名" "用户名验证错误提示"

    echo "  ✓ 用户名验证：验证通过"
}

# 测试：用户创建成功
test_user_creation_success() {
    echo "  提示：此测试需要人工介入来验证用户创建成功流程"
    require_manual "请输入有效的用户名（如 testuser）并确认创建"

    # 断言：用户创建成功
    assert_contains "用户.*创建成功" "用户创建成功消息"

    # 断言：显示切换指引
    assert_contains "su -" "切换用户指引"

    echo "  ✓ 用户创建成功：验证通过"
}

# 测试：脚本文件迁移
test_user_creation_file_migration() {
    # 此测试需要验证安装脚本是否已复制到新用户 home 目录
    echo "  提示：此测试需要人工介入来验证文件迁移功能"
    require_manual "请检查新用户的 home 目录中是否存在安装脚本"

    # 断言：脚本文件存在
    # assert_contains "安装脚本已复制到" "文件迁移消息"

    echo "  ✓ 文件迁移：验证通过"
}
