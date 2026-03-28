#!/bin/bash
#
# TUI Baseline - 纯 Bash 交互式菜单库
#
# 用途：提供零外部依赖的 TUI 菜单功能，支持 ↑↓/j/k 移动、空格勾选、←→/hl 切换选项、Enter 确认
#
# 用法示例：
#
#   source scripts/lib/tui.sh
#
#   # 初始化菜单（注意：不要使用 menu_id=$(tui_menu_create ...)，因为关联数组在 subshell 中无法传递）
#   tui_menu_create "请选择要安装的软件包"
#   menu_id="$TUI_LAST_MENU_ID"
#
#   # 添加菜单项
#   tui_menu_add "$menu_id" "Docker" "docker" true
#   tui_menu_add "$menu_id" "Linuxbrew" "brew" true
#   tui_menu_add "$menu_id" "Neovim" "neovim" false
#
#   # 设置配置式选项（新增）
#   tui_menu_set_options "$menu_id" 3 "zh_CN.UTF-8" "en_US.UTF-8"
#
#   # 运行菜单，获取结果
#   result=$(tui_menu_run "$menu_id")
#   echo "选中的项：$result"
#
#   # 解析结果（新增）
#   checked=$(tui_parse_result "$result" "CHECKED")
#   values=$(tui_parse_result "$result" "VALUE")
#
# 依赖：无（纯 Bash + ANSI 转义序列）
#

set -u

# ============================================================================
# ANSI 转义序列常量
# ============================================================================

# 颜色
TUI_RED=$'\033[0;31m'
TUI_GREEN=$'\033[0;32m'
TUI_YELLOW=$'\033[1;33m'
TUI_BLUE=$'\033[0;34m'
TUI_WHITE=$'\033[1;37m'
TUI_NC=$'\033[0m'  # No Color

# 光标控制
TUI_CLEAR=$'\033[2J'     # 清屏
TUI_CLEAR_LINE=$'\033[2K' # 清当前行
TUI_MOVE_HOME=$'\033[H'   # 光标归位 (1,1)
TUI_HIDE=$'\033[?25l'    # 隐藏光标
TUI_SHOW=$'\033[?25h'    # 显示光标

# 样式
TUI_BOLD=$'\033[1m'
TUI_REVERSE=$'\033[7m'
TUI_RESET=$'\033[0m'

# ============================================================================
# 全局变量
# ============================================================================

# 菜单数据存储（关联数组，需要 Bash 4+）
declare -A TUI_MENU_TITLE
declare -A TUI_MENU_ITEMS_TEXT
declare -A TUI_MENU_ITEMS_VALUE
declare -A TUI_MENU_ITEMS_CHECKED
declare -A TUI_MENU_ITEMS_TYPE      # 选项类型："checkbox" 或 "options"
declare -A TUI_MENU_ITEMS_OPTIONS   # 可选项列表（分号分隔）
declare -A TUI_MENU_ITEMS_CURRENT   # 配置式选项的当前值
declare -A TUI_MENU_CURSOR
declare -A TUI_MENU_COUNT
declare -A TUI_MENU_MODE        # 菜单模式："multi"（多选，默认）或 "radio"（单选）

# 菜单项数 >= 此值时，上下键仅增量重绘两行，减轻卡顿（可 export TUI_MENU_FAST_MIN 覆盖）
TUI_MENU_FAST_MIN="${TUI_MENU_FAST_MIN:-8}"

# 检测标志
TUI_USE_TPUT=false
TUI_USE_COLOR=true

# tput 缓存（避免重复调用）
TUI_TPUT_CLEAR=""
TUI_TPUT_HOME=""
TUI_TPUT_HIDE=""
TUI_TPUT_SHOW=""
TUI_TPUT_BOLD=""
TUI_TPUT_RESET=""

# ============================================================================
# 初始化：检测环境
# ============================================================================

