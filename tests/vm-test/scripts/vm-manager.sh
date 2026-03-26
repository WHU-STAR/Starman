#!/bin/bash
#
# VM Manager - KVM/QEMU VM 生命周期管理
#
# 用途：提供 VM 的创建、启动、停止、快照、文件传输等功能
#
# 用法示例：
#
#   source tests/vm-test/scripts/vm-manager.sh
#
#   # 创建 VM
#   vm_create "ubuntu-cloud.img"
#
#   # 创建快照
#   vm_snapshot_create "clean"
#
#   # 恢复快照
#   vm_snapshot_restore "clean"
#
#   # 执行命令
#   vm_exec "echo hello"
#
#   # 上传文件
#   vm_upload ./local.sh /tmp/remote.sh
#
# 依赖：KVM/QEMU, socat (用于串行控制台通信)
#

set -u

# ============================================================================
# 全局变量
# ============================================================================

VM_NAME="starman-test-vm"
VM_DISK_IMAGE=""
VM_SERIAL_SOCKET="/tmp/starman-vm-serial.sock"
VM_SSH_PORT=2222
VM_PID=""

# ============================================================================
# VM 生命周期管理
# ============================================================================

# 创建 VM（定义但不启动）
# 用法：vm_create <disk-image-path> [memory-size]
vm_create() {
    local disk_image="$1"
    local memory="${2:-1024}"

    if [ -z "$disk_image" ]; then
        echo "ERROR: 请指定磁盘镜像路径" >&2
        return 1
    fi

    VM_DISK_IMAGE="$disk_image"

    # 检查镜像是否存在
    if [ ! -f "$disk_image" ]; then
        echo "ERROR: 磁盘镜像不存在：$disk_image" >&2
        echo "请使用 cloud-image 或其他工具创建镜像" >&2
        return 1
    fi

    echo "VM 配置："
    echo "  名称：$VM_NAME"
    echo "  磁盘：$disk_image"
    echo "  内存：${memory}MB"
    echo "  SSH 端口：$VM_SSH_PORT"
    echo "  串行控制台：$VM_SERIAL_SOCKET"
}

# 启动 VM
# 用法：vm_start [background]
vm_start() {
    local background="${1:-true}"

    if [ -z "$VM_DISK_IMAGE" ]; then
        echo "ERROR: VM 磁盘镜像未设置，请先调用 vm_create" >&2
        return 1
    fi

    # 移除旧的 socket
    rm -f "$VM_SERIAL_SOCKET"

    local qemu_args=(
        qemu-system-x86_64
        -enable-kvm
        -m 1024
        -drive "format=qcow2,file=$VM_DISK_IMAGE"
        -netdev "user,id=net0,hostfwd=tcp::$VM_SSH_PORT-:22"
        -device e1000,netdev=net0
        -serial "unix:$VM_SERIAL_SOCKET,server=nowait"
        -display none
        -daemonize
    )

    echo "正在启动 VM..."
    if "${qemu_args[@]}"; then
        echo "VM 已启动"
        VM_PID=$!
        return 0
    else
        echo "ERROR: VM 启动失败" >&2
        return 1
    fi
}

# 停止 VM
vm_stop() {
    echo "正在停止 VM..."

    # 尝试通过串行控制台发送关机命令
    if [ -S "$VM_SERIAL_SOCKET" ]; then
        echo "shutdown" | socat - "unix-connect:$VM_SERIAL_SOCKET" 2>/dev/null || true
    fi

    # 等待进程结束
    sleep 2

    # 强制杀死进程
    if [ -n "$VM_PID" ] && kill -0 "$VM_PID" 2>/dev/null; then
        kill "$VM_PID" 2>/dev/null || true
        wait "$VM_PID" 2>/dev/null || true
    fi

    # 清理 socket
    rm -f "$VM_SERIAL_SOCKET"

    echo "VM 已停止"
}

# 销毁 VM（删除磁盘镜像）
vm_destroy() {
    local disk_image="$VM_DISK_IMAGE"

    vm_stop

    if [ -n "$disk_image" ] && [ -f "$disk_image" ]; then
        echo "正在删除磁盘镜像：$disk_image"
        rm -f "$disk_image"
    fi

    echo "VM 已销毁"
}

# ============================================================================
# VM 快照管理
# ============================================================================

# 创建快照
# 用法：vm_snapshot_create <snapshot-name>
vm_snapshot_create() {
    local snapshot_name="$1"

    if [ -z "$VM_DISK_IMAGE" ]; then
        echo "ERROR: VM 磁盘镜像未设置" >&2
        return 1
    fi

    # 使用 qcow2 的 snapshot 功能
    if qemu-img snapshot -c "$snapshot_name" "$VM_DISK_IMAGE" 2>/dev/null; then
        echo "快照 '$snapshot_name' 创建成功"
        return 0
    else
        # 回退到文件复制方案
        local snapshot_dir
        snapshot_dir="$(dirname "$VM_DISK_IMAGE")/snapshots"
        mkdir -p "$snapshot_dir"

        local snapshot_file="$snapshot_dir/$snapshot_name.img"
        if cp --reflink=auto "$VM_DISK_IMAGE" "$snapshot_file" 2>/dev/null || \
           cp "$VM_DISK_IMAGE" "$snapshot_file"; then
            echo "快照 '$snapshot_name' 创建成功 (文件备份)"
            return 0
        fi

        echo "ERROR: 快照创建失败" >&2
        return 1
    fi
}

