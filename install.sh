#!/bin/bash
#
# Starman 安装脚本 - 统一入口
#
# 用法（须交互式终端，勿使用管道）：
#   curl -fsSL <url>/install.sh -o /tmp/starman-install.sh && bash /tmp/starman-install.sh
#   或
#   git clone <repo> && cd <repo> && bash install.sh
#

set -e

# ============================================================================
# 引导阶段：定位脚本目录并切换到项目根
# ============================================================================

# 获取当前脚本所在目录（支持被 source 或直接执行）
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    local dir
    if [ -L "$source" ]; then
        # 如果是符号链接，解析真实路径
        dir="$(cd "$(dirname "$source")" && pwd)"
    else
        dir="$(cd "$(dirname "$source")" && pwd)"
    fi
    echo "$dir"
}

SCRIPT_DIR="$(get_script_dir)"

# 切换到项目根目录（假设 install.sh 在项目根）
cd "$SCRIPT_DIR"

# ============================================================================
# 源入依赖库
# ============================================================================

# 源入公共库（如果存在）
if [ -f "$SCRIPT_DIR/scripts/lib/common.sh" ]; then
    source "$SCRIPT_DIR/scripts/lib/common.sh"
fi

# 源入 TUI 库
if [ -f "$SCRIPT_DIR/scripts/lib/tui.sh" ]; then
    source "$SCRIPT_DIR/scripts/lib/tui.sh"
fi

# 源入包管理器库
if [ -f "$SCRIPT_DIR/scripts/lib/pkgmgr.sh" ]; then
    source "$SCRIPT_DIR/scripts/lib/pkgmgr.sh"
fi

# 装机状态（续跑；OpenSpec: install-script-mihomo）
if [ -f "$SCRIPT_DIR/scripts/lib/starman_state.sh" ]; then
    # shellcheck source=scripts/lib/starman_state.sh
    source "$SCRIPT_DIR/scripts/lib/starman_state.sh"
fi

# 软件包与配置步骤（OpenSpec: install-script-packages-config）
if [ -f "$SCRIPT_DIR/scripts/steps/packages.sh" ]; then
    # shellcheck source=scripts/steps/packages.sh
    source "$SCRIPT_DIR/scripts/steps/packages.sh"
fi

# 数据盘与 lab 共享（OpenSpec: install-script-disk-lab）
if [ -f "$SCRIPT_DIR/scripts/steps/disk_lab.sh" ]; then
    # shellcheck source=scripts/steps/disk_lab.sh
    source "$SCRIPT_DIR/scripts/steps/disk_lab.sh"
fi

# Linuxbrew 模板（OpenSpec: install-script-brew）
if [ -f "$SCRIPT_DIR/scripts/steps/brew.sh" ]; then
    # shellcheck source=scripts/steps/brew.sh
    source "$SCRIPT_DIR/scripts/steps/brew.sh"
fi

# OpenSSH 服务端片段（OpenSpec: install-script-ssh）
if [ -f "$SCRIPT_DIR/scripts/steps/ssh.sh" ]; then
    # shellcheck source=scripts/steps/ssh.sh
    source "$SCRIPT_DIR/scripts/steps/ssh.sh"
fi

# mihomo 与 systemd（OpenSpec: install-script-mihomo）
if [ -f "$SCRIPT_DIR/scripts/steps/mihomo.sh" ]; then
    # shellcheck source=scripts/steps/mihomo.sh
    source "$SCRIPT_DIR/scripts/steps/mihomo.sh"
fi

# ============================================================================
# 安装步骤函数
# ============================================================================

if ! declare -F run_step_packages >/dev/null 2>&1; then
    run_step_packages() {
        log_warn "未找到 scripts/steps/packages.sh，跳过软件包步骤"
        return 3
    }
fi

if ! declare -F run_step_disk_lab >/dev/null 2>&1; then
    run_step_disk_lab() {
        log_warn "未找到 scripts/steps/disk_lab.sh，跳过数据盘与 lab 步骤"
        return 3
    }
fi

if ! declare -F run_step_brew >/dev/null 2>&1; then
    run_step_brew() {
        log_warn "未找到 scripts/steps/brew.sh，跳过 Linuxbrew 步骤"
        return 3
    }
fi

if ! declare -F run_step_ssh >/dev/null 2>&1; then
    run_step_ssh() {
        log_warn "未找到 scripts/steps/ssh.sh，跳过 SSH 服务端步骤"
        return 3
    }
fi

if ! declare -F run_step_mihomo >/dev/null 2>&1; then
    run_step_mihomo() {
        log_warn "未找到 scripts/steps/mihomo.sh，跳过 mihomo 步骤"
        return 3
    }
fi

# ============================================================================
# 主流程
# ============================================================================

main() {
    # Banner
    if command -v ui_banner_starman &>/dev/null; then
        ui_banner_starman
    fi

    # 基本信息
    log_info "用户：$(whoami)"
    log_info "工作目录：$(pwd)"

    local os_type="unknown"
    if command -v detect_os &>/dev/null; then
        os_type="$(detect_os)"
    fi
    log_info "操作系统：$os_type"
    log_info "架构：$(uname -m)"
    log_info "内核：$(uname -r)"
    echo ""

    require_interactive_terminal

    # 检测 sudo 权限
    require_sudo

    # 装机状态与续跑菜单（需 python3 + TUI；无进度时等价于完整安装）
    if declare -F starman_install_flow_prompt &>/dev/null; then
        starman_install_flow_prompt
    fi

    # 执行安装步骤（续跑模式下跳过状态中已完成的步骤）
    log_info "开始执行安装步骤..."
    echo ""

    if declare -F starman_run_step_maybe_skip &>/dev/null; then
        starman_run_step_maybe_skip packages run_step_packages
        starman_run_step_maybe_skip disk_lab run_step_disk_lab
        starman_run_step_maybe_skip brew run_step_brew
        starman_run_step_maybe_skip ssh run_step_ssh
        starman_run_step_maybe_skip mihomo run_step_mihomo
    else
        run_step_packages
        run_step_disk_lab
        run_step_brew
        run_step_ssh
        run_step_mihomo
    fi

    echo ""
    log_success "Starman 系统配置完成"
}

# 支持被 source 时不执行 main，仅供函数定义
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
