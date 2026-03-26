#!/bin/bash
# TUI Menu Test Script
# 测试 TUI 菜单 Enter 键功能

source scripts/lib/tui.sh

tui_menu_create "选择操作"
menu_id="$TUI_LAST_MENU_ID"
tui_menu_add "$menu_id" "新建 sudo 用户并迁移项目" "create_user" true
tui_menu_add "$menu_id" "切换到已有用户" "switch_user" false
tui_menu_add "$menu_id" "取消安装" "cancel" false

echo "=== TUI Menu Test ===" > /tmp/tui-test.log
echo "Start time: $(date)" >> /tmp/tui-test.log

result=$(tui_menu_run "$menu_id")
exit_code=$?

echo "Result: $result" >> /tmp/tui-test.log
echo "Exit code: $exit_code" >> /tmp/tui-test.log
echo "End time: $(date)" >> /tmp/tui-test.log

echo "$result"
exit $exit_code