tui_detect() {
    # 检测 tput 是否可用
    if command -v tput &>/dev/null; then
        TUI_USE_TPUT=true
        # 缓存 tput 输出
        TUI_TPUT_CLEAR=$(tput clear 2>/dev/null) || TUI_TPUT_CLEAR=$'\033[2J'
        TUI_TPUT_HOME=$(tput cup 0 0 2>/dev/null) || TUI_TPUT_HOME=$'\033[H'
        TUI_TPUT_HIDE=$(tput civis 2>/dev/null) || TUI_TPUT_HIDE=$'\033[?25l'
        TUI_TPUT_SHOW=$(tput cnorm 2>/dev/null) || TUI_TPUT_SHOW=$'\033[?25h'
        TUI_TPUT_BOLD=$(tput bold 2>/dev/null) || TUI_TPUT_BOLD=$'\033[1m'
        TUI_TPUT_RESET=$(tput sgr0 2>/dev/null) || TUI_TPUT_RESET=$'\033[0m'
        TUI_TPUT_REVERSE=$(tput rev 2>/dev/null) || TUI_TPUT_REVERSE=$'\033[7m'
        TUI_TPUT_WHITE=$(tput setaf 15 2>/dev/null) || TUI_TPUT_WHITE=$'\033[1;37m'
    fi

    # 检测终端是否支持颜色
    if [ "$TERM" = "dumb" ] || [ -z "$TERM" ]; then
        TUI_USE_COLOR=false
    fi

    # 检查是否支持颜色变量
    if [ -n "${NO_COLOR:-}" ]; then
        TUI_USE_COLOR=false
    fi
}

# 自动检测（源文件时自动调用）
tui_detect

# ============================================================================
# 工具函数
# ============================================================================

# 清屏并归位（输出到 stderr）
tui_clear() {
    if [ "$TUI_USE_TPUT" = "true" ]; then
        printf '%s' "$TUI_TPUT_CLEAR$TUI_TPUT_HOME" >&2
    else
        printf '\033[2J\033[H' >&2
    fi
}

# 移动光标到指定位置 (row, col)（输出到 stderr）
tui_move_cursor() {
    local row="${1:-1}"
    local col="${2:-1}"
    if [ "$TUI_USE_TPUT" = "true" ]; then
        tput cup "$row" "$col" >&2
    else
        printf '\033[%s;%sH' "$row" "$col" >&2
    fi
}

# 隐藏光标（输出到 stderr）
tui_hide_cursor() {
    if [ "$TUI_USE_TPUT" = "true" ]; then
        printf '%s' "$TUI_TPUT_HIDE" >&2
    else
        printf '%b' "$TUI_HIDE" >&2
    fi
}

# 显示光标（输出到 stderr）
tui_show_cursor() {
    if [ "$TUI_USE_TPUT" = "true" ]; then
        printf '%s' "$TUI_TPUT_SHOW" >&2
    else
        printf '%b' "$TUI_SHOW" >&2
    fi
}

# 清理：恢复光标显示等（输出到 stderr）
tui_cleanup() {
    tui_show_cursor
    if [ "$TUI_USE_TPUT" = "true" ]; then
        printf '%s' "$TUI_TPUT_RESET" >&2
    else
        printf '%b' "$TUI_RESET" >&2
    fi
}

# 彩色打印（自动降级）
tui_print_color() {
    local color="$1"
    shift
    local text="$*"

    if [ "$TUI_USE_COLOR" = true ]; then
        printf '%b%s%b\n' "$color" "$text" "$TUI_NC"
    else
        printf '%s\n' "$text"
    fi
}

# ============================================================================
# 菜单函数
# ============================================================================

# 最后一个创建的菜单 ID（用于避免子 shell 问题）
TUI_LAST_MENU_ID=""
# 最后一个菜单结果（用于避免子 shell 问题）
TUI_LAST_RESULT=""

# 创建菜单（设置 TUI_LAST_MENU_ID 变量）
# 用法：tui_menu_create "标题"
#       menu_id="$TUI_LAST_MENU_ID"
tui_menu_create() {
    local title="${1:-菜单}"
    TUI_LAST_MENU_ID="menu_$$"

    TUI_MENU_TITLE["$TUI_LAST_MENU_ID"]="$title"
    TUI_MENU_ITEMS_TEXT["$TUI_LAST_MENU_ID"]=""
    TUI_MENU_ITEMS_VALUE["$TUI_LAST_MENU_ID"]=""
    TUI_MENU_ITEMS_CHECKED["$TUI_LAST_MENU_ID"]=""
    TUI_MENU_ITEMS_TYPE["$TUI_LAST_MENU_ID"]=""
    TUI_MENU_ITEMS_OPTIONS["$TUI_LAST_MENU_ID"]=""
    TUI_MENU_ITEMS_CURRENT["$TUI_LAST_MENU_ID"]=""
    TUI_MENU_CURSOR["$TUI_LAST_MENU_ID"]=0
    TUI_MENU_COUNT["$TUI_LAST_MENU_ID"]=0
    TUI_MENU_MODE["$TUI_LAST_MENU_ID"]="multi"
}

# 设置菜单为单选模式
# 用法：tui_menu_set_radio <menu_id>
tui_menu_set_radio() {
    local menu_id="$1"
    TUI_MENU_MODE["$menu_id"]="radio"
}