# 恢复快照
# 用法：vm_snapshot_restore <snapshot-name>
vm_snapshot_restore() {
    local snapshot_name="$1"
    local snapshot_file
    snapshot_file="$(dirname "$VM_DISK_IMAGE")/snapshots/$snapshot_name.img"

    # 优先使用 qcow2 snapshot
    if qemu-img snapshot -a "$snapshot_name" "$VM_DISK_IMAGE" 2>/dev/null; then
        echo "快照 '$snapshot_name' 已恢复"
        return 0
    fi

    # 回退到文件恢复
    if [ -f "$snapshot_file" ]; then
        echo "正在从文件恢复快照..."
        cp --reflink=auto "$snapshot_file" "$VM_DISK_IMAGE" 2>/dev/null || \
        cp "$snapshot_file" "$VM_DISK_IMAGE"
        echo "快照 '$snapshot_name' 已恢复"
        return 0
    fi

    echo "ERROR: 快照 '$snapshot_name' 不存在" >&2
    return 1
}

# 列出快照
vm_snapshot_list() {
    if [ -z "$VM_DISK_IMAGE" ]; then
        echo "ERROR: VM 磁盘镜像未设置" >&2
        return 1
    fi

    echo "=== QEMU 快照 ==="
    qemu-img snapshot -l "$VM_DISK_IMAGE" 2>/dev/null || echo "(无)"

    echo ""
    echo "=== 文件备份快照 ==="
    local snapshot_dir
    snapshot_dir="$(dirname "$VM_DISK_IMAGE")/snapshots"
    if [ -d "$snapshot_dir" ]; then
        ls -1 "$snapshot_dir"/*.img 2>/dev/null | while read -r f; do
            basename "$f" .img
        done
    else
        echo "(无)"
    fi
}

# ============================================================================
# VM 命令执行
# ============================================================================

# 在 VM 内执行命令（通过 SSH）
# 用法：vm_exec <command>
vm_exec() {
    local command="$1"

    if [ -z "$command" ]; then
        echo "ERROR: 请指定要执行的命令" >&2
        return 1
    fi

    # 通过 SSH 执行（需要配置 SSH key）
    ssh -p "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "${VM_SSH_KEY:-~/.ssh/id_rsa}" \
        root@localhost "$command" 2>/dev/null
}

# 在 VM 内执行脚本文件
# 用法：vm_exec_file <local-script-path>
vm_exec_file() {
    local script="$1"

    if [ -z "$script" ] || [ ! -f "$script" ]; then
        echo "ERROR: 请指定有效的脚本文件" >&2
        return 1
    fi

    # 先上传脚本
    local remote_script="/tmp/$(basename "$script")"
    vm_upload "$script" "$remote_script" || return 1

    # 执行脚本
    vm_exec "bash $remote_script"
}

# ============================================================================
# VM 文件传输
# ============================================================================

# 上传文件到 VM
# 用法：vm_upload <local-path> <remote-path>
vm_upload() {
    local local_path="$1"
    local remote_path="$2"

    if [ -z "$local_path" ] || [ -z "$remote_path" ]; then
        echo "ERROR: 请指定本地和远程路径" >&2
        return 1
    fi

    scp -P "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "${VM_SSH_KEY:-~/.ssh/id_rsa}" \
        "$local_path" root@localhost:"$remote_path" 2>/dev/null
}

# 从 VM 下载文件
# 用法：vm_download <remote-path> <local-path>
vm_download() {
    local remote_path="$1"
    local local_path="$2"

    if [ -z "$remote_path" ] || [ -z "$local_path" ]; then
        echo "ERROR: 请指定远程和本地路径" >&2
        return 1
    fi

    scp -P "$VM_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i "${VM_SSH_KEY:-~/.ssh/id_rsa}" \
        root@localhost:"$remote_path" "$local_path" 2>/dev/null
}

# ============================================================================
# 串行控制台通信（备选方案）
# ============================================================================

# 通过串行控制台发送命令
# 用法：vm_serial_send <text>
vm_serial_send() {
    local text="$1"

    if [ -S "$VM_SERIAL_SOCKET" ]; then
        echo "$text" | socat - "unix-connect:$VM_SERIAL_SOCKET"
    else
        echo "ERROR: 串行控制台未连接" >&2
        return 1
    fi
}

# 通过串行控制台读取输出
# 用法：vm_serial_read [timeout-seconds]
vm_serial_read() {
    local timeout="${1:-5}"

    if [ -S "$VM_SERIAL_SOCKET" ]; then
        timeout "$timeout" socat -u "unix-connect:$VM_SERIAL_SOCKET" - 2>/dev/null
    else
        echo "ERROR: 串行控制台未连接" >&2
        return 1
    fi
}

# ============================================================================
# 辅助函数
# ============================================================================

# 等待 VM 启动完成
# 用法：vm_wait_for_boot [timeout-seconds]
vm_wait_for_boot() {
    local timeout="${1:-60}"
    local elapsed=0

    echo "等待 VM 启动..."
    while [ $elapsed -lt $timeout ]; do
        if ssh -p "$VM_SSH_PORT" -o ConnectTimeout=2 \
            -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -i "${VM_SSH_KEY:-~/.ssh/id_rsa}" \
            root@localhost "echo ready" 2>/dev/null | grep -q "ready"; then
            echo "VM 已就绪"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo "ERROR: VM 启动超时（${timeout}秒）" >&2
    return 1
}
