#!/bin/bash
# 简化的 install.sh root flow 测试

cd /home/ubuntu/starman
source scripts/lib/tui.sh

# 模拟 guide_root_user() 函数中的菜单
tui_menu_create "选择操作"
menu_id="$TUI_LAST_MENU_ID"
tui_menu_add "$menu_id" "新建 sudo 用户并迁移项目" "create_user" true
tui_menu_add "$menu_id" "切换到已有用户" "switch_user" false
tui_menu_add "$menu_id" "取消安装" "cancel" false

echo "=== 测试菜单显示 ==="
sleep 2

# 运行菜单（修复后的调用方式）
tui_menu_run "$menu_id"
result="$TUI_LAST_RESULT"

echo ""
echo "=== 测试结果 ==="
echo "返回值：$result"

case "$result" in
    create_user*)
        echo "选择：新建用户"
        ;;
    switch_user*)
        echo "选择：切换用户"
        ;;
    cancel*)
        echo "选择：取消安装"
        ;;
    *)
        echo "选择：未知或取消"
        ;;
esac

if [ -n "$result" ]; then
    echo "TEST PASSED: Enter 键功能正常"
    exit 0
else
    echo "TEST FAILED: Enter 键未返回结果"
    exit 1
fi
