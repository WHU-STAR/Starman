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

# ============================================================================
# 安装步骤函数（骨架，由子 change 实现）
# ============================================================================

run_step_packages() {
    log_info "正在检测并安装系统包..."
    # TODO: 由子 change 实现完整的包管理逻辑
    log_success "系统包检测完成"
}

run_step_disk() {
    log_info "正在检测磁盘空间..."
    # TODO: 由子 change 实现完整的磁盘检测逻辑
    log_success "磁盘空间检测完成"
}

# ============================================================================
# 主流程
# ============================================================================

main() {
    log_info "Starman 安装脚本已启动"
    log_info "工作目录：$(pwd)"

    # 环境检测阶段
    log_info "正在进行环境检测..."

    # 检测是否为 root 用户（root 用户需要特殊处理）
    if [ "$(id -u)" -eq 0 ]; then
        log_warn "检测到 root 用户运行，需要切换到非 root 用户"
        # TODO: 调用 TUI 菜单引导用户创建或切换用户
        # 此功能由 installer-user-prompt change 实现
    fi

    # 检测 sudo 权限
    require_sudo

    # 检测操作系统
    local os_type
    os_type="$(detect_os)"
    log_info "检测到操作系统：$os_type"

    # 执行安装步骤
    echo ""
    log_info "开始执行安装步骤..."

    run_step_packages
    run_step_disk

    echo ""
    log_success "Starman 安装脚本执行完成"
}

# 支持被 source 时不执行 main，仅供函数定义
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
