#!/bin/bash
#
# 测试场景：root 用户引导流程
#
# 测试安装脚本检测到 root 用户时的 TUI 引导流程
#

# 测试：root 用户检测到
test_root_user_detected() {
    local session="${TUX_SESSION_PREFIX}root-detect"

    # 设置 tmux 会话（模拟 root 用户运行）
    tmux_session_create "$session" "sudo bash -c 'cd /home/adrian/code/misc/starman && ./installers/install.sh'"
    sleep 2

    # 断言：显示安全警告
    if assert_contains "安全警告" "检测到 root 用户警告"; then
        tmux_session_destroy "$session"
        return 0
    else
        tmux_session_destroy "$session"
        return 1
    fi
}

# 测试：TUI 菜单显示
test_root_user_menu_display() {
    local session="${TUX_SESSION_PREFIX}root-menu"

    tmux_session_create "$session" "sudo bash -c 'cd /home/adrian/code/misc/starman && ./installers/install.sh'"
    sleep 2

    # 断言：菜单包含三个选项
    assert_contains "新建 sudo 用户并迁移项目" "菜单项 1: 新建用户"
    assert_contains "切换到已有用户" "菜单项 2: 切换用户"
    assert_contains "取消安装" "菜单项 3: 取消安装"

    # 断言：菜单项数量为 3
    assert_tui_menu_count 3 "TUI 菜单项数量"

    tmux_session_destroy "$session"
}

# 测试：菜单导航
test_root_user_menu_navigation() {
    local session="${TUX_SESSION_PREFIX}root-nav"

    tmux_session_create "$session" "sudo bash -c 'cd /home/adrian/code/misc/starman && ./installers/install.sh'"
    sleep 2

    # 获取初始光标位置
    local initial_pos
    initial_pos=$(tui_get_cursor_position "$session")

    # 发送下移键
    tmux_send_key "$session" "j"
    sleep 0.5

    # 验证光标移动
    local new_pos
    new_pos=$(tui_get_cursor_position "$session")

    if [ "$new_pos" -gt "$initial_pos" ]; then
        echo "  ✓ 菜单导航：光标下移成功"
    else
        echo "  ✗ 菜单导航：光标未移动"
    fi

    tmux_session_destroy "$session"
}

# 测试：取消安装
test_root_user_cancel() {
    local session="${TUX_SESSION_PREFIX}root-cancel"

    # 注意：此测试需要手动操作，因为需要选择"取消安装"选项
    # 在实际运行时，需要先导航到"取消安装"选项，然后按 Enter

    echo "  提示：此测试需要人工介入来选择'取消安装'选项"
    require_manual "请在 tmux 会话中选择'取消安装'选项，然后按 Enter"

    # 断言：脚本已退出
    sleep 1
    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "  ✓ 取消安装：会话已关闭"
    else
        echo "  ✗ 取消安装：会话仍然存在"
        tmux_session_destroy "$session"
        return 1
    fi
}
