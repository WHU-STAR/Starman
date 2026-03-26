#!/bin/bash
#
# Starman Main Installer
#
# Usage: ./install.sh (usually downloaded and executed by bootstrap.sh)
#
# This script:
# 1. Detects system environment (architecture, network, user identity)
# 2. Downloads starman binary from GitHub/Gitee Releases
# 3. Installs to /usr/sbin/starman
# 4. Deploys configuration and completion scripts
#
# Copyright (c) STAR Laboratory. All rights reserved.
# Licensed under the GPL License.
#

set -e

# ============================================================================
# Configuration
# ============================================================================

GITHUB_BASE="https://github.com/STAR-Organization/starman"
GITEE_BASE="https://gitee.com/ajgamma/starman"

# Release binary URLs (will be constructed based on arch)
GITHUB_RELEASE="$GITHUB_BASE/releases/latest/download"
GITEE_RELEASE="$GITEE_BASE/releases/latest/download"

# Installation paths
INSTALL_DIR="/usr/sbin"
CONFIG_DIR="/etc/starman"
STARMAN_BIN="starman"

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

# Source TUI library
SCRIPT_DIR="$(get_script_dir)"
if [ -f "$SCRIPT_DIR/../scripts/lib/tui.sh" ]; then
    source "$SCRIPT_DIR/../scripts/lib/tui.sh"
elif [ -f "/home/adrian/code/misc/starman/scripts/lib/tui.sh" ]; then
    source /home/adrian/code/misc/starman/scripts/lib/tui.sh
fi

# Source common library
if [ -f "$SCRIPT_DIR/../scripts/lib/common.sh" ]; then
    source "$SCRIPT_DIR/../scripts/lib/common.sh"
elif [ -f "/home/adrian/code/misc/starman/scripts/lib/common.sh" ]; then
    source /home/adrian/code/misc/starman/scripts/lib/common.sh
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

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            ARCH="x86_64"
            ;;
        aarch64|arm64)
            ARCH="aarch64"
            ;;
        *)
            log_error "不支持的系统架构：$ARCH"
            return 1
            ;;
    esac
    log_info "检测到系统架构：$ARCH"
}

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
        log_info "检测到 sudo 权限"
    else
        HAS_SUDO=false
        log_warn "未检测到 sudo 权限"
    fi
}

detect_network() {
    log_info "检测网络连通性..."

    # Test GitHub
    if curl -fsSL --connect-timeout 5 "https://github.com" &>/dev/null; then
        GITHUB_AVAILABLE=true
        log_info "GitHub 可访问"
    else
        GITHUB_AVAILABLE=false
        log_warn "GitHub 不可访问"
    fi

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

# 保存原始脚本路径（用于切换用户后重新执行）
ORIGINAL_SCRIPT_PATH=""

detect_script_path() {
    ORIGINAL_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
    log_info "脚本路径：$ORIGINAL_SCRIPT_PATH"
}

guide_root_user() {
    if [ "$IS_ROOT" = false ]; then
        return 0
    fi

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

        # 创建 TUI 菜单
        local menu_id
        tui_menu_create "选择操作"
        tui_menu_add "$menu_id" "新建 sudo 用户并迁移项目" "create_user" true
        tui_menu_add "$menu_id" "切换到已有用户" "switch_user" false
        tui_menu_add "$menu_id" "取消安装" "cancel" false

        # 运行菜单
        local choice
        choice=$(tui_menu_run "$menu_id")
        local result="$TUI_LAST_RESULT"

        case "$result" in
            create_user*)
                do_create_user_flow
                if [ $? -eq 0 ]; then
                    return 0
                fi
                ;;
            switch_user*)
                do_switch_user_flow
                if [ $? -eq 0 ]; then
                    return 0
                fi
                ;;
            cancel*)
                log_warn "用户取消安装"
                exit 0
                ;;
        esac
    done
}

