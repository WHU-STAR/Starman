#!/bin/bash
# 在测试虚拟机内执行（宿主机通过 tmux 下发；落地脚本后 bash，勿管道）；勿在宿主机直接运行。
# 从 HTTP 拉取仓库快照并执行 install.sh，最后打印唯一结束标记。
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
    echo "guest-smoke: 无法安装 tar，请先装好 tar 再运行" >&2
    return 127
}

ensure_tar || exit 127

cd /tmp
rm -rf starman-smoke
mkdir -p starman-smoke
cd starman-smoke

curl -fsSL "http://${HOST}:${PORT}/${SNAP}" | tar xzf -

run_install() {
    # sudo -S 会占用 stdin，导致 install.sh 无 TTY；用 script(1) 分配伪终端以满足 require_interactive_terminal
    local _run='bash install.sh'
    if [ "$(id -u)" -eq 0 ]; then
        bash install.sh
        return $?
    fi
    case "$(whoami)" in
        ubuntu)
            echo ubuntu123 | sudo -S env DEBIAN_FRONTEND=noninteractive script -q -c "$_run" /dev/null
            ;;
        fedora)
            echo fedora123 | sudo -S script -q -c "$_run" /dev/null
            ;;
        *)
            echo "guest-smoke: 未知用户 $(whoami)，尝试 sudo -S + script" >&2
            sudo -S script -q -c "$_run" /dev/null
            ;;
    esac
}

set +e
run_install
ec=$?
set -e

SID="${STARMAN_SMOKE_ID:-0}"
echo "STARMAN_GUEST_SMOKE_DONE_${SID} exit=${ec}"
