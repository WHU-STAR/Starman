#!/bin/bash
#
# Package Manager Abstraction - 统一包管理器接口
#
# 用途：提供跨发行版的包管理器抽象层，支持 apt/yum/dnf/pacman/zypper
#
# 用法示例：
#
#   source scripts/lib/pkgmgr.sh
#
#   # 检测包管理器
#   pkgmgr_detect || exit 1
#   echo "检测到包管理器：$PKGMGR"
#
#   # 安装软件包
#   pkgmgr_install git curl
#
#   # 检查是否已安装
#   if pkgmgr_is_installed docker; then
#       echo "Docker 已安装"
#   fi
#
#   # 版本检查与 fallback
#   pkgmgr_ensure_min neovim "0.5.0" "curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz"
#
# 依赖：无（纯 Bash + 基础命令）
#

set -u

# ============================================================================
# 全局变量
# ============================================================================

# 包管理器类型（由 pkgmgr_detect 设置）
PKGMGR=""

# ============================================================================
# 包管理器检测
# ============================================================================

# 检测包管理器类型，设置 PKGMGR 变量
# 返回：0 成功，1 失败（未检测到支持的包管理器）
pkgmgr_detect() {
    if command -v apt-get &>/dev/null; then
        PKGMGR="apt"
    elif command -v dnf &>/dev/null; then
        PKGMGR="dnf"
    elif command -v yum &>/dev/null; then
        PKGMGR="yum"
    elif command -v pacman &>/dev/null; then
        PKGMGR="pacman"
    elif command -v zypper &>/dev/null; then
        PKGMGR="zypper"
    else
        echo "ERROR: 未检测到支持的包管理器 (apt/yum/dnf/pacman/zypper)" >&2
        return 1
    fi
    return 0
}

# ============================================================================
# 统一安装接口
# ============================================================================

# 安装软件包
# 用法：pkgmgr_install <package1> [package2] ...
pkgmgr_install() {
    if [ $# -eq 0 ]; then
        echo "ERROR: 请指定要安装的软件包" >&2
        return 1
    fi

    case "$PKGMGR" in
        apt)
            apt-get install -y "$@"
            ;;
        yum)
            yum install -y "$@"
            ;;
        dnf)
            dnf install -y "$@"
            ;;
        pacman)
            pacman -S --noconfirm "$@"
            ;;
        zypper)
            zypper install -y "$@"
            ;;
        *)
            echo "ERROR: 不支持的包管理器：$PKGMGR" >&2
            return 1
            ;;
    esac
}

# 更新包索引
# 用法：pkgmgr_update
pkgmgr_update() {
    case "$PKGMGR" in
        apt)
            apt-get update
            ;;
        yum)
            yum makecache
            ;;
        dnf)
            dnf makecache
            ;;
        pacman)
            pacman -Sy
            ;;
        zypper)
            zypper refresh
            ;;
        *)
            echo "ERROR: 不支持的包管理器：$PKGMGR" >&2
            return 1
            ;;
    esac
}

# 检查软件包是否已安装
# 用法：pkgmgr_is_installed <package>
# 返回：0 已安装，1 未安装
pkgmgr_is_installed() {
    local pkg="$1"
    if [ -z "$pkg" ]; then
        echo "ERROR: 请指定软件包名" >&2
        return 1
    fi

    case "$PKGMGR" in
        apt)
            dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
            return $?
            ;;
        yum|dnf)
            rpm -q "$pkg" &>/dev/null
            return $?
            ;;
        pacman)
            pacman -Q "$pkg" &>/dev/null
            return $?
            ;;
        zypper)
            rpm -q "$pkg" &>/dev/null
            return $?
            ;;
        *)
            echo "ERROR: 不支持的包管理器：$PKGMGR" >&2
            return 1
            ;;
    esac
}

# ============================================================================
# 包名映射
# ============================================================================

# 包名映射函数
# 用法：pkgmgr_map_name <canonical-name>
# 返回：映射后的包名
pkgmgr_map_name() {
    local pkg="$1"
    if [ -z "$pkg" ]; then
        echo "ERROR: 请指定包名" >&2
        return 1
    fi

    case "$PKGMGR:$pkg" in
        apt:fd)
            echo "fd-find"
            ;;
        apt:docker)
            echo "docker.io"
            ;;
        yum:docker|dnf:docker|zypper:docker)
            echo "docker"
            ;;
        yum:openssh-client|dnf:openssh-client)
            echo "openssh-clients"
            ;;
        *)
            echo "$pkg"
            ;;
    esac
}

