#!/bin/bash
#
# Starman VM Restore Script
#
# Usage: ./restore-vm.sh <vm-name>
#        ./restore-vm.sh --all
#
# This script restores virtual machine images from backup.
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
    echo "  --all      恢复所有测试虚拟机"
    echo ""
    echo "示例："
    echo "  $0 centos7-test     # 恢复 centos7-test 虚拟机"
    echo "  $0 --all            # 恢复所有测试虚拟机"
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

# Restore a single VM
restore_vm() {
    local vm_name="$1"
    local backup_file="$BACKUP_DIR/${vm_name}-backup.qcow2"

    log_info "============================================"
    log_info "  恢复虚拟机：$vm_name"
    log_info "============================================"

    # Check if backup exists
    if [ ! -f "$backup_file" ]; then
        log_error "备份文件不存在：$backup_file"
        log_info "请先执行备份：./backup-vm.sh $vm_name"
        return 1
    fi

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

    log_info "原始镜像：$image_path"
    log_info "备份文件：$backup_file"

    # Confirm before restore
    read -rp "是否确认恢复？这将覆盖当前虚拟机状态 [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            log_info "开始恢复..."
            ;;
        *)
            log_info "取消恢复：$vm_name"
            return 0
            ;;
    esac

    # Copy backup to original location
    log_info "正在从备份恢复镜像..."
    rsync -ah --progress "$backup_file" "$image_path"

    log_success "恢复完成：$vm_name"
    log_info "请使用以下命令启动虚拟机："
    echo "  virsh -c qemu:///session start $vm_name"
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "=== Starman VM Restore Script ==="
    log_info ""

    # Parse arguments
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    if [ "$1" = "--all" ]; then
        # Restore all test VMs
        log_info "恢复所有测试虚拟机..."
        log_info ""

        local success_count=0
        local fail_count=0

        for vm in "${TEST_VMS[@]}"; do
            if vm_exists "$vm"; then
                if restore_vm "$vm"; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                    log_warn "恢复失败：$vm"
                fi
                log_info ""
            else
                log_warn "虚拟机不存在，跳过：$vm"
                log_info ""
            fi
        done

        log_info "============================================"
        log_info "  恢复完成"
        log_info "============================================"
        log_info "成功：$success_count, 失败：$fail_count"
    else
        # Restore single VM
        restore_vm "$1"
    fi

    log_info ""
    log_info "=== Restore Complete ==="
}

main "$@"
