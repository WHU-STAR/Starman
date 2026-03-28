#!/bin/bash
#
# 为 libvirt 域 ubuntu22-test 增加一块 virtio 数据盘（qcow2），用于在客体里测试 Starman 数据盘挂载 / disk_lab。
#
# 用法：
#   bash scripts/vm/attach-ubuntu-data-disk.sh           # 创建/附加默认 2G 盘到 vdb
#   bash scripts/vm/attach-ubuntu-data-disk.sh --size 5G # 指定大小（仅当镜像尚不存在时生效）
#
# 依赖：qemu-img、virsh（qemu:///session）；虚拟机可处于 running（热插）或 shut off。
# 数据文件：~/.local/libvirt/images/ubuntu22-test-data.qcow2
#
# 测试后若需恢复单一系统盘状态，见同目录 detach-ubuntu-data-disk.sh；完整基线恢复仍用 restore-vm.sh（建议先 detach 额外盘以免域 XML 与备份不一致）。
#

set -euo pipefail

LIBVIRT_URI="qemu:///session"
VM="ubuntu22-test"
DISK_NAME="ubuntu22-test-data.qcow2"
DISK_DIR="${DISK_DIR:-$HOME/.local/libvirt/images}"
DISK_PATH="$DISK_DIR/$DISK_NAME"
TARGET_VIRTIO="${TARGET_VIRTIO:-vdb}"
SIZE="${SIZE:-2G}"

usage() {
    sed -n '1,20p' "$0" | tail -n +2 | sed 's/^# \?//'
}

while [ "${1:-}" = "--size" ] && [ -n "${2:-}" ]; do
    SIZE="$2"
    shift 2
done

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if ! virsh -c "$LIBVIRT_URI" dominfo "$VM" &>/dev/null; then
    echo "错误：域不存在 $VM" >&2
    exit 1
fi

mkdir -p "$DISK_DIR"

if [ ! -f "$DISK_PATH" ]; then
    echo "[INFO] 创建数据盘镜像：$DISK_PATH（$SIZE）"
    qemu-img create -f qcow2 "$DISK_PATH" "$SIZE"
else
    echo "[INFO] 已存在镜像：$DISK_PATH（跳过 qemu-img create）"
fi

if virsh -c "$LIBVIRT_URI" domblklist "$VM" --details 2>/dev/null | awk '{print $3}' | grep -qx "$TARGET_VIRTIO"; then
    echo "[INFO] 目标 $TARGET_VIRTIO 已存在，跳过 attach"
else
    echo "[INFO] 附加磁盘 -> $VM:$TARGET_VIRTIO"
    virsh -c "$LIBVIRT_URI" attach-disk "$VM" "$DISK_PATH" "$TARGET_VIRTIO" \
        --cache none --subdriver qcow2 --persistent
fi

echo ""
echo "[SUCCESS] 客体中可执行：lsblk -f  （应看到约 ${SIZE} 的磁盘，一般为 /dev/${TARGET_VIRTIO}）"
echo "          未分区整块设备可用于 disk_lab 交互测试（请先备份 VM，测试 destructive 操作有风险）。"
