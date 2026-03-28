#!/bin/bash
# 在测试虚拟机内执行：勿使用 curl|bash 管道；由宿主机 tmux 下发
#   curl -fsSL … -o /tmp/guest-disk-lab-smoke.sh && chmod +x … && bash /tmp/guest-disk-lab-smoke.sh
# 以保证 bash 挂在交互式终端上（见 starman-vm-tmux-test）。
#
# 拉取仓库快照（curl -o + tar）、语法检查、在 TTY 下跑 run_step_disk_lab（默认「跳过」需一次 Enter，由宿主机发键），
# 再验证 STARMAN_SKIP_DISK_LAB 路径；最后打印唯一结束标记。
set -uo pipefail

HOST="${STARMAN_SMOKE_HTTP_HOST:-192.168.122.1}"
PORT="${STARMAN_SMOKE_HTTP_PORT:-8765}"
SNAP="${STARMAN_SMOKE_SNAP:-starman-snapshot.tgz}"

ensure_tar() {
    command -v tar >/dev/null 2>&1 && return 0
    if [ "$(id -u)" -eq 0 ]; then
        dnf install -y tar 2>/dev/null && return 0
        yum install -y tar 2>/dev/null && return 0
        apt-get update -qq && apt-get install -y tar && return 0
        zypper install -y tar 2>/dev/null && return 0
        pacman -Sy --noconfirm tar 2>/dev/null && return 0
    else
        echo ubuntu123 | sudo -S env DEBIAN_FRONTEND=noninteractive apt-get install -y tar 2>/dev/null && return 0
        echo fedora123 | sudo -S dnf install -y tar 2>/dev/null && return 0
        echo ubuntu123 | sudo -S yum install -y tar 2>/dev/null && return 0
    fi
    echo "guest-disk-lab-smoke: 无法安装 tar" >&2
    return 127
}

ensure_tar || exit 127

cd /tmp
rm -rf starman-disk-lab-smoke
mkdir -p starman-disk-lab-smoke
cd starman-disk-lab-smoke

local_tgz="/tmp/starman-disk-lab-snapshot.tgz"
curl -fsSL "http://${HOST}:${PORT}/${SNAP}" -o "$local_tgz"
tar xzf "$local_tgz"

ROOT="$(pwd)"
bash -n "${ROOT}/scripts/steps/disk_lab.sh" || exit 2
bash -n "${ROOT}/install.sh" || exit 2

# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/tui.sh"
# shellcheck source=/dev/null
source "${ROOT}/scripts/steps/disk_lab.sh"

set +e
# 交互式终端：应出现「数据盘与 lab 共享」TUI，默认「跳过」——由宿主机 tmux send-keys Enter 确认
run_step_disk_lab
ec1=$?

export STARMAN_SKIP_DISK_LAB=1
run_step_disk_lab
ec2=$?
set -e

SID="${STARMAN_SMOKE_ID:-0}"
if [ "$ec1" -ne 0 ] || [ "$ec2" -ne 0 ]; then
    echo "STARMAN_DISK_LAB_VM_FAIL_${SID} ec1=${ec1} ec2=${ec2}"
    exit 1
fi

echo "STARMAN_DISK_LAB_VM_DONE_${SID}"