# 添加菜单项
# 用法：tui_menu_add <menu_id> <显示文本> <返回值> [checked]
tui_menu_add() {
    local menu_id="$1"
    local text="$2"
    local value="$3"
    local checked="${4:-false}"

    local idx="${TUI_MENU_COUNT[$menu_id]:-0}"
    local current_text="${TUI_MENU_ITEMS_TEXT[$menu_id]:-}"

    if [ -n "$current_text" ]; then
        TUI_MENU_ITEMS_TEXT["$menu_id"]="${current_text}|$text"
        TUI_MENU_ITEMS_VALUE["$menu_id"]="${TUI_MENU_ITEMS_VALUE[$menu_id]:-}|$value"
        TUI_MENU_ITEMS_CHECKED["$menu_id"]="${TUI_MENU_ITEMS_CHECKED[$menu_id]:-}|$checked"
        TUI_MENU_ITEMS_TYPE["$menu_id"]="${TUI_MENU_ITEMS_TYPE[$menu_id]:-}|checkbox"
        TUI_MENU_ITEMS_OPTIONS["$menu_id"]="${TUI_MENU_ITEMS_OPTIONS[$menu_id]:-}|"
        TUI_MENU_ITEMS_CURRENT["$menu_id"]="${TUI_MENU_ITEMS_CURRENT[$menu_id]:-}|"
    else
        TUI_MENU_ITEMS_TEXT["$menu_id"]="$text"
        TUI_MENU_ITEMS_VALUE["$menu_id"]="$value"
        TUI_MENU_ITEMS_CHECKED["$menu_id"]="$checked"
        TUI_MENU_ITEMS_TYPE["$menu_id"]="checkbox"
        TUI_MENU_ITEMS_OPTIONS["$menu_id"]=""
        TUI_MENU_ITEMS_CURRENT["$menu_id"]=""
    fi

    TUI_MENU_COUNT["$menu_id"]=$((idx + 1))
}

