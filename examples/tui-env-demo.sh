#!/bin/bash
#
# TUI 环境变量配置演示脚本
#
# 用途：演示如何使用 TUI 库的配置式选项功能
# 运行：bash examples/tui-env-demo.sh
#

set -e

# 获取脚本所在目录
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    local dir="$(cd "$(dirname "$source")" && pwd)"
    echo "$dir"
}

SCRIPT_DIR="$(get_script_dir)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 源入 TUI 库
if [ -f "$PROJECT_ROOT/scripts/lib/tui.sh" ]; then
    source "$SCRIPT_DIR/../scripts/lib/tui.sh"
else
    echo "ERROR: 找不到 scripts/lib/tui.sh" >&2
    exit 1
fi

# 启用调试模式（可选）
# export TUI_DEBUG=true

# 初始化菜单（注意：不要使用 menu_id=$(tui_menu_create ...)，因为关联数组在 subshell 中无法传递）
tui_menu_create "系统配置选项"
menu_id="$TUI_LAST_MENU_ID"

# 添加勾选式选项
tui_menu_add "$menu_id" "Docker" "docker" true
tui_menu_add "$menu_id" "Linuxbrew" "brew" false
tui_menu_add "$menu_id" "Neovim" "neovim" true

# 添加配置式选项
# 时区选择
tui_menu_add "$menu_id" "时区" "timezone" false
tui_menu_set_options "$menu_id" 3 "Asia/Shanghai" "America/New_York" "Europe/London" "Asia/Tokyo"

# 语言选择
tui_menu_add "$menu_id" "语言" "locale" false
tui_menu_set_options "$menu_id" 4 "zh_CN.UTF-8" "en_US.UTF-8" "ja_JP.UTF-8"

# 编辑器选择
tui_menu_add "$menu_id" "编辑器" "editor" false
tui_menu_set_options "$menu_id" 5 "vim" "neovim" "nano" "code"

# 运行菜单
echo "正在启动 TUI 菜单..."
echo ""
tui_menu_run "$menu_id"
result="$TUI_LAST_RESULT"

# 显示结果
echo ""
echo "=========================================="
echo "选择结果:"
echo "=========================================="
echo "$result"
echo ""

# 解析结果
echo "=========================================="
echo "解析结果:"
echo "=========================================="

checked=$(tui_parse_result "$result" "CHECKED")
if [ -n "$checked" ]; then
    echo "已勾选的项：$checked"
fi

values=$(tui_parse_result "$result" "VALUE")
if [ -n "$values" ]; then
    echo "配置式选项："
    # values 是空格分隔的字符串：3:America/New_York 4:zh_CN.UTF-8 5:vim
    for item in $values; do
        if [ -n "$item" ]; then
            idx="${item%%:*}"
            value="${item#*:}"
            case "$idx" in
                3) echo "  时区：$value" ;;
                4) echo "  语言：$value" ;;
                5) echo "  编辑器：$value" ;;
            esac
        fi
    done
fi

echo ""
echo "完成!"
