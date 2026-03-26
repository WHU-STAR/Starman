#!/bin/bash
# TUI Enter Key Local Test
# 测试修复后的 Enter 键功能

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/lib/tui.sh"

echo "=== TUI Enter Key 本地测试 ==="
echo ""

# 模拟安装脚本的菜单逻辑
tui_menu_create "选择操作"
menu_id="$TUI_LAST_MENU_ID"
tui_menu_add "$menu_id" "新建 sudo 用户并迁移项目" "create_user" true
tui_menu_add "$menu_id" "切换到已有用户" "switch_user" false
tui_menu_add "$menu_id" "取消安装" "cancel" false

echo "菜单已创建，请按："
echo "  j/k - 上下移动"
echo "  Enter - 确认选择"
echo "  q - 退出"
echo ""

# 修复后的调用方式 - 不使用子 shell
tui_menu_run "$menu_id"
result="$TUI_LAST_RESULT"

echo ""
echo "=== 测试结果 ==="
echo "返回值：$result"

case "$result" in
    create_user*)
        echo "操作：新建用户"
        ;;
    switch_user*)
        echo "操作：切换用户"
        ;;
    cancel*)
        echo "操作：取消安装"
        ;;
    *)
        echo "操作：未知或取消"
        ;;
esac
