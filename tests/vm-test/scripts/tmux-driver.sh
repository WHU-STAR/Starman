#!/bin/bash
#
# Tmux TUI Driver - 通过 tmux 会话发送按键并捕获 TUI 状态
#
# 用途：提供 tmux 会话管理、按键发送、窗口内容捕获等功能
#
# 用法示例：
#
#   source tests/vm-test/scripts/tmux-driver.sh
#
#   # 创建会话
#   tmux_session_create "test" "./install.sh"
#
#   # 发送按键
#   tmux_send_key "j"        # 下移
#   tmux_send_key "Enter"    # 确认
#   tmux_send_key "Space"    # 空格
#
#   # 捕获内容
#   tmux_capture             # 捕获当前窗口内容
#   tmux_capture_plain       # 捕获并去除 ANSI 序列
#
#   # 解析 TUI 状态
#   tui_get_menu_items       # 获取菜单项
#   tui_get_cursor_position  # 获取光标位置
#
# 依赖：tmux
#

set -u

# ============================================================================
# 全局变量
# ============================================================================

TUX_SESSION_PREFIX="vm-tui-test-"
TUX_LAST_SESSION=""

# ============================================================================
# tmux 会话管理
# ============================================================================

# 创建 tmux 会话
# 用法：tmux_session_create <session-name> <command>
tmux_session_create() {
    local session_name="$1"
    local command="$2"

    if [ -z "$session_name" ] || [ -z "$command" ]; then
        echo "ERROR: 请指定会话名称和命令" >&2
        return 1
    fi

    # 检查会话是否已存在
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "WARN: 会话 '$session_name' 已存在，先销毁" >&2
        tmux_session_destroy "$session_name"
    fi

    # 创建后台会话
    tmux new-session -d -s "$session_name" "$command"
    TUX_LAST_SESSION="$session_name"

    echo "会话 '$session_name' 已创建"
}

# 列出所有测试会话
tmux_session_list() {
    echo "=== VM TUI 测试会话 ==="
    tmux list-sessions 2>/dev/null | grep "$TUX_SESSION_PREFIX" || echo "(无)"
}

# 销毁会话
# 用法：tmux_session_destroy <session-name>
tmux_session_destroy() {
    local session_name="$1"

    if [ -z "$session_name" ]; then
        session_name="$TUX_LAST_SESSION"
    fi

    if [ -z "$session_name" ]; then
        echo "ERROR: 未指定会话名称" >&2
        return 1
    fi

    if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux kill-session -t "$session_name"
        echo "会话 '$session_name' 已销毁"
    else
        echo "WARN: 会话 '$session_name' 不存在" >&2
    fi
}

# 清理所有测试会话
tmux_session_cleanup() {
    echo "正在清理所有测试会话..."
    tmux list-sessions -F "#{session_name}" 2>/dev/null | \
        grep "^$TUX_SESSION_PREFIX" | \
        while read -r session; do
            tmux kill-session -t "$session" 2>/dev/null
        done
    echo "清理完成"
}

# ============================================================================
# 按键发送
# ============================================================================

# 发送按键到会话
# 用法：tmux_send_key <session-name> <key>
tmux_send_key() {
    local session_name="$1"
    local key="$2"

    if [ -z "$session_name" ] || [ -z "$key" ]; then
        echo "ERROR: 请指定会话名称和按键" >&2
        return 1
    fi

    if ! tmux has-session -t "$session_name" 2>/dev/null; then
        echo "ERROR: 会话 '$session_name' 不存在" >&2
        return 1
    fi

    # 特殊键映射
    case "$key" in
        Enter|enter)
            tmux send-keys -t "$session_name" "Enter"
            ;;
        Space|space|" ")
            tmux send-keys -t "$session_name" "Space"
            ;;
        Tab|tab)
            tmux send-keys -t "$session_name" "Tab"
            ;;
        Escape|escape)
            tmux send-keys -t "$session_name" "Escape"
            ;;
        Up|up)
            tmux send-keys -t "$session_name" "Up"
            ;;
        Down|down)
            tmux send-keys -t "$session_name" "Down"
            ;;
        Left|left)
            tmux send-keys -t "$session_name" "Left"
            ;;
        Right|right)
            tmux send-keys -t "$session_name" "Right"
            ;;
        C-c)
            tmux send-keys -t "$session_name" "C-c"
            ;;
        *)
            # 单字符直接发送
            tmux send-keys -t "$session_name" "$key"
            ;;
    esac
}

