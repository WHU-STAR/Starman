#!/bin/bash
#
# Starman VM Backup Script
#
# Usage: ./backup-vm.sh <vm-name>
#        ./backup-vm.sh --all
#
# This script backs up virtual machine images to a backup directory.
#
# Copyright (c) STAR Laboratory. All rights reserved.
# Licensed under the GPL License.
#

set -e

# ============================================================================
# Configuration
# ============================================================================

LIBVIRT_URI="qemu:///session"
BACKUP_DIR="$HOME/.local/libvirt/images/backups"

# Test VMs list
TEST_VMS=("centos7-test" "ubuntu22-test" "fedora-test")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

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

usage() {
    echo "用法：$0 <vm-name>"
    echo "      $0 --all"
    echo ""
    echo "选项："
    echo "  vm-name    虚拟机名称（如 centos7-test, ubuntu22-test, fedora-test）"
    echo "  --all      备份所有测试虚拟机"
    echo ""
    echo "示例："
    echo "  $0 centos7-test     # 备份 centos7-test 虚拟机"
    echo "  $0 --all            # 备份所有测试虚拟机"
}

# ============================================================================
# VM Operations
# ============================================================================

# Check if VM exists
vm_exists() {
    local vm_name="$1"
    virsh -c "$LIBVIRT_URI" dominfo "$vm_name" &>/dev/null
}

# Get VM state (running, shut off, etc.)
vm_get_state() {
    local vm_name="$1"
    virsh -c "$LIBVIRT_URI" domstate "$vm_name" 2>/dev/null
}

# Shutdown VM gracefully
vm_shutdown() {
    local vm_name="$1"
    log_info "正在关闭虚拟机：$vm_name..."
    virsh -c "$LIBVIRT_URI" shutdown "$vm_name"

    # Wait for VM to shut down (max 60 seconds)
    local timeout=60
    local elapsed=0
    while [ "$(vm_get_state "$vm_name")" != "shut off" ] && [ $elapsed -lt $timeout ]; do
        sleep 2
        elapsed=$((elapsed + 2))
        log_info "等待虚拟机关闭... ($elapsed/$timeout)"
    done

    if [ "$(vm_get_state "$vm_name")" != "shut off" ]; then
        log_warn "虚拟机未能在 ${timeout} 秒内关闭，强制关闭..."
        virsh -c "$LIBVIRT_URI" destroy "$vm_name"
        sleep 2
    fi

    log_success "虚拟机已关闭：$vm_name"
}

# Get VM image path
vm_get_image_path() {
    local vm_name="$1"
    # Get the first disk (vda usually)
    virsh -c "$LIBVIRT_URI" domblklist "$vm_name" 2>/dev/null | \
        grep -E "^\\s+vda\\s" | \
        awk '{print $2}'
}

# Backup a single VM
backup_vm() {
    local vm_name="$1"
    local backup_file="$BACKUP_DIR/${vm_name}-backup.qcow2"

    log_info "============================================"
    log_info "  备份虚拟机：$vm_name"
    log_info "============================================"

    # Check if VM exists
    if ! vm_exists "$vm_name"; then
        log_error "虚拟机不存在：$vm_name"
        return 1
    fi

    # Get VM state
    local vm_state
    vm_state=$(vm_get_state "$vm_name")
    log_info "虚拟机状态：$vm_state"

    # Shutdown if running
    if [ "$vm_state" = "running" ]; then
        log_warn "虚拟机正在运行，需要先关闭"
        vm_shutdown "$vm_name"
    fi

    # Get image path
    local image_path
    image_path=$(vm_get_image_path "$vm_name")

    if [ -z "$image_path" ] || [ ! -f "$image_path" ]; then
        log_error "无法找到虚拟机镜像文件"
        return 1
    fi

    log_info "镜像文件：$image_path"

    # Check if backup already exists
    if [ -f "$backup_file" ]; then
        log_warn "备份文件已存在：$backup_file"
        read -rp "是否覆盖现有备份？[y/N] " answer
        case "$answer" in
            [yY]|[yY][eE][sS])
                log_info "覆盖现有备份..."
                ;;
            *)
                log_info "跳过备份：$vm_name"
                return 0
                ;;
        esac
    fi

    # Copy image to backup directory
    log_info "正在复制镜像到备份目录..."
    rsync -ah --progress "$image_path" "$backup_file"

    log_success "备份完成：$backup_file"
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "=== Starman VM Backup Script ==="
    log_info ""

    # Create backup directory if not exists
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_info "创建备份目录：$BACKUP_DIR"
    fi

    # Parse arguments
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    if [ "$1" = "--all" ]; then
        # Backup all test VMs
        log_info "备份所有测试虚拟机..."
        log_info ""

        for vm in "${TEST_VMS[@]}"; do
            if vm_exists "$vm"; then
                backup_vm "$vm" || log_warn "备份失败：$vm"
                log_info ""
            else
                log_warn "虚拟机不存在，跳过：$vm"
                log_info ""
            fi
        done

        log_success "所有虚拟机备份完成"
    else
        # Backup single VM
        backup_vm "$1"
    fi

    log_info ""
    log_info "=== Backup Complete ==="
}

main "$@"