# 设置配置式选项（新增）
# 用法：tui_menu_set_options <menu_id> <item_index> <option1> <option2> ...
# 示例：tui_menu_set_options "$menu_id" 2 "Asia/Shanghai" "America/New_York" "Europe/London"
tui_menu_set_options() {
    local menu_id="$1"
    local item_idx="$2"
    local first_opt="$3"  # 保存第一个选项值（在 shift 之前）
    shift 2

    # 将选项用分号连接
    local options=""
    for opt in "$@"; do
        if [ -n "$options" ]; then
            options="$options;$opt"
        else
            options="$opt"
        fi
    done

    # 设置类型为 options
    # 先构建一个完整的数组，然后写入
    local -a type_arr=()
    local type_items="${TUI_MENU_ITEMS_TYPE[$menu_id]:-}"
    if [ -n "$type_items" ]; then
        IFS='|' read -ra type_arr <<< "$type_items"
    fi

    # 确保数组足够长
    while [ ${#type_arr[@]} -le $item_idx ]; do
        type_arr+=("checkbox")
    done

    # 设置指定索引的类型
    type_arr[$item_idx]="options"

    # 重新组合成字符串
    local new_items=""
    local i=0
    for val in "${type_arr[@]}"; do
        if [ $i -eq 0 ]; then
            new_items="$val"
        else
            new_items="$new_items|$val"
        fi
        i=$((i + 1))
    done
    TUI_MENU_ITEMS_TYPE["$menu_id"]="$new_items"

    # 设置选项列表
    # 先构建一个完整的数组，然后写入
    local -a opts_arr=()
    local opts="${TUI_MENU_ITEMS_OPTIONS[$menu_id]:-}"
    if [ -n "$opts" ]; then
        IFS='|' read -ra opts_arr <<< "$opts"
    fi

    # 确保数组足够长
    while [ ${#opts_arr[@]} -le $item_idx ]; do
        opts_arr+=("")
    done

    # 设置指定索引的值
    opts_arr[$item_idx]="$options"

    # 重新组合成字符串
    local new_opts=""
    local i=0
    for val in "${opts_arr[@]}"; do
        if [ $i -eq 0 ]; then
            new_opts="$val"
        else
            new_opts="$new_opts|$val"
        fi
        i=$((i + 1))
    done
    TUI_MENU_ITEMS_OPTIONS["$menu_id"]="$new_opts"
    TUI_MENU_ITEMS_OPTIONS["$menu_id"]="$new_opts"

    # 设置当前值为第一个选项
    # 先构建一个完整的数组，然后写入
    local -a current_arr=()
    local currents="${TUI_MENU_ITEMS_CURRENT[$menu_id]:-}"
    if [ -n "$currents" ]; then
        IFS='|' read -ra current_arr <<< "$currents"
    fi

    # 确保数组足够长
    while [ ${#current_arr[@]} -le $item_idx ]; do
        current_arr+=("")
    done

    # 设置指定索引的值
    current_arr[$item_idx]="$first_opt"

    # 重新组合成字符串
    local new_currents=""
    local i=0
    for val in "${current_arr[@]}"; do
        if [ $i -eq 0 ]; then
            new_currents="$val"
        else
            new_currents="$new_currents|$val"
        fi
        i=$((i + 1))
    done
    TUI_MENU_ITEMS_CURRENT["$menu_id"]="$new_currents"
}

# 获取配置式选项的当前值（新增）
# 用法：tui_menu_get_current <menu_id> <item_index>
tui_menu_get_current() {
    local menu_id="$1"
    local idx="$2"
    local current="${TUI_MENU_ITEMS_CURRENT[$menu_id]:-}"

    echo "$current" | cut -d'|' -f$((idx + 1))
}

# 设置配置式选项的当前值（新增）
# 用法：tui_menu_set_current <menu_id> <item_index> <value>
tui_menu_set_current() {
    local menu_id="$1"
    local idx="$2"
    local value="$3"

    local currents="${TUI_MENU_ITEMS_CURRENT[$menu_id]:-}"
    local new_currents=""
    local i=0
    local first=true

    IFS='|' read -ra PARTS <<< "$currents"
    for part in "${PARTS[@]}"; do
        if [ $i -eq $idx ]; then
            part="$value"
        fi
        if [ "$first" = true ]; then
            new_currents="$part"
            first=false
        else
            new_currents="$new_currents|$part"
        fi
        i=$((i + 1))
    done

    TUI_MENU_ITEMS_CURRENT["$menu_id"]="$new_currents"
}

# 获取菜单项的文本
tui_menu_get_text() {
    local menu_id="$1"
    local idx="$2"
    local text="${TUI_MENU_ITEMS_TEXT[$menu_id]:-}"

    echo "$text" | cut -d'|' -f$((idx + 1))
}

# 获取菜单项的值
tui_menu_get_value() {
    local menu_id="$1"
    local idx="$2"
    local value="${TUI_MENU_ITEMS_VALUE[$menu_id]:-}"

    echo "$value" | cut -d'|' -f$((idx + 1))
}

# 获取菜单项的勾选状态
tui_menu_get_checked() {
    local menu_id="$1"
    local idx="$2"
    local checked="${TUI_MENU_ITEMS_CHECKED[$menu_id]:-}"

    echo "$checked" | cut -d'|' -f$((idx + 1))
}

# 设置菜单项的勾选状态
tui_menu_set_checked() {
    local menu_id="$1"
    local idx="$2"
    local checked="$3"

    local items="${TUI_MENU_ITEMS_CHECKED[$menu_id]:-}"
    local new_items=""
    local i=0

    IFS='|' read -ra PARTS <<< "$items"
    for part in "${PARTS[@]}"; do
        if [ $i -eq $idx ]; then
            part="$checked"
        fi
        if [ -n "$new_items" ]; then
            new_items="$new_items|$part"
        else
            new_items="$part"
        fi
        i=$((i + 1))
    done

    TUI_MENU_ITEMS_CHECKED["$menu_id"]="$new_items"
}

# 切换配置式选项的当前值（内部函数）
# 用法：_tui_switch_option <menu_id> <direction>
# direction: 1 = 下一个，-1 = 上一个
_tui_switch_option() {
    local menu_id="$1"
    local direction="$2"
    local cursor="${TUI_MENU_CURSOR[$menu_id]:-0}"

    # 检查当前项是否为配置式选项
    local item_type
    item_type=$(echo "${TUI_MENU_ITEMS_TYPE[$menu_id]:-}" | cut -d'|' -f$((cursor + 1)))
    if [ "$item_type" != "options" ]; then
        return 0  # 不是配置式选项，无操作
    fi

    # 获取当前选项列表和当前值
    local options
    options=$(echo "${TUI_MENU_ITEMS_OPTIONS[$menu_id]:-}" | cut -d'|' -f$((cursor + 1)))
    local current
    current=$(tui_menu_get_current "$menu_id" "$cursor")

    if [ -z "$options" ]; then
        return 0  # 无可用选项
    fi

    # 将选项分割为数组
    IFS=';' read -ra OPT_ARRAY <<< "$options"
    local opt_count=${#OPT_ARRAY[@]}
    if [ "$opt_count" -eq 0 ]; then
        return 0
    fi

    # 找到当前值的索引
    local current_idx=0
    for i in "${!OPT_ARRAY[@]}"; do
        if [ "${OPT_ARRAY[$i]}" = "$current" ]; then
            current_idx=$i
            break
        fi
    done

    # 计算新索引（循环）
    local new_idx=$(( (current_idx + direction + opt_count) % opt_count ))
    local new_value="${OPT_ARRAY[$new_idx]}"

    # 设置新值
    tui_menu_set_current "$menu_id" "$cursor" "$new_value"
}

# 绘制单行菜单项（输出到 stderr）。is_cursor_line：1=光标行高亮
_tui_menu_draw_item_line() {
    local menu_id="$1"
    local i="$2"
    local is_cursor_line="${3:-0}"
    local text
    text="$(tui_menu_get_text "$menu_id" "$i")"
    local checked
    checked=$(tui_menu_get_checked "$menu_id" "$i")
    local item_type
    item_type=$(echo "${TUI_MENU_ITEMS_TYPE[$menu_id]:-}" | cut -d'|' -f$((i + 1)))
    local mode="${TUI_MENU_MODE[$menu_id]:-multi}"
    local status="[ ]"
    local suffix=""

    if [ "$item_type" = "options" ]; then
        local current
        current=$(tui_menu_get_current "$menu_id" "$i")
        status="[$text]"
        suffix=" $current <← →>"
    elif [ "$mode" = "radio" ]; then
        if [ "$checked" = "true" ]; then
            status="(●)"
        else
            status="( )"
        fi
    else
        if [ "$checked" = "true" ]; then
            if [ "$TUI_USE_COLOR" = true ]; then
                status="[✓]"
            else
                status="[x]"
            fi
        fi
    fi

    if [ "$is_cursor_line" = "1" ]; then
        if [ "$TUI_USE_COLOR" = true ]; then
            if [ "$TUI_USE_TPUT" = "true" ]; then
                if [ "$item_type" = "options" ]; then
                    printf '%s> %s%s%s\n' "$TUI_TPUT_REVERSE" "$status" "$suffix" "$TUI_TPUT_RESET" >&2
                else
                    printf '%s> %s %s%s\n' "$TUI_TPUT_REVERSE" "$status" "$text" "$TUI_TPUT_RESET" >&2
                fi
            else
                if [ "$item_type" = "options" ]; then
                    printf '%b> %s%s%b\n' "$TUI_REVERSE" "$status" "$suffix" "$TUI_RESET" >&2
                else
                    printf '%b> %s %s%b\n' "$TUI_REVERSE" "$status" "$text" "$TUI_RESET" >&2
                fi
            fi
        else
            if [ "$item_type" = "options" ]; then
                printf '> %s%s\n' "$status" "$suffix" >&2
            else
                printf '> %s %s\n' "$status" "$text" >&2
            fi
        fi
    else
        if [ "$item_type" = "options" ]; then
            printf '  %s%s\n' "$status" "$suffix" >&2
        else
            printf '  %s %s\n' "$status" "$text" >&2
        fi
    fi
}

# 仅重绘光标移动时的两行（不 tui_clear），项数多时明显减轻卡顿
tui_menu_render_delta() {
    local menu_id="$1"
    local old_i="$2"
    local new_i="$3"
    local row_old=$((3 + old_i))
    local row_new=$((3 + new_i))

    printf '\033[%s;1H\033[2K' "$row_old" >&2
    _tui_menu_draw_item_line "$menu_id" "$old_i" 0
    printf '\033[%s;1H\033[2K' "$row_new" >&2
    _tui_menu_draw_item_line "$menu_id" "$new_i" 1
}

# 渲染菜单
tui_menu_render() {
    local menu_id="$1"
    local title="${TUI_MENU_TITLE[$menu_id]:-}"
    local count="${TUI_MENU_COUNT[$menu_id]:-0}"
    local cursor="${TUI_MENU_CURSOR[$menu_id]:-0}"

    # 清屏并移动光标到顶部
    tui_clear
    tui_move_cursor 1 1

    # 打印标题
    if [ "$TUI_USE_COLOR" = true ]; then
        if [ "$TUI_USE_TPUT" = "true" ]; then
            printf '%s=== %s ===%s\n\n' "$TUI_TPUT_BOLD" "$title" "$TUI_TPUT_RESET"
        else
            printf '%b%b=== %s ===%b\n\n' "$TUI_BOLD" "$TUI_YELLOW" "$title" "$TUI_RESET"
        fi
    else
        printf '=== %s ===\n\n' "$title"
    fi

    # 打印菜单项
    local i=0
    local mode="${TUI_MENU_MODE[$menu_id]:-multi}"
    while [ "$i" -lt "$count" ]; do
        if [ "$i" -eq "$cursor" ]; then
            _tui_menu_draw_item_line "$menu_id" "$i" 1
        else
            _tui_menu_draw_item_line "$menu_id" "$i" 0
        fi
        i=$((i + 1))
    done

    # 打印操作提示
    printf '\n'
    local hint=""
    if [ "$mode" = "radio" ]; then
        hint="↑/k 上移  ↓/j 下移  Enter 确认  ESC/Ctrl-C 退出"
    else
        hint="↑/k 上移  ↓/j 下移  空格勾选  ←→/hl 切换选项  Enter 确认  ESC/Ctrl-C 退出"
    fi
    if [ "$TUI_USE_COLOR" = true ]; then
        if [ "$TUI_USE_TPUT" = "true" ]; then
            printf '%s%s%s\n' "$TUI_TPUT_WHITE" "$hint" "$TUI_TPUT_RESET"
        else
            printf '%b%s%b\n' "$TUI_WHITE" "$hint" "$TUI_RESET"
        fi
    else
        printf '%s\n' "$hint"
    fi
}

# 运行菜单事件循环（直接输出到终端，结果存入 TUI_LAST_RESULT）
# 用法：tui_menu_run "$menu_id"
#       result="$TUI_LAST_RESULT"
tui_menu_run() {
    local menu_id="$1"
    local count="${TUI_MENU_COUNT[$menu_id]:-0}"

    if [ "$count" -eq 0 ]; then
        TUI_LAST_RESULT=""
        return 1
    fi

    # 保存调用方的 trap，以便函数返回时恢复
    local _tui_saved_traps
    _tui_saved_traps=$(trap -p EXIT INT TERM 2>/dev/null) || _tui_saved_traps=""

    # 保存当前终端设置并设置为原始模式
    local old_tty
    old_tty=$(stty -g </dev/tty 2>/dev/null) || old_tty=""
    stty raw -echo opost </dev/tty >/dev/null 2>&1 || stty raw -echo opost 2>/dev/null || true

    # 隐藏光标
    tui_hide_cursor >&2

    # 清理函数（恢复终端设置 + 恢复调用方 trap）
    TUI_MENU_CLEANUP_DONE=false
    _tui_menu_cleanup() {
        if [ "${TUI_MENU_CLEANUP_DONE:-false}" = "false" ]; then
            TUI_MENU_CLEANUP_DONE=true
            if [ -n "$old_tty" ]; then
                stty "$old_tty" 2>/dev/null || true
            fi
            tui_show_cursor >&2
            # 恢复调用方的 trap
            if [ -n "${_tui_saved_traps:-}" ]; then
                eval "$_tui_saved_traps"
            else
                trap - EXIT INT TERM
            fi
        fi
    }
    trap _tui_menu_cleanup EXIT INT TERM

    local _tui_skip_full_render=0

    # 主事件循环
    while true; do
        # 渲染菜单（增量重绘时会跳过本轮全量 tui_clear）
        if [ "$_tui_skip_full_render" = 0 ]; then
            tui_menu_render "$menu_id" >&2
        fi
        _tui_skip_full_render=0

        # 读取单个字符 - 从 /dev/tty 读取，使用 IFS= read -rn1
        # IFS= 防止空格被 trim，-r 防止反斜杠转义，-n1 读取单字符
        local key=""
        IFS= read -rn1 key </dev/tty
        local read_status=$?

        # 调试：记录读取状态
        if [ -n "${TUI_DEBUG:-}" ]; then
            echo "[DEBUG] read status=$read_status, key=[$key]" >&2
        fi

        # read 返回空可能是 Enter（\r）或读取失败
        if [ -z "$key" ]; then
            if [ $read_status -eq 0 ]; then
                # read 成功但返回空，这通常是 Enter 键（\r 被 read 消耗但不保存）
                key=$'\r'
            else
                # read 失败，使用 Ctrl+C 退出
                key=$'\x03'
            fi
        fi

        # 调试：记录按键（仅在 TUI_DEBUG 环境变量设置时）
        if [ -n "${TUI_DEBUG:-}" ]; then
            echo "[DEBUG] key=[$key] hex=$(printf '%s' "$key" | od -An -tx1)" >&2
        fi

        # 处理输入
        case "$key" in
            $'\x1b')  # ESC 前缀：可能是方向键序列，也可能是单独 ESC
                local seq1="" seq2=""
                IFS= read -rn1 -t 0.1 seq1 </dev/tty 2>/dev/null
                if [ -z "$seq1" ]; then
                    tui_clear >&2
                    _tui_menu_cleanup
                    TUI_LAST_RESULT=""
                    return 1
                fi
                IFS= read -rn1 -t 0.1 seq2 </dev/tty 2>/dev/null
                case "${seq1}${seq2}" in
                    '[A'|'OA')  # 上键
                        local _old_c="${TUI_MENU_CURSOR[$menu_id]:-0}"
                        local cursor="${TUI_MENU_CURSOR[$menu_id]:-0}"
                        cursor=$((cursor - 1))
                        if [ "$cursor" -lt 0 ]; then
                            cursor=$((count - 1))
                        fi
                        TUI_MENU_CURSOR["$menu_id"]="$cursor"
                        if [ "$count" -ge "${TUI_MENU_FAST_MIN:-8}" ] && [ "$_old_c" != "$cursor" ]; then
                            tui_menu_render_delta "$menu_id" "$_old_c" "$cursor" >&2
                            _tui_skip_full_render=1
                        fi
                        ;;
                    '[B'|'OB')  # 下键
                        local _old_c="${TUI_MENU_CURSOR[$menu_id]:-0}"
                        local cursor="${TUI_MENU_CURSOR[$menu_id]:-0}"
                        cursor=$((cursor + 1))
                        if [ "$cursor" -ge "$count" ]; then
                            cursor=0
                        fi
                        TUI_MENU_CURSOR["$menu_id"]="$cursor"
                        if [ "$count" -ge "${TUI_MENU_FAST_MIN:-8}" ] && [ "$_old_c" != "$cursor" ]; then
                            tui_menu_render_delta "$menu_id" "$_old_c" "$cursor" >&2
                            _tui_skip_full_render=1
                        fi
                        ;;
                    '[C'|'OC')  # 右键 - 切换下一个选项值
                        _tui_switch_option "$menu_id" 1
                        ;;
                    '[D'|'OD')  # 左键 - 切换上一个选项值
                        _tui_switch_option "$menu_id" -1
                        ;;
                esac
                ;;
            'h'|'H')  # vim 左移 - 切换上一个选项值
                _tui_switch_option "$menu_id" -1
                ;;
            'l'|'L')  # vim 右移 - 切换下一个选项值
                _tui_switch_option "$menu_id" 1
                ;;
            'k'|'K')  # vim 上移
                local _old_c="${TUI_MENU_CURSOR[$menu_id]:-0}"
                local cursor="${TUI_MENU_CURSOR[$menu_id]:-0}"
                cursor=$((cursor - 1))
                if [ "$cursor" -lt 0 ]; then
                    cursor=$((count - 1))
                fi
                TUI_MENU_CURSOR["$menu_id"]="$cursor"
                if [ "$count" -ge "${TUI_MENU_FAST_MIN:-8}" ] && [ "$_old_c" != "$cursor" ]; then
                    tui_menu_render_delta "$menu_id" "$_old_c" "$cursor" >&2
                    _tui_skip_full_render=1
                fi
                ;;
            'j'|'J')  # vim 下移
                local _old_c="${TUI_MENU_CURSOR[$menu_id]:-0}"
                local cursor="${TUI_MENU_CURSOR[$menu_id]:-0}"
                cursor=$((cursor + 1))
                if [ "$cursor" -ge "$count" ]; then
                    cursor=0
                fi
                TUI_MENU_CURSOR["$menu_id"]="$cursor"
                if [ "$count" -ge "${TUI_MENU_FAST_MIN:-8}" ] && [ "$_old_c" != "$cursor" ]; then
                    tui_menu_render_delta "$menu_id" "$_old_c" "$cursor" >&2
                    _tui_skip_full_render=1
                fi
                ;;
            $'\x03')  # Ctrl+C 退出
                tui_clear >&2
                _tui_menu_cleanup
                TUI_LAST_RESULT=""
                return 1
                ;;
            ' '|$'\x20')  # 空格切换勾选
                local cursor="${TUI_MENU_CURSOR[$menu_id]:-0}"
                local mode="${TUI_MENU_MODE[$menu_id]:-multi}"

                if [ "$mode" = "radio" ]; then
                    # 单选：先取消所有，再选中当前
                    local ri=0
                    while [ "$ri" -lt "$count" ]; do
                        tui_menu_set_checked "$menu_id" "$ri" "false"
                        ri=$((ri + 1))
                    done
                    tui_menu_set_checked "$menu_id" "$cursor" "true"
                else
                    # 多选：切换当前项
                    local checked
                    checked=$(tui_menu_get_checked "$menu_id" "$cursor")
                    if [ "$checked" = "true" ]; then
                        tui_menu_set_checked "$menu_id" "$cursor" "false"
                    else
                        tui_menu_set_checked "$menu_id" "$cursor" "true"
                    fi
                fi
                ;;
            $'\n' | $'\r' | '')  # Enter 确认
                if [ -n "${TUI_DEBUG:-}" ]; then
                    echo "[DEBUG] Enter pressed" >&2
                fi

                local mode="${TUI_MENU_MODE[$menu_id]:-multi}"
                local i=0
                local result=""

                if [ "$mode" = "radio" ]; then
                    # 单选模式：返回光标位置
                    local cursor="${TUI_MENU_CURSOR[$menu_id]:-0}"
                    result="SELECTED:$cursor"
                else
                    # 多选模式：收集勾选项和配置值
                    IFS='|' read -ra VALUES <<< "${TUI_MENU_ITEMS_VALUE[$menu_id]:-}"
                    IFS='|' read -ra CHECKED <<< "${TUI_MENU_ITEMS_CHECKED[$menu_id]:-}"
                    IFS='|' read -ra TYPES <<< "${TUI_MENU_ITEMS_TYPE[$menu_id]:-}"
                    IFS='|' read -ra CURRENTS <<< "${TUI_MENU_ITEMS_CURRENT[$menu_id]:-}"

                    for val in "${VALUES[@]}"; do
                        local item_type="${TYPES[$i]:-checkbox}"
                        if [ "$item_type" = "options" ]; then
                            local current="${CURRENTS[$i]:-}"
                            if [ -n "$result" ]; then
                                result="$result"$'\n'"VALUE:$i:$current"
                            else
                                result="VALUE:$i:$current"
                            fi
                        elif [ "${CHECKED[$i]:-false}" = "true" ]; then
                            if [ -n "$result" ]; then
                                result="$result"$'\n'"CHECKED:$i"
                            else
                                result="CHECKED:$i"
                            fi
                        fi
                        i=$((i + 1))
                    done

                    if [ -z "$result" ]; then
                        local cursor="${TUI_MENU_CURSOR[$menu_id]:-0}"
                        local cursor_type
                        cursor_type=$(echo "$TYPES" | cut -d'|' -f$((cursor + 1)))
                        if [ "$cursor_type" = "options" ]; then
                            local current
                            current=$(tui_menu_get_current "$menu_id" "$cursor")
                            result="VALUE:$cursor:$current"
                        else
                            result="UNCHECKED:$cursor"
                        fi
                    fi
                fi

                # 调试：输出结果
                if [ -n "${TUI_DEBUG:-}" ]; then
                    echo "[DEBUG] Parsed result:" >&2
                    echo "$result" >&2
                fi

                # 清屏并恢复
                tui_clear >&2
                _tui_menu_cleanup

                # 设置结果到全局变量
                TUI_LAST_RESULT="$result"
                return 0
                ;;
        esac
    done
}