do_create_user_flow() {
    tui_clear

    # 提示输入用户名
    if [ "$TUI_USE_TPUT" = "true" ]; then
        printf '%s%s%s\n\n' "$TUI_TPUT_BOLD" "新建 sudo 用户" "$TUI_TPUT_RESET"
    else
        printf '\033[1m新建 sudo 用户\033[0m\n\n'
    fi

    read -rp "请输入新用户名（默认：staruser）: " username
    username="${username:-staruser}"

    # 验证用户名
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "无效的用户名：$username"
        echo "用户名必须以小写字母或下划线开头，只能包含小写字母、数字、下划线和连字符。"
        read -rp "按 Enter 继续..."
        return 1
    fi

    # 检查用户是否已存在
    if id "$username" &>/dev/null; then
        log_error "用户 $username 已存在"
        read -rp "按 Enter 继续..."
        return 1
    fi

    printf "正在创建用户：%s...\n" "$username"

    # 创建用户
    if ! useradd -m -s /bin/bash "$username" 2>/dev/null; then
        log_error "创建用户失败，请检查系统命令"
        read -rp "按 Enter 继续..."
        return 1
    fi

    # 添加到 sudo 组
    if command -v usermod &>/dev/null; then
        usermod -aG sudo "$username" 2>/dev/null || \
        usermod -aG wheel "$username" 2>/dev/null || \
        echo "$username ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers 2>/dev/null
    fi

    log_success "用户 $username 创建成功"

    # 复制安装脚本到新用户 home 目录
    local script_name
    script_name=$(basename "$ORIGINAL_SCRIPT_PATH")
    local target_dir="/home/$username"

    if [ -f "$ORIGINAL_SCRIPT_PATH" ]; then
        cp "$ORIGINAL_SCRIPT_PATH" "$target_dir/"
        chown "$username:$username" "$target_dir/$script_name"
        chmod 755 "$target_dir/$script_name"
        log_info "安装脚本已复制到：$target_dir/$script_name"
    fi

    # 显示切换指引
    tui_clear

    if [ "$TUI_USE_TPUT" = "true" ]; then
        printf '%s%s%s\n\n' "$TUI_TPUT_BOLD" "用户创建完成" "$TUI_TPUT_RESET"
    else
        printf '\033[1m用户创建完成\033[0m\n\n'
    fi

    printf '请按以下步骤操作：\n\n'
    printf '  1. 切换用户：\n'
    printf '     \033[1;32msu - %s\033[0m\n\n' "$username"
    printf '  2. 重新运行安装：\n'
    printf '     \033[1;32m./%s\033[0m\n\n' "$script_name"
    printf '\n按 Enter 键退出...'
    read -r

    exit 0
}

