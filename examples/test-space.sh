#!/bin/bash
# 测试空格键输入

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/tui.sh"

echo "=== 空格键测试 ==="
echo "请在下方按空格键，然后按 Enter"

# 测试 1: 直接 read -n1
echo "测试 1: 按一个键..."
read -n1 key1
echo "读取到：[$key1]"

# 测试 2: 使用 IFS=
echo "测试 2: 再按一个键..."
IFS= read -n1 key2
echo "读取到：[$key2]"

# 测试 3: 使用 read -rs
echo "测试 3: 再按一个键..."
read -rs -n1 key3
echo "读取到：[$key3]"

# TUI 测试
echo ""
echo "=== TUI 菜单测试 ==="
tui_menu_create "按空格勾选"
menu_id="$TUI_LAST_MENU_ID"
tui_menu_add "$menu_id" "选项 A" "a" false
tui_menu_add "$menu_id" "选项 B" "b" false

tui_menu_run "$menu_id"
echo "结果：$TUI_LAST_RESULT"
