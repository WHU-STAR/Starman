#!/bin/bash
#
# 从 ubuntu22-test 分离由 attach-ubuntu-data-disk.sh 附加的数据盘，并可选删除 qcow2 文件。
#
# 用法：
#   bash scripts/vm/detach-ubuntu-data-disk.sh           # 分离 vdb，保留镜像文件
#   bash scripts/vm/detach-ubuntu-data-disk.sh --remove-file  # 分离并删除数据镜像
#
# 若虚拟机正在运行，支持热拔（客体请先 umount / 勿占用该盘）。
#

set -euo pipefail

LIBVIRT_URI="qemu:///session"
VM="ubuntu22-test"
DISK_DIR="${DISK_DIR:-$HOME/.local/libvirt/images}"
DISK_NAME="ubuntu22-test-data.qcow2"
DISK_PATH="$DISK_DIR/$DISK_NAME"
TARGET_VIRTIO="${TARGET_VIRTIO:-vdb}"

REMOVE_FILE=false
if [ "${1:-}" = "--remove-file" ]; then
    REMOVE_FILE=true
fi

if ! virsh -c "$LIBVIRT_URI" dominfo "$VM" &>/dev/null; then
    echo "错误：域不存在 $VM" >&2
    exit 1
fi

if virsh -c "$LIBVIRT_URI" domblklist "$VM" --details 2>/dev/null | awk '{print $3}' | grep -qx "$TARGET_VIRTIO"; then
    echo "[INFO] 分离 $VM 的 $TARGET_VIRTIO"
    virsh -c "$LIBVIRT_URI" detach-disk "$VM" "$TARGET_VIRTIO" --persistent
else
    echo "[WARN] 未找到目标 $TARGET_VIRTIO，跳过 detach"
fi

if [ "$REMOVE_FILE" = true ] && [ -f "$DISK_PATH" ]; then
    echo "[INFO] 删除镜像：$DISK_PATH"
    rm -f "$DISK_PATH"
fi

echo "[SUCCESS] 完成。"
