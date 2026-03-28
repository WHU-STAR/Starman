#!/bin/bash
#
# Starman Main Installer
#
# Usage: ./install.sh [--from-root] (usually downloaded and executed by bootstrap.sh)
#
# This script:
# 1. Detects system environment (user identity, sudo, network)
# 2. Handles root user → non-root user switch
# 3. Downloads only the required install scripts from Gitee/GitHub
# 4. Stages to /opt/starman-install
# 5. Runs the project's install.sh for system setup
# 6. Staging dir can be cleaned up after installation is complete
#
# Copyright (c) STAR Laboratory. All rights reserved.
# Licensed under the GPL License.
#

set -e

# ============================================================================
# Global Flags
# ============================================================================

SUDO_NOPASSWD=false

# ============================================================================
# Configuration
# ============================================================================

GITHUB_BASE="https://github.com/STAR-Organization/starman"
GITEE_BASE="https://gitee.com/ajgamma/starman"

# Raw file URL bases
GITEE_RAW="$GITEE_BASE/raw/master"
GITHUB_RAW="https://raw.githubusercontent.com/STAR-Organization/starman/master"

# Staging directory for install scripts (cleaned up after completion)
# 使用用户 home 目录避免 sudo 权限问题（su 切换用户后无 TTY 输入密码）
STAGING_DIR="${HOME}/.starman-install"