# ============================================================================
# 版本检查与 Fallback
# ============================================================================

# 比较两个版本号（语义化版本）
# 用法：pkgmgr_version_compare <version1> <version2>
# 返回：0 if v1 >= v2, 1 otherwise
pkgmgr_version_compare() {
    local v1="$1"
    local v2="$2"

    if [ "$v1" = "$v2" ]; then
        return 0
    fi

    # 分割版本号
    local v1_major v1_minor v1_patch
    local v2_major v2_minor v2_patch

    IFS='.' read -r v1_major v1_minor v1_patch <<< "$v1"
    IFS='.' read -r v2_major v2_minor v2_patch <<< "$v2"

    # 默认值为 0
    v1_major=${v1_major:-0}
    v1_minor=${v1_minor:-0}
    v1_patch=${v1_patch:-0}
    v2_major=${v2_major:-0}
    v2_minor=${v2_minor:-0}
    v2_patch=${v2_patch:-0}

    # 比较主版本
    if [ "$v1_major" -gt "$v2_major" ]; then
        return 0
    elif [ "$v1_major" -lt "$v2_major" ]; then
        return 1
    fi

    # 比较次版本
    if [ "$v1_minor" -gt "$v2_minor" ]; then
        return 0
    elif [ "$v1_minor" -lt "$v2_minor" ]; then
        return 1
    fi

    # 比较补丁版本
    if [ "$v1_patch" -ge "$v2_patch" ]; then
        return 0
    else
        return 1
    fi
}

# 获取软件包版本
# 用法：pkgmgr_get_version <package>
# 返回：版本号字符串
pkgmgr_get_version() {
    local pkg="$1"

    case "$PKGMGR" in
        apt)
            dpkg -s "$pkg" 2>/dev/null | grep "^Version:" | awk '{print $2}'
            ;;
        yum|dnf)
            rpm -q "$pkg" --queryformat '%{VERSION}\n' 2>/dev/null
            ;;
        pacman)
            pacman -Q "$pkg" 2>/dev/null | awk '{print $2}'
            ;;
        zypper)
            rpm -q "$pkg" --queryformat '%{VERSION}\n' 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# 版本检查与 fallback
# 用法：pkgmgr_ensure_min <package> <min-version> <fallback-cmd>
pkgmgr_ensure_min() {
    local pkg="$1"
    local min_version="$2"
    local fallback_cmd="$3"

    if [ -z "$pkg" ] || [ -z "$min_version" ]; then
        echo "ERROR: 请指定包名和最低版本" >&2
        return 1
    fi

    # 尝试安装
    pkgmgr_install "$pkg" || return 1

    # 获取版本
    local installed_version
    installed_version=$(pkgmgr_get_version "$pkg")

    if [ -z "$installed_version" ]; then
        echo "WARNING: 无法获取 $pkg 的版本" >&2
        if [ -n "$fallback_cmd" ]; then
            echo "执行 fallback: $fallback_cmd" >&2
            eval "$fallback_cmd"
        fi
        return 1
    fi

    # 检查版本
    if pkgmgr_version_compare "$installed_version" "$min_version"; then
        echo "$pkg 版本 $installed_version >= $min_version" >&2
        return 0
    else
        echo "WARNING: $pkg 版本 $installed_version < $min_version" >&2
        if [ -n "$fallback_cmd" ]; then
            echo "执行 fallback: $fallback_cmd" >&2
            eval "$fallback_cmd"
        fi
        return 1
    fi
}

# neovim 专用 fallback（PPA → GitHub Release）
# 用法：pkgmgr_install_neovim <min-version>
pkgmgr_install_neovim() {
    local min_version="${1:-0.5.0}"

    case "$PKGMGR" in
        apt)
            # 尝试 PPA
            if command -v add-apt-repository &>/dev/null; then
                add-apt-repository -y ppa:neovim-ppa/stable 2>/dev/null || true
                apt-get update
            fi
            pkgmgr_install neovim

            # 检查版本，不足则 fallback
            local installed_version
            installed_version=$(pkgmgr_get_version neovim)

            if ! pkgmgr_version_compare "${installed_version:-0}" "$min_version"; then
                echo "执行 neovim GitHub Release fallback" >&2
                curl -LO "https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz"
                tar -xzf nvim-linux64.tar.gz
                mv nvim-linux64 /opt/nvim
                ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
            fi
            ;;
        *)
            # 其他发行版直接使用包管理器
            pkgmgr_install neovim
            ;;
    esac
}
