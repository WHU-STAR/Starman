#!/bin/bash
#
# Starman 安装脚本 - 统一入口
#
# 用法：
#   curl -fsSL <url>/install.sh | bash
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

# 软件包与配置步骤（OpenSpec: install-script-packages-config）
if [ -f "$SCRIPT_DIR/scripts/steps/packages.sh" ]; then
    # shellcheck source=scripts/steps/packages.sh
    source "$SCRIPT_DIR/scripts/steps/packages.sh"
fi

# ============================================================================
# 安装步骤函数
# ============================================================================

if ! declare -F run_step_packages >/dev/null 2>&1; then
    run_step_packages() {
        log_warn "未找到 scripts/steps/packages.sh，跳过软件包步骤"
    }
fi

run_step_disk() {
    log_info "正在检测磁盘空间..."
    # TODO: 由子 change 实现完整的磁盘检测逻辑
    log_success "磁盘空间检测完成"
}

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

    # 检测 sudo 权限
    require_sudo

    # 执行安装步骤
    log_info "开始执行安装步骤..."
    echo ""

    run_step_packages
    run_step_disk

    echo ""
    log_success "Starman 系统配置完成"
}

# 支持被 source 时不执行 main，仅供函数定义
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
