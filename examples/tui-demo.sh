#!/bin/bash
#
# TUI Demo - 演示 TUI 库的使用
#
# 用法：./examples/tui-demo.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/tui.sh"

echo "========================================"
echo "  TUI Baseline 演示"
echo "========================================"
echo ""
echo "按 Enter 开始演示..."
read -r

# 创建菜单
tui_menu_create "请选择要安装的软件包"
menu_id="$TUI_LAST_MENU_ID"

# 添加菜单项
tui_menu_add "$menu_id" "Docker" "docker" true
tui_menu_add "$menu_id" "Linuxbrew" "brew" true
tui_menu_add "$menu_id" "Neovim" "neovim" false
tui_menu_add "$menu_id" "Node.js" "nodejs" false
tui_menu_add "$menu_id" "Python3" "python3" true
tui_menu_add "$menu_id" "Golang" "golang" false
tui_menu_add "$menu_id" "Java" "java" false

# 运行菜单
echo "启动 TUI 菜单，使用 ↑↓ 或 j/k 移动，空格勾选，Enter 确认"
sleep 2
read -r -p "按 Enter 继续..."

tui_menu_run "$menu_id"
result="$TUI_LAST_RESULT"

echo ""
echo "========================================"
echo "  选择结果"
echo "========================================"
echo "选中的项：$result"
echo ""

# 解析结果（用 | 分隔）
echo "已选中的软件包："
IFS='|' read -ra PACKAGES <<< "$result"
for pkg in "${PACKAGES[@]}"; do
    echo "  - $pkg"
done
echo ""