do_switch_user_flow() {
    tui_clear

    # 获取所有非 root 用户（/home 下有主目录的用户）
    local users=()
    local user_values=()

    if [ -d "/home" ]; then
        for dir in /home/*/; do
            if [ -d "$dir" ]; then
                local user
                user=$(basename "$dir")
                if id "$user" &>/dev/null; then
                    users+=("$user")
                    user_values+=("$user")
                fi
            fi
        done
    fi

    # 检查是否有可用用户
    if [ ${#users[@]} -eq 0 ]; then
        log_error "未找到可用的非 root 用户"
        echo ""
        echo "请先创建一个新用户，或选择"新建 sudo 用户"选项。"
        read -rp "按 Enter 继续..."
        return 1
    fi

    # 创建 TUI 菜单
    tui_clear

    if [ "$TUI_USE_TPUT" = "true" ]; then
        printf '%s%s%s\n\n' "$TUI_TPUT_BOLD" "选择要切换的用户" "$TUI_TPUT_RESET"
    else
        printf '\033[1m选择要切换的用户\033[0m\n\n'
    fi

    local menu_id
    tui_menu_create "选择用户"

    for i in "${!users[@]}"; do
        tui_menu_add "$menu_id" "${users[$i]}" "${user_values[$i]}" false
    done

    # 运行菜单
    local result
    tui_menu_run "$menu_id"
    result="$TUI_LAST_RESULT"

    if [ -z "$result" ]; then
        log_warn "用户取消选择"
        return 1
    fi

    local target_user="$result"
    log_info "切换到用户：$target_user"

    # 复制安装脚本到目标用户 home 目录
    local script_name
    script_name=$(basename "$ORIGINAL_SCRIPT_PATH")
    local target_dir="/home/$target_user"

    if [ -f "$ORIGINAL_SCRIPT_PATH" ]; then
        cp "$ORIGINAL_SCRIPT_PATH" "$target_dir/"
        chown "$target_user:$target_user" "$target_dir/$script_name"
        chmod 755 "$target_dir/$script_name"
        log_info "安装脚本已复制到：$target_dir/$script_name"
    fi

    # 使用 su 切换用户并重新执行
    tui_clear

    if [ "$TUI_USE_TPUT" = "true" ]; then
        printf '%s%s%s\n\n' "$TUI_TPUT_BOLD" "切换用户" "$TUI_TPUT_RESET"
    else
        printf '\033[1m切换用户\033[0m\n\n'
    fi

    printf '正在切换到用户：%s...\n\n' "$target_user"
    printf '在新会话中重新执行安装脚本。\n\n'

    # 创建一个临时脚本在新用户上下文中执行
    local temp_script="$target_dir/install_temp.sh"
    cat > "$temp_script" << EOF
#!/bin/bash
echo "================================"
echo "  已切换到用户：$target_user"
echo "================================"
echo ""
echo "正在重新执行安装脚本..."
cd "$target_dir"
./$script_name
EOF
    chown "$target_user:$target_user" "$temp_script"
    chmod 755 "$temp_script"

    # 使用 su -c 执行
    su - "$target_user" -c "cd $target_dir && ./install_temp.sh"

    # 如果 su 失败，提供手动指引
    if [ $? -ne 0 ]; then
        tui_clear
        printf '\033[1m手动切换指引\033[0m\n\n'
        printf '请手动执行以下命令：\n\n'
        printf '  \033[1;32msu - %s\033[0m\n\n' "$target_user"
        printf '然后在新会话中执行：\n\n'
        printf '  \033[1;32mcd %s && ./%s\033[0m\n\n' "$target_dir" "$script_name"
        printf '\n按 Enter 键退出...'
        read -r
    fi

    exit 0
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
# Download Functions
# ============================================================================

download_binary() {
    local output="$1"
    local binary_name="starman-$ARCH-linux"

    # Construct URLs
    local github_url="$GITHUB_RELEASE/$binary_name"
    local gitee_url="$GITEE_RELEASE/$binary_name"

    log_info "正在下载 starman 二进制..."

    # Try GitHub first if available
    if [ "$GITHUB_AVAILABLE" = true ]; then
        log_info "从 GitHub 下载：$github_url"
        if curl -fsSL -C - "$github_url" -o "$output" 2>/dev/null; then
            log_success "下载成功"
            return 0
        fi
    fi

    # Fallback to Gitee
    if [ "$GITEE_AVAILABLE" = true ]; then
        log_warn "GitHub 下载失败，切换到 Gitee..."
        log_info "从 Gitee 下载：$gitee_url"
        if curl -fsSL -C - "$gitee_url" -o "$output"; then
            log_success "下载成功"
            return 0
        fi
    fi

    log_error "下载失败，请检查网络连接或手动下载"
    echo ""
    echo "离线安装指引："
    echo "1. 在其他机器下载：$github_url"
    echo "2. 将文件复制到本机的 /tmp/starman"
    echo "3. 重新运行此脚本"
    return 1
}

verify_checksum() {
    local binary="$1"
    local checksum_file="$2"

    if [ -f "$checksum_file" ]; then
        log_info "验证 checksum..."
        local expected
        expected=$(cat "$checksum_file" | awk '{print $1}')
        local actual
        actual=$(sha256sum "$binary" | awk '{print $1}')

        if [ "$expected" = "$actual" ]; then
            log_success "Checksum 验证通过"
            return 0
        else
            log_error "Checksum 验证失败"
            return 1
        fi
    fi
    return 0
}

# ============================================================================
# Installation Functions
# ============================================================================

install_binary() {
    local binary="$1"

    log_info "正在安装 starman 到系统..."

    # Create config directory
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        log_info "创建配置目录：$CONFIG_DIR"
    fi

    # Copy binary
    if [ "$IS_ROOT" = true ]; then
        cp "$binary" "$INSTALL_DIR/$STARMAN_BIN"
        chmod 755 "$INSTALL_DIR/$STARMAN_BIN"
        chown root:root "$INSTALL_DIR/$STARMAN_BIN"
    else
        sudo cp "$binary" "$INSTALL_DIR/$STARMAN_BIN"
        sudo chmod 755 "$INSTALL_DIR/$STARMAN_BIN"
        sudo chown root:root "$INSTALL_DIR/$STARMAN_BIN"
    fi

    log_success "已安装到 $INSTALL_DIR/$STARMAN_BIN"
}

deploy_completions() {
    log_info "部署补全脚本..."

    # Bash completion
    local bash_comp="/etc/bash_completion.d/starman"
    if [ -d "/etc/bash_completion.d" ]; then
        if [ "$IS_ROOT" = true ]; then
            cat > "$bash_comp" << 'EOF'
_starman() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "--help --version" -- "$cur"))
}
complete -F _starman starman
EOF
            log_info "已部署 bash 补全"
        fi
    fi

    # Zsh completion
    local zsh_comp="/usr/local/share/zsh/site-functions/_starman"
    if [ -d "/usr/local/share/zsh/site-functions" ] || mkdir -p "$(dirname "$zsh_comp")" 2>/dev/null; then
        if [ "$IS_ROOT" = true ]; then
            cat > "$zsh_comp" << 'EOF'
#compdef starman
_starman() {
    _arguments '--help[显示帮助]' '--version[显示版本]'
}
_starman
EOF
            log_info "已部署 zsh 补全"
        fi
    fi
}

verify_installation() {
    log_info "验证安装..."

    if command -v starman &>/dev/null; then
        local version
        version=$(starman --version 2>/dev/null || echo "unknown")
        log_success "安装成功！版本：$version"
        return 0
    else
        log_warn "starman 未在 PATH 中，可能需要重新加载 shell"
        return 1
    fi
}

# ============================================================================
# Post-Installation
# ============================================================================

# ============================================================================
# Step Functions (Placeholders for sub-changes)
# ============================================================================

# run_step_packages - 安装系统软件包（占位，由子变更实现）
# TODO: 由 package-install 子变更实现
run_step_packages() {
    log_info "run_step_packages: TODO - 由 package-install 子变更实现"
}

# run_step_disk - 磁盘分区与挂载（占位，由子变更实现）
# TODO: 由 disk-mount 子变更实现
run_step_disk() {
    log_info "run_step_disk: TODO - 由 disk-mount 子变更实现"
}

# run_step_user - 用户配置（占位，由子变更实现）
# TODO: 由 user-config 子变更实现
run_step_user() {
    log_info "run_step_user: TODO - 由 user-config 子变更实现"
}

# run_step_services - 服务配置（占位，由子变更实现）
# TODO: 由 services-config 子变更实现
run_step_services() {
    log_info "run_step_services: TODO - 由 services-config 子变更实现"
}

ask_run_setup() {
    echo ""
    log_info "============================================"
    log_info "  安装完成"
    log_info "============================================"
    echo ""
    echo "是否立即运行装机脚本初始化系统？"
    echo ""
    read -rp "[?] 是否立即运行装机脚本？[Y/n] " answer
    case "$answer" in
        [nN]|[nN][oO])
            echo ""
            log_info "稍后可通过以下命令运行装机脚本："
            echo "  starman setup"
            ;;
        *)
            log_info "正在启动装机脚本..."
            if command -v starman &>/dev/null; then
                starman setup || log_warn "装机脚本执行失败"
            else
                log_error "starman 未找到，无法运行装机脚本"
            fi
            ;;
    esac
}

show_offline_guide() {
    echo ""
    log_info "============================================"
    log_info "  离线安装指引"
    log_info "============================================"
    echo ""
    echo "如果无法在线下载，可按以下步骤离线安装："
    echo ""
    echo "1. 在其他机器下载二进制文件："
    echo "   curl -LO https://github.com/STAR-Organization/starman/releases/latest/download/starman-$ARCH-linux"
    echo ""
    echo "2. 将文件复制到目标机器的 /tmp/starman"
    echo ""
    echo "3. 在目标机器执行："
    echo "   sudo cp /tmp/starman /usr/sbin/starman"
    echo "   sudo chmod 755 /usr/sbin/starman"
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
    detect_arch || exit 1
    detect_user
    detect_sudo
    detect_script_path

    # Check sudo before network detection
    check_sudo

    # Guide root user (mandatory)
    guide_root_user

    # Detect network
    detect_network || {
        show_offline_guide
        exit 1
    }

    # Download binary
    local temp_binary
    temp_binary=$(mktemp)/starman
    download_binary "$temp_binary" || {
        show_offline_guide
        exit 1
    }

    # Verify checksum (optional)
    # verify_checksum "$temp_binary" "$temp_binary.sha256"

    # Install
    install_binary "$temp_binary"

    # Deploy completions
    deploy_completions

    # Verify
    verify_installation

    # Cleanup
    rm -f "$temp_binary"

    # Ask to run setup script
    ask_run_setup

    log_info ""
    log_info "=== Installation Complete ==="
}

main "$@"