# 捕获退出信号，恢复光标
_tui_trap_exit() {
    tui_cleanup
}
trap _tui_trap_exit EXIT INT TERM

# ============================================================================
# 解析辅助函数（新增）
# ============================================================================

# 解析 tui_menu_run 返回值
# 用法：tui_parse_result <result> <type>
# type: "SELECTED" 返回单选模式选中的索引
#       "CHECKED" 返回所有勾选的索引
#       "VALUE" 返回所有配置式的 index:value
#       "ALL" 返回所有结果（每行一个）
tui_parse_result() {
    local result="$1"
    local type="$2"
    local output=""

    while IFS= read -r line; do
        if [ -z "$line" ]; then
            continue
        fi
        case "$type" in
            SELECTED)
                if [[ "$line" == SELECTED:* ]]; then
                    output="${line#SELECTED:}"
                fi
                ;;
            CHECKED)
                if [[ "$line" == CHECKED:* ]]; then
                    local idx="${line#CHECKED:}"
                    if [ -n "$output" ]; then
                        output="$output $idx"
                    else
                        output="$idx"
                    fi
                fi
                ;;
            VALUE)
                if [[ "$line" == VALUE:* ]]; then
                    local rest="${line#VALUE:}"
                    local idx="${rest%%:*}"
                    local value="${rest#*:}"
                    if [ -n "$output" ]; then
                        output="$output $idx:$value"
                    else
                        output="$idx:$value"
                    fi
                fi
                ;;
            ALL|"")
                if [ -n "$output" ]; then
                    output="$output"$'\n'"$line"
                else
                    output="$line"
                fi
                ;;
        esac
    done <<< "$result"

    echo "$output"
}
