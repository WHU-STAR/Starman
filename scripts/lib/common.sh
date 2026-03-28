#!/bin/bash
#
# Starman 公共库 - 提供日志、颜色、错误处理等通用功能
#
# 用法：
#   source scripts/lib/common.sh
#
# 主要函数：
#   log_info    - 信息日志
#   log_error   - 错误日志
#   log_warn    - 警告日志
#   log_success - 成功日志
#   die         - 打印错误并退出
#   require_non_root - 检测必须以非 root 用户运行
#   require_sudo     - 检测当前用户是否有 sudo 权限
#   detect_os        - 检测操作系统类型
#   ui_banner_starman  - 打印横幅标题
#   ui_step    - 打印步骤标题
#   ui_ok      - 打印成功标记
#   ui_err     - 打印错误标记
#   menu_numbered      - 显示编号菜单
#   try_fzf_or_menu    - 尝试使用 fzf 或回退到编号菜单
#

set -u

# ============================================================================
# 颜色定义
# ============================================================================

# 检测是否支持颜色
if [ -t 1 ]; then
    # 终端支持颜色
    COMMON_RED=$'\033[0;31m'
    COMMON_GREEN=$'\033[0;32m'
    COMMON_YELLOW=$'\033[1;33m'
    COMMON_BLUE=$'\033[0;34m'
    COMMON_WHITE=$'\033[1;37m'
    COMMON_NC=$'\033[0m'
else
    # 非交互式环境，禁用颜色
    COMMON_RED=""
    COMMON_GREEN=""
    COMMON_YELLOW=""
    COMMON_BLUE=""
    COMMON_WHITE=""
    COMMON_NC=""
fi

# 允许通过环境变量覆盖
if [ -n "${NO_COLOR:-}" ]; then
    COMMON_RED=""
    COMMON_GREEN=""
    COMMON_YELLOW=""
    COMMON_BLUE=""
    COMMON_WHITE=""
    COMMON_NC=""
fi

# ============================================================================
# 日志函数
# ============================================================================

log_info() {
    echo -e "${COMMON_BLUE}[INFO]${COMMON_NC} $*"
}

log_error() {
    echo -e "${COMMON_RED}[ERROR]${COMMON_NC} $*" >&2
}

log_warn() {
    echo -e "${COMMON_YELLOW}[WARN]${COMMON_NC} $*" >&2
}

log_success() {
    echo -e "${COMMON_GREEN}[SUCCESS]${COMMON_NC} $*"
}

# 打印错误并退出
die() {
    log_error "$*"
    exit "${2:-1}"
}

# ============================================================================
# 环境检测函数
# ============================================================================

# 检测是否以 root 用户运行，如果是则退出
require_non_root() {
    if [ "$(id -u)" -eq 0 ]; then
        die "不能使用 root 用户运行安装脚本。请使用非 root 用户或 sudo 用户执行。" 1
    fi
}

# 检测当前用户是否有 sudo 权限
require_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    if ! command -v sudo &>/dev/null; then
        die "未找到 sudo 命令。请先安装 sudo 或以 root 用户执行。" 1
    fi

    # 免密 sudo 可用
    if sudo -n true 2>/dev/null; then
        return 0
    fi

    # 用户在 sudo/wheel 组中（实际 sudo 时再提示密码）
    if id -nG 2>/dev/null | grep -qwE 'sudo|wheel|admin'; then
        return 0
    fi

    # 有 TTY 时尝试交互验证
    if [ -t 0 ]; then
        sudo -v || die "sudo 验证失败。" 1
        return 0
    fi

    die "需要 sudo 权限但无法验证。请确保当前用户在 sudo/wheel 组中。" 1
}

# 检测操作系统类型
# 返回值：
#   输出 "debian" "ubuntu" "rhel" "centos" "fedora" "arch" 等
detect_os() {
    local os_id=""
    local os_id_like=""

    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        os_id="${ID:-}"
        os_id_like="${ID_LIKE:-}"
    else
        # 回退方案
        if [ -f /etc/redhat-release ]; then
            os_id="rhel"
        elif [ -f /etc/debian_version ]; then
            os_id="debian"
        elif [ -f /etc/arch-release ]; then
            os_id="arch"
        else
            os_id="unknown"
        fi
    fi

    # 处理 ID_LIKE 的情况（如 ubuntu 可能出现在 ID_LIKE 中）
    case "$os_id" in
        ubuntu)
            echo "ubuntu"
            return 0
            ;;
        debian)
            echo "debian"
            return 0
            ;;
        rhel|centos|rocky|almalinux)
            echo "rhel"
            return 0
            ;;
        fedora)
            echo "fedora"
            return 0
            ;;
        arch|manjaro)
            echo "arch"
            return 0
            ;;
        *)
            # 检查 ID_LIKE
            if [[ "$os_id_like" == *"debian"* ]]; then
                echo "debian"
            elif [[ "$os_id_like" == *"rhel"* ]] || [[ "$os_id_like" == *"centos"* ]]; then
                echo "rhel"
            elif [[ "$os_id_like" == *"arch"* ]]; then
                echo "arch"
            else
                echo "unknown"
            fi
            return 0
            ;;
    esac
}

# 检测是否为 Debian/Ubuntu 系列
is_debian_family() {
    local os
    os="$(detect_os)"
    [[ "$os" == "debian" || "$os" == "ubuntu" ]]
}

