#!/bin/bash
#
# VM TUI Test Setup - 一键设置测试环境
#
# 用法：tests/vm-test/setup.sh
#

set -e

echo "╔════════════════════════════════════════╗"
echo "║     VM TUI 测试环境设置                  ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ============================================================================
# 依赖检查
# ============================================================================

echo "=== 检查依赖 ==="

check_dependency() {
    local name="$1"
    local command="$2"

    if command -v "$command" &>/dev/null; then
        echo "  ✓ $name ($command)"
        return 0
    else
        echo "  ✗ $name ($command) - 未安装"
        return 1
    fi
}

DEPS_OK=true

check_dependency "QEMU" "qemu-system-x86_64" || DEPS_OK=false
check_dependency "tmux" "tmux" || DEPS_OK=false
check_dependency "socat" "socat" || DEPS_OK=false

if command -v notify-send &>/dev/null; then
    echo "  ✓ 桌面通知 (notify-send)"
else
    echo "  ! 桌面通知 (notify-send) - 未安装，人工介入将使用终端提示"
fi

echo ""

if [ "$DEPS_OK" = false ]; then
    echo "ERROR: 缺少必要的依赖"
    echo ""
    echo "安装依赖："
    echo "  Ubuntu/Debian: sudo apt-get install qemu-kvm tmux socat libnotify-bin"
    echo "  CentOS/RHEL:   sudo yum install qemu-kvm tmux socat libnotify"
    echo "  Arch Linux:    sudo pacman -S qemu-full tmux socat libnotify"
    exit 1
fi

# ============================================================================
# KVM 模块检查
# ============================================================================

echo "=== 检查 KVM 模块 ==="

if lsmod | grep -q kvm_intel; then
    echo "  ✓ KVM Intel 模块已加载"
elif lsmod | grep -q kvm_amd; then
    echo "  ✓ KVM AMD 模块已加载"
else
    if lsmod | grep -q kvm; then
        echo "  ✓ KVM 模块已加载"
    else
        echo "  ✗ KVM 模块未加载"
        echo ""
        echo "加载 KVM 模块："
        echo "  Intel CPU: sudo modprobe kvm_intel"
        echo "  AMD CPU:   sudo modprobe kvm_amd"
    fi
fi

echo ""

# ============================================================================
# 目录结构检查
# ============================================================================

echo "=== 检查目录结构 ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."

check_directory() {
    local name="$1"
    local path="$2"

    if [ -d "$path" ]; then
        echo "  ✓ $name"
        return 0
    else
        echo "  ✗ $name - 创建中..."
        mkdir -p "$path"
        echo "      已创建：$path"
    fi
}

check_directory "测试目录" "$SCRIPT_DIR"
check_directory "脚本目录" "$SCRIPT_DIR/scripts"
check_directory "场景目录" "$SCRIPT_DIR/scenarios"
check_directory "快照目录" "$SCRIPT_DIR/snapshots"

echo ""

# ============================================================================
# 测试镜像检查
# ============================================================================

echo "=== 检查测试镜像 ==="

IMAGE_DIR="$SCRIPT_DIR/images"
IMAGE_FILE="$IMAGE_DIR/ubuntu-cloud.img"

mkdir -p "$IMAGE_DIR"

if [ -f "$IMAGE_FILE" ]; then
    echo "  ✓ 测试镜像已存在"
    echo "    路径：$IMAGE_FILE"
    echo "    大小：$(du -h "$IMAGE_FILE" | cut -f1)"
else
    echo "  ! 测试镜像不存在"
    echo ""
    echo "下载 cloud image（约 300MB）："
    echo "  mkdir -p $IMAGE_DIR"
    echo "  cd $IMAGE_DIR"
    echo "  wget -O ubuntu-cloud.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    echo "  或: curl -L https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -o ubuntu-cloud.img"
    echo ""
    read -rp "是否现在下载？[y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            echo "正在下载..."
            if command -v wget &>/dev/null; then
                wget -q --timeout=300 --tries=3 -O "$IMAGE_FILE" \
                    "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
            else
                curl -L "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img" -o "$IMAGE_FILE"
            fi
            echo "下载完成"
            ;;
        *)
            echo "稍后手动下载"
            ;;
    esac
fi

echo ""

# ============================================================================
# SSH Key 检查
# ============================================================================

echo "=== 检查 SSH Key ==="

SSH_KEY="$HOME/.ssh/id_rsa"

if [ -f "$SSH_KEY" ]; then
    echo "  ✓ SSH Key 已存在"
else
    echo "  ! SSH Key 不存在"
    echo ""
    read -rp "是否现在生成 SSH Key？[y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS])
            echo "正在生成 SSH Key..."
            ssh-keygen -t rsa -b 2048 -f "$SSH_KEY" -N ""
            echo "生成完成"
            ;;
        *)
            echo "稍后手动生成：ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''"
            ;;
    esac
fi

echo ""

# ============================================================================
# 完成
# ============================================================================

echo "╔════════════════════════════════════════╗"
echo "║         设置完成                        ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "下一步："
echo ""
echo "1. 如果尚未下载镜像，运行："
echo "   wget -O $IMAGE_FILE https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
echo ""
echo "2. 运行测试："
echo "   $SCRIPT_DIR/scripts/test-harness.sh run-all"
echo ""
echo "3. 运行单个测试："
echo "   $SCRIPT_DIR/scripts/test-harness.sh run-test root_user_guide"
echo ""
