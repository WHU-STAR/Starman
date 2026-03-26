#!/bin/bash
#
# Starman Bootstrap Installer
#
# Usage: curl -fsSL <url> | bash
#
# This script downloads and executes the main install.sh script
# from GitHub Releases or Gitee mirror.
#
# Copyright (c) STAR Laboratory. All rights reserved.
# Licensed under the GPL License.
#

set -e

# ============================================================================
# Configuration
# ============================================================================

GITEE_BASE="https://gitee.com/ajgamma/starman"

# Latest release installer URL (Gitee only)
GITEE_INSTALLER="$GITEE_BASE/raw/master/installers/install.sh"

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

# ============================================================================
# Environment Detection
# ============================================================================

detect_downloader() {
    if command -v curl &>/dev/null; then
        DOWNLOADER="curl"
        return 0
    elif command -v wget &>/dev/null; then
        DOWNLOADER="wget"
        return 0
    else
        log_error "未找到 curl 或 wget，请先安装其中一个"
        return 1
    fi
}

# ============================================================================
# Download Functions
# ============================================================================

download_file() {
    local url="$1"
    local output="$2"

    case "$DOWNLOADER" in
        curl)
            curl -fsSL "$url" -o "$output"
            ;;
        wget)
            wget -q --show-progress "$url" -O "$output"
            ;;
    esac
}

download_and_run() {
    local gitee_url="$1"
    local temp_file

    temp_file=$(mktemp -d)/install.sh

    log_info "正在下载安装脚本..."

    # Download from Gitee
    if download_file "$gitee_url" "$temp_file"; then
        log_info "已从 Gitee 下载安装脚本"
    else
        log_error "无法下载安装脚本，请检查网络连接"
        rm -f "$temp_file"
        return 1
    fi

    # Execute the install script
    log_info "正在执行安装脚本..."
    bash "$temp_file"
    local status=$?

    # Cleanup
    rm -f "$temp_file"

    return $status
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "=== Starman Bootstrap Installer ==="
    log_info ""

    # Detect downloader
    if ! detect_downloader; then
        exit 1
    fi
    log_info "使用下载工具：$DOWNLOADER"

    # Download and run install script from Gitee
    download_and_run "$GITEE_INSTALLER"

    log_info ""
    log_info "=== Bootstrap Complete ==="
}

main "$@"