# 检测是否为 RHEL 系列
is_rhel_family() {
    local os
    os="$(detect_os)"
    [[ "$os" == "rhel" || "$os" == "fedora" || "$os" == "centos" ]]
}

# ============================================================================
# 工具函数
# ============================================================================

# 检查命令是否存在
command_exists() {
    command -v "$1" &>/dev/null
}

# 打印调试信息（当 COMMON_DEBUG 设置时）
debug() {
    if [ -n "${COMMON_DEBUG:-}" ]; then
        echo -e "${COMMON_YELLOW}[DEBUG]${COMMON_NC} $*" >&2
    fi
}

# ============================================================================
# UI 辅助函数
# ============================================================================

# 打印 Starman 随机 ASCII Banner
# 用法：ui_banner_starman
# 从 scripts/lib/banners.txt 随机选择一个 banner 打印
ui_banner_starman() {
    local green="${COMMON_GREEN:-\033[0;32m}"
    local yellow="${COMMON_YELLOW:-\033[1;33m}"
    local blue="${COMMON_BLUE:-\033[0;34m}"
    local white="${COMMON_WHITE:-\033[1;37m}"
    local nc="${COMMON_NC:-\033[0m}"

    # 获取脚本所在目录
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
    local banner_file="$script_dir/banners.txt"

    # 如果 banners.txt 不存在，回退到简单 banner
    if [ ! -f "$banner_file" ]; then
        echo ""
        echo -e "${white}=== Starman Installer ===${nc}"
        echo -e "${yellow}STAR Lab Server Management System${nc}"
        echo -e "${blue}STAR Laboratory${nc} | ${green}GPL License${nc}"
        echo ""
        return
    fi

    # 读取所有 banner（用 >>>>>>>>>>> 分隔）
    local banners=()
    local current_banner=""

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" == ">>>>>>>>>>>" ]]; then
            if [ -n "$current_banner" ]; then
                banners+=("$current_banner")
                current_banner=""
            fi
        else
            current_banner+="$line"$'\n'
        fi
    done < "$banner_file"

    # 添加最后一个 banner
    if [ -n "$current_banner" ]; then
        banners+=("$current_banner")
    fi

    # 随机选择一个 banner
    local num_banners=${#banners[@]}
    if [ "$num_banners" -gt 0 ]; then
        local random_idx=$((RANDOM % num_banners))
        echo ""
        echo -e "${white}${banners[$random_idx]}${nc}"
    fi

    echo -e "   ${yellow}STAR Lab Server Management System${nc}"
    echo -e "   ${blue}STAR Laboratory${nc} | ${green}GPL License${nc}"
    echo ""
    echo -e "${white}────────────────────────────────────────────────────${nc}"
    echo ""
}

# 打印横幅标题
ui_banner() {
    local title="$1"
    local width="${2:-60}"
    local i

    echo ""
    for ((i = 0; i < width; i++)); do
        echo -n "="
    done
    echo ""

    # 居中显示标题
    local padding=$(( (width - ${#title}) / 2 ))
    printf "%${padding}s%s\n" "" "$title"

    for ((i = 0; i < width; i++)); do
        echo -n "="
    done
    echo ""
}

# 打印步骤标题
ui_step() {
    local step="$1"
    local description="$2"
    echo ""
    echo -e "${COMMON_BLUE}==> ${COMMON_WHITE}$step: $description${COMMON_NC}"
}

# 打印成功标记
ui_ok() {
    local message="$1"
    echo -e "${COMMON_GREEN}    ✓ $message${COMMON_NC}"
}

# 打印错误标记
ui_err() {
    local message="$1"
    echo -e "${COMMON_RED}    ✗ $message${COMMON_NC}" >&2
}

# 显示编号菜单
# 用法：menu_numbered "标题" "选项 1" "选项 2" "选项 3"
# 返回：用户选择的选项编号（1, 2, 3...）或 0（取消）
menu_numbered() {
    local title="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local choice

    echo "" >&2
    echo -e "${COMMON_WHITE}$title${COMMON_NC}" >&2
    echo "" >&2

    for ((i = 0; i < num_options; i++)); do
        printf "  ${COMMON_YELLOW}%d${COMMON_NC}) %s\n" $((i + 1)) "${options[$i]}" >&2
    done

    echo "" >&2
    printf "请选择 (1-%d, 0 取消): " "$num_options" >&2
    read -r choice

    # 验证输入
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le "$num_options" ]; then
        echo "$choice"
    else
        echo "0"
    fi
}

# 尝试使用 fzf 或回退到编号菜单
# 用法：try_fzf_or_menu "标题" "选项 1" "选项 2" ...
# 返回：用户选择的选项（字符串）
try_fzf_or_menu() {
    local title="$1"
    shift
    local options=("$@")

    # 检查 fzf 是否可用
    if command -v fzf &>/dev/null; then
        # 使用 fzf
        local choice
        choice=$(printf '%s\n' "${options[@]}" | fzf --prompt="$title: " --height=40% --reverse)
        if [ -n "$choice" ]; then
            echo "$choice"
        else
            echo ""
        fi
    else
        # 回退到编号菜单
        local idx
        idx=$(menu_numbered "$title" "${options[@]}")
        if [ "$idx" -gt 0 ]; then
            echo "${options[$((idx - 1))]}"
        else
            echo ""
        fi
    fi
}