# 发送字符串
# 用法：tmux_send_string <session-name> <text>
tmux_send_string() {
    local session_name="$1"
    local text="$2"

    if [ -z "$text" ]; then
        return 0
    fi

    # 逐字符发送
    for ((i=0; i<${#text}; i++)); do
        tmux send-keys -t "$session_name" "${text:$i:1}"
    done
}

# ============================================================================
# 窗口内容捕获
# ============================================================================

# 捕获窗口内容（保留 ANSI 序列）
# 用法：tmux_capture <session-name> [lines]
tmux_capture() {
    local session_name="$1"
    local lines="${2:-100}"

    if [ -z "$session_name" ]; then
        session_name="$TUX_LAST_SESSION"
    fi

    if ! tmux has-session -t "$session_name" 2>/dev/null; then
        echo "ERROR: 会话 '$session_name' 不存在" >&2
        return 1
    fi

    tmux capture-pane -t "$session_name" -p -S "-$lines"
}

# 捕获窗口内容（纯文本，去除 ANSI 序列）
# 用法：tmux_capture_plain <session-name> [lines]
tmux_capture_plain() {
    local session_name="$1"
    local lines="${2:-100}"

    tmux_capture "$session_name" "$lines" | ansi_strip
}

# 捕获到文件
# 用法：tmux_capture_to_file <session-name> <output-file>
tmux_capture_to_file() {
    local session_name="$1"
    local output_file="$2"

    if [ -z "$output_file" ]; then
        echo "ERROR: 请指定输出文件" >&2
        return 1
    fi

    tmux_capture "$session_name" 200 > "$output_file"
}

# ============================================================================
# ANSI 转义序列处理
# ============================================================================

# 去除 ANSI 转义序列
# 用法：ansi_strip <input>
ansi_strip() {
    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\]0;[^\x07]*\x07//g; s/\x1b[=><]//g'
}

# 提取颜色信息
# 用法：ansi_extract_colors <input>
ansi_extract_colors() {
    grep -o '\x1b\[[0-9;]*m' | sort -u
}

# ============================================================================
# TUI 状态解析
# ============================================================================

# 获取 TUI 菜单项
# 用法：tui_get_menu_items <session-name>
# 输出：每行一个菜单项，格式为 "文本 [选中]"
tui_get_menu_items() {
    local session_name="$1"
    local content
    content=$(tmux_capture_plain "$session_name" 50)

    # 查找菜单项模式（以 "> " 或 "  " 开头的行）
    echo "$content" | grep -E "^(\>|  ) \[" | while read -r line; do
        local prefix
        prefix=$(echo "$line" | cut -c1-2)
        local text
        text=$(echo "$line" | sed 's/^[> ]* \[.\] //')
        local status
        if [[ "$prefix" == "> " ]]; then
            status="[cursor]"
        else
            status=""
        fi
        echo "$text $status"
    done
}

# 获取光标位置（选中的菜单项索引）
# 用法：tui_get_cursor_position <session-name>
tui_get_cursor_position() {
    local session_name="$1"
    local content
    content=$(tmux_capture_plain "$session_name" 50)

    # 查找以 "> " 开头的行
    local index=0
    local found=0
    while IFS= read -r line; do
        if [[ "$line" == "> "* ]]; then
            echo "$index"
            found=1
            break
        fi
        # 只统计菜单项行
        if [[ "$line" == "  "* ]] || [[ "$line" == "> "* ]]; then
            index=$((index + 1))
        fi
    done <<< "$content"

    if [ "$found" -eq 0 ]; then
        echo "-1"
    fi
}

# 获取已勾选的项目
# 用法：tui_get_checked_items <session-name>
tui_get_checked_items() {
    local session_name="$1"
    local content
    content=$(tmux_capture_plain "$session_name" 50)

    # 查找已勾选的项 [x] 或 [✓]
    echo "$content" | grep -E "\[(x|✓)\]" | sed 's/.*\[(x|✓)\] //'
}

# ============================================================================
# 断言辅助
# ============================================================================

# 检查输出是否包含指定文本
# 用法：assert_contains_text <session-name> <text>
assert_contains_text() {
    local session_name="$1"
    local text="$2"

    local content
    content=$(tmux_capture_plain "$session_name" 100)

    if echo "$content" | grep -qF "$text"; then
        return 0
    else
        return 1
    fi
}

# 检查输出是否匹配正则表达式
# 用法：assert_matches_text <session-name> <regex>
assert_matches_text() {
    local session_name="$1"
    local regex="$2"

    local content
    content=$(tmux_capture_plain "$session_name" 100)

    if echo "$content" | grep -qE "$regex"; then
        return 0
    else
        return 1
    fi
}
