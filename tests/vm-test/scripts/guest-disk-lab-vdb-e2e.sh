#!/bin/bash
# 在 ubuntu22-test 客体中执行（宿主机 HTTP 提供仓库快照；勿 wget/curl|bash）。
# 对附加数据盘跑 run_step_disk_lab 全流程；破坏性：会格式化所选块设备。
#
# 环境变量：STARMAN_SMOKE_ID、STARMAN_SMOKE_HTTP_HOST、STARMAN_SMOKE_HTTP_PORT、STARMAN_SMOKE_SNAP
#
# 成功条件：/data 已挂载且存在 /data/share（lab）；打印 STARMAN_DISK_LAB_VDB_E2E_DONE_<id>
set -uo pipefail

HOST="${STARMAN_SMOKE_HTTP_HOST:-192.168.122.1}"
PORT="${STARMAN_SMOKE_HTTP_PORT:-8765}"
SNAP="${STARMAN_SMOKE_SNAP:-starman-snapshot.tgz}"
SID="${STARMAN_SMOKE_ID:-0}"

ensure_tar() {
    command -v tar >/dev/null 2>&1 && return 0
    echo ubuntu123 | sudo -S env DEBIAN_FRONTEND=noninteractive apt-get install -y tar 2>/dev/null && return 0
    return 127
}

ensure_tar || exit 127

cd /tmp
rm -rf starman-disk-lab-vdb-e2e
mkdir -p starman-disk-lab-vdb-e2e
cd starman-disk-lab-vdb-e2e

local_tgz="/tmp/starman-vdb-e2e-snap.tgz"
if command -v wget &>/dev/null; then
    wget -q --timeout=120 --tries=1 -O "$local_tgz" "http://${HOST}:${PORT}/${SNAP}"
else
    curl -fsSL "http://${HOST}:${PORT}/${SNAP}" -o "$local_tgz"
fi
tar xzf "$local_tgz"

ROOT="$(pwd)"
bash -n "${ROOT}/scripts/steps/disk_lab.sh" || exit 2

# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/common.sh"
# shellcheck source=/dev/null
source "${ROOT}/scripts/lib/tui.sh"
# shellcheck source=/dev/null
source "${ROOT}/scripts/steps/disk_lab.sh"

# 预验证 sudo（tmux 自动化时密码易与 shell 不同步）；后续 mkfs/mount 在同一会话内通常不再提示
PW="${STARMAN_UBUNTU_PASS:-ubuntu123}"
if [ "$(id -u)" -ne 0 ]; then
    echo "$PW" | sudo -S -v 2>/dev/null || {
        echo "STARMAN_DISK_LAB_VDB_E2E_FAIL_${SID} sudo"
        exit 3
    }
fi

# 可重复跑：卸载 /data 并去掉本脚本写入的 fstab 行，使 vdb 再次可选
if mountpoint -q /data 2>/dev/null; then
    echo "$PW" | sudo -S umount /data 2>/dev/null || true
fi
if [ -f /etc/fstab ]; then
    echo "$PW" | sudo -S sed -i '/Starman data disk/d' /etc/fstab 2>/dev/null || true
fi

run_step_disk_lab || exit 3

# 成功标志：lab 步骤已创建共享目录（mountpoint 在个别环境下与 findmnt -n 行为不一致，不单独依赖）
if [ -d /data/share ] && findmnt --target /data &>/dev/null; then
    lsblk -f /dev/vdb /data 2>/dev/null || true
    echo "STARMAN_DISK_LAB_VDB_E2E_DONE_${SID}"
    exit 0
fi

echo "STARMAN_DISK_LAB_VDB_E2E_FAIL_${SID}"
exit 1