# Files needed for installation (relative to repo root)
INSTALL_FILES=(
    "install.sh"
    "scripts/lib/tui.sh"
    "scripts/lib/common.sh"
    "scripts/lib/pkgmgr.sh"
    "scripts/lib/banners.txt"
    "scripts/steps/packages.sh"
    "templates/vim.min.snippet"
    "templates/tmux.min.snippet"
    "templates/bash.min.snippet"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

# 获取脚本所在目录（用于 sourcing lib）
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    local dir
    dir="$(dirname "$source")"
    # 如果是相对路径，转换为绝对路径
    if [[ "$dir" != /* ]]; then
        dir="$(cd "$dir" && pwd)"
    fi
    echo "$dir"
}

# Source TUI library from Gitee if not available locally
SCRIPT_DIR="$(get_script_dir)"
if [ -f "$SCRIPT_DIR/../scripts/lib/tui.sh" ]; then
    source "$SCRIPT_DIR/../scripts/lib/tui.sh"
else
    # Download from Gitee
    TUI_TMP="/tmp/starman_tui_$$.sh"
    if curl -fsSL "https://gitee.com/ajgamma/starman/raw/master/scripts/lib/tui.sh" -o "$TUI_TMP"; then
        source "$TUI_TMP"
        rm -f "$TUI_TMP"
    else
        log_warn "无法下载 tui.sh，TUI 功能可能不可用"
        rm -f "$TUI_TMP" 2>/dev/null
    fi
fi

# Source common library from Gitee if not available locally
if [ -f "$SCRIPT_DIR/../scripts/lib/common.sh" ]; then
    source "$SCRIPT_DIR/../scripts/lib/common.sh"
else
    # Download from Gitee
    COMMON_TMP="/tmp/starman_common_$$.sh"
    if curl -fsSL "https://gitee.com/ajgamma/starman/raw/master/scripts/lib/common.sh" -o "$COMMON_TMP"; then
        source "$COMMON_TMP"
        rm -f "$COMMON_TMP"
    else
        log_warn "无法下载 common.sh，部分功能可能不可用"
        rm -f "$COMMON_TMP" 2>/dev/null
    fi
fi

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# ============================================================================
# Environment Detection
# ============================================================================

detect_user() {
    if [ "$(id -u)" = "0" ]; then
        IS_ROOT=true
        log_warn "当前以 root 用户运行"
    else
        IS_ROOT=false
        log_info "当前用户：$(whoami)"
    fi
}

detect_sudo() {
    if sudo -n true 2>/dev/null; then
        HAS_SUDO=true
        SUDO_NOPASSWD=true
        log_info "检测到 sudo 权限（免密）"
    elif id -nG 2>/dev/null | grep -qwE 'sudo|wheel|admin'; then
        HAS_SUDO=true
        SUDO_NOPASSWD=false
        log_info "检测到 sudo 权限（需要密码）"
    else
        HAS_SUDO=false
        SUDO_NOPASSWD=false
        log_warn "未检测到 sudo 权限"
    fi
}

detect_network() {
    log_info "检测网络连通性..."

    # TODO: GitHub 源待配置，暂时跳过检测
    GITHUB_AVAILABLE=false

    # Test Gitee
    if curl -fsSL --connect-timeout 5 "https://gitee.com" &>/dev/null; then
        GITEE_AVAILABLE=true
        log_info "Gitee 可访问"
    else
        GITEE_AVAILABLE=false
        log_warn "Gitee 不可访问"
    fi

    if [ "$GITHUB_AVAILABLE" = false ] && [ "$GITEE_AVAILABLE" = false ]; then
        log_error "GitHub 和 Gitee 都不可访问，请检查网络连接"
        return 1
    fi
}

# ============================================================================
# User Guidance
# ============================================================================

check_interactive() {
    if [ "$IS_ROOT" = true ] && [ ! -t 0 ]; then
        log_error "检测到以 root 用户通过管道模式执行安装脚本"
        echo ""
        echo "管道模式下无法进行交互式用户切换，请手动操作："
        echo ""
        echo "  1. 创建非 root 用户："
        echo "     useradd -m -s /bin/bash <用户名>"
        echo "     passwd <用户名>"
        echo "     usermod -aG sudo <用户名>   # Debian/Ubuntu"
        echo "     usermod -aG wheel <用户名>  # RHEL/Fedora"
        echo ""
        echo "  2. 以新用户身份重新执行安装："
        echo "     su - <用户名>"
        echo "     curl -fsSL <安装URL> | bash"
        echo ""
        exit 1
    fi
}

# 保存原始脚本路径（用于切换用户后重新执行）
ORIGINAL_SCRIPT_PATH=""

detect_script_path() {
    ORIGINAL_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
    log_info "脚本路径：$ORIGINAL_SCRIPT_PATH"
}

_handoff_to_user() {
    local target_user="$1"
    local script_name
    script_name=$(basename "$ORIGINAL_SCRIPT_PATH")
    local target_dir="/home/$target_user"
    local target_script="$target_dir/$script_name"

    if [ -f "$ORIGINAL_SCRIPT_PATH" ]; then
        cp "$ORIGINAL_SCRIPT_PATH" "$target_script"
        chown "$target_user:$target_user" "$target_script"
        chmod 755 "$target_script"
    else
        log_error "无法找到安装脚本：$ORIGINAL_SCRIPT_PATH"
        exit 1
    fi

    tui_clear
    log_success "用户 $target_user 已就绪，正在切换..."
    log_info "切换后请执行以下命令继续安装："
    echo ""
    printf '  \033[1;32mbash %s\033[0m\n\n' "$target_script"

    # 直接 su 进入用户的交互式 shell，用户在里面手动执行上面的命令
    exec su - "$target_user"
}

guide_root_user() {
    if [ "$IS_ROOT" = false ]; then
        return 0
    fi

    # 非交互模式下无法进行 TUI 操作
    check_interactive

    # 强制引导：root 用户必须切换到非 root 用户
    while true; do
        tui_clear

        # 使用 tput 或 ANSI 打印标题
        if [ "$TUI_USE_TPUT" = "true" ]; then
            printf '%s%s%s\n\n' "$TUI_TPUT_BOLD" "=== 安全警告 ===" "$TUI_TPUT_RESET"
        else
            printf '\033[1m=== 安全警告 ===\033[0m\n\n'
        fi

        printf '检测到当前以 \033[1;31mroot 用户\033[0m 身份运行安装脚本。\n\n'
        printf '这不符合安全最佳实践，可能导致：\n'
        printf '  - 权限过大，误操作风险高\n'
        printf '  - 不符合最小权限原则\n'
        printf '  - 后续运维需要在 root 和非 root 用户之间切换\n\n'
        printf '请选择以下操作：\n\n'

        # 创建 TUI 单选菜单
        tui_menu_create "选择操作"
        local menu_id="$TUI_LAST_MENU_ID"
        tui_menu_set_radio "$menu_id"
        tui_menu_add "$menu_id" "新建 sudo 用户并迁移项目" "create_user" false
        tui_menu_add "$menu_id" "切换到已有用户" "switch_user" false
        tui_menu_add "$menu_id" "取消安装" "cancel" false

        tui_menu_run "$menu_id"
        local result="$TUI_LAST_RESULT"

        # radio 模式返回 SELECTED:<index>
        local selected_idx=""
        case "$result" in
            SELECTED:*)
                selected_idx="${result#SELECTED:}"
                ;;
            "")
                continue
                ;;
        esac

        case "$selected_idx" in
            0)
                do_create_user_flow
                if [ $? -eq 0 ]; then
                    return 0
                fi
                ;;
            1)
                do_switch_user_flow
                if [ $? -eq 0 ]; then
                    return 0
                fi
                ;;
            2)
                log_warn "用户取消安装"
                exit 0
                ;;
        esac
    done
}

do_create_user_flow() {
    tui_clear

    if [ "$TUI_USE_TPUT" = "true" ]; then
        printf '%s%s%s\n\n' "$TUI_TPUT_BOLD" "新建 sudo 用户" "$TUI_TPUT_RESET"
    else
        printf '\033[1m新建 sudo 用户\033[0m\n\n'
    fi

    read -rp "请输入新用户名（默认：staruser）: " username
    username="${username:-staruser}"

    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "无效的用户名：$username"
        echo "用户名必须以小写字母或下划线开头，只能包含小写字母、数字、下划线和连字符。"
        read -rp "按 Enter 继续..."
        return 1
    fi

    if id "$username" &>/dev/null; then
        log_error "用户 $username 已存在"
        read -rp "按 Enter 继续..."
        return 1
    fi

    # 密码输入（两次确认）
    local password=""
    while true; do
        local pw1="" pw2=""
        echo ""
        read -rsp "请为用户 $username 设置密码: " pw1
        echo ""
        read -rsp "请再次输入密码确认: " pw2
        echo ""

        if [ -z "$pw1" ]; then
            log_error "密码不能为空"
            continue
        fi

        if [ "$pw1" != "$pw2" ]; then
            log_error "两次输入的密码不一致，请重新输入"
            continue
        fi

        password="$pw1"
        break
    done

    printf "\n正在创建用户：%s...\n" "$username"

    if ! useradd -m -s /bin/bash "$username" 2>/dev/null; then
        log_error "创建用户失败，请检查系统命令"
        unset password
        read -rp "按 Enter 继续..."
        return 1
    fi

    # 设置密码
    echo "$username:$password" | chpasswd 2>/dev/null
    unset password
    log_success "用户密码已设置"

    # 配置 sudo 权限：sudo 组 → wheel 组 → sudoers.d 兜底
    local sudo_ok=false
    if command -v usermod &>/dev/null; then
        if getent group sudo &>/dev/null; then
            usermod -aG sudo "$username" 2>/dev/null && sudo_ok=true
        fi
        if [ "$sudo_ok" = false ] && getent group wheel &>/dev/null; then
            usermod -aG wheel "$username" 2>/dev/null && sudo_ok=true
        fi
    fi
    if [ "$sudo_ok" = false ]; then
        mkdir -p /etc/sudoers.d
        echo "$username ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$username"
        chmod 440 "/etc/sudoers.d/$username"
    fi

    log_success "用户 $username 创建成功，已配置 sudo 权限"

    _handoff_to_user "$username"
}

do_switch_user_flow() {
    tui_clear

    local users=()

    if [ -d "/home" ]; then
        for dir in /home/*/; do
            if [ -d "$dir" ]; then
                local user
                user=$(basename "$dir")
                if id "$user" &>/dev/null; then
                    users+=("$user")
                fi
            fi
        done
    fi

    if [ ${#users[@]} -eq 0 ]; then
        log_error "未找到可用的非 root 用户"
        echo ""
        echo "请先创建一个新用户，或选择"新建 sudo 用户"选项。"
        read -rp "按 Enter 继续..."
        return 1
    fi

    tui_clear

    if [ "$TUI_USE_TPUT" = "true" ]; then
        printf '%s%s%s\n\n' "$TUI_TPUT_BOLD" "选择要切换的用户" "$TUI_TPUT_RESET"
    else
        printf '\033[1m选择要切换的用户\033[0m\n\n'
    fi

    tui_menu_create "选择用户"
    local menu_id="$TUI_LAST_MENU_ID"
    tui_menu_set_radio "$menu_id"

    for i in "${!users[@]}"; do
        tui_menu_add "$menu_id" "${users[$i]}" "${users[$i]}" false
    done

    tui_menu_run "$menu_id"
    local result="$TUI_LAST_RESULT"

    if [ -z "$result" ]; then
        log_warn "用户取消选择"
        return 1
    fi

    local target_user=""
    case "$result" in
        SELECTED:*)
            local idx="${result#SELECTED:}"
            target_user="${users[$idx]}"
            ;;
        *)
            log_warn "用户取消选择"
            return 1
            ;;
    esac

    _handoff_to_user "$target_user"
}

check_sudo() {
    if [ "$IS_ROOT" = false ] && [ "$HAS_SUDO" = false ]; then
        log_error "需要 sudo 权限才能安装到系统目录"
        echo ""
        echo "请使用 sudo 执行此脚本："
        echo "  sudo $0"
        exit 1
    fi
}

# ============================================================================
# Download & Install Functions
# ============================================================================

_sudo_cmd() {
    if [ "$IS_ROOT" = true ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# 从 Gitee 或 GitHub 下载单个文件
# 用法: _download_raw_file <relative_path> <output>
_download_raw_file() {
    local file_path="$1"
    local output="$2"

    if [ "$GITEE_AVAILABLE" = true ]; then
        if curl -fsSL "$GITEE_RAW/$file_path" -o "$output" 2>/dev/null; then
            return 0
        fi
    fi

    if [ "$GITHUB_AVAILABLE" = true ]; then
        if curl -fsSL "$GITHUB_RAW/$file_path" -o "$output" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

download_install_files() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    log_info "正在下载安装脚本（共 ${#INSTALL_FILES[@]} 个文件）..."

    local failed=0
    for file in "${INSTALL_FILES[@]}"; do
        local dir
        dir="$(dirname "$file")"
        mkdir -p "$tmp_dir/$dir"

        if _download_raw_file "$file" "$tmp_dir/$file"; then
            log_info "  ✓ $file"
        else
            log_error "  ✗ $file"
            failed=1
        fi
    done

    if [ "$failed" -eq 1 ]; then
        log_error "部分文件下载失败"
        rm -rf "$tmp_dir"
        return 1
    fi

    # 部署到 staging 目录（用户 home 下，无需 sudo）
    mkdir -p "$STAGING_DIR"
    cp -r "$tmp_dir/"* "$STAGING_DIR/"
    chmod +x "$STAGING_DIR/install.sh"

    rm -rf "$tmp_dir"
    log_success "安装脚本已就绪：$STAGING_DIR"
}

run_setup() {
    local setup_script="$STAGING_DIR/install.sh"

    if [ ! -f "$setup_script" ]; then
        log_error "安装脚本不存在：$setup_script"
        return 1
    fi

    echo ""
    log_info "============================================"
    log_info "  下载完成，启动系统配置"
    log_info "============================================"
    echo ""

    cd "$STAGING_DIR"
    bash "$setup_script"
    local status=$?

    # setup 脚本正常退出后，提示可以清理
    if [ $status -eq 0 ]; then
        echo ""
        log_success "系统配置完成"
        log_info "安装脚本位于 $STAGING_DIR"
        log_info "如需重新运行: cd $STAGING_DIR && bash install.sh"
        log_info "确认不再需要后可清理: sudo rm -rf $STAGING_DIR"
    fi

    return $status
}

show_offline_guide() {
    echo ""
    log_info "============================================"
    log_info "  离线安装指引"
    log_info "============================================"
    echo ""
    echo "如果无法在线下载，可在可联网的机器上手动下载以下文件："
    echo ""
    for file in "${INSTALL_FILES[@]}"; do
        echo "  $GITEE_RAW/$file"
    done
    echo ""
    echo "将文件按目录结构放入目标机器的 ~/.starman-install/ 下，然后执行："
    echo "  cd ~/.starman-install && bash install.sh"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    # 显示 ASCII Banner
    if command -v ui_banner_starman &>/dev/null; then
        ui_banner_starman
    else
        log_info "=== Starman Installer ==="
    fi

    # Detect environment
    detect_user
    detect_sudo
    detect_script_path

    # Check sudo before network detection
    check_sudo

    # root 用户引导切换（会 exit，不会继续后续流程）
    guide_root_user

    # Detect network
    detect_network || {
        show_offline_guide
        exit 1
    }

    # Download install scripts
    download_install_files || {
        show_offline_guide
        exit 1
    }

    # Run setup
    run_setup

    log_info ""
    log_info "=== Installation Complete ==="
}

main "$@"
