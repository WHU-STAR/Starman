#!/bin/bash
#
# Package Manager Demo - 演示 pkgmgr 库的使用
#
# 用法：./examples/pkgmgr-demo.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/pkgmgr.sh"

echo "========================================"
echo "  Package Manager Abstraction 演示"
echo "========================================"
echo ""

# 检测包管理器
echo "检测包管理器..."
if ! pkgmgr_detect; then
    echo "错误：无法检测包管理器"
    exit 1
fi
echo "检测到包管理器：$PKGMGR"
echo ""

# 演示包名映射
echo "=== 包名映射演示 ==="
echo "标准名 'fd' 在 $PKGMGR 下的实际包名：$(pkgmgr_map_name fd)"
echo "标准名 'ripgrep' 在 $PKGMGR 下的实际包名：$(pkgmgr_map_name ripgrep)"
echo ""

# 演示检查已安装包
echo "=== 检查已安装的软件包 ==="
if pkgmgr_is_installed curl; then
    echo "curl: 已安装"
else
    echo "curl: 未安装"
fi

if pkgmgr_is_installed git; then
    echo "git: 已安装"
else
    echo "git: 未安装"
fi
echo ""

# 演示版本号比较
echo "=== 版本号比较演示 ==="
if pkgmgr_version_compare "1.2.3" "1.2.0"; then
    echo "1.2.3 >= 1.2.0: 是"
else
    echo "1.2.3 >= 1.2.0: 否"
fi

if pkgmgr_version_compare "1.2.0" "1.2.3"; then
    echo "1.2.0 >= 1.2.3: 是"
else
    echo "1.2.0 >= 1.2.3: 否"
fi
echo ""

# 演示版本检查（以 curl 为例）
echo "=== 版本检查演示 ==="
curl_version=$(pkgmgr_get_version curl 2>/dev/null)
if [ -n "$curl_version" ]; then
    echo "当前 curl 版本：$curl_version"
    if pkgmgr_version_compare "$curl_version" "7.0.0"; then
        echo "curl 版本 >= 7.0.0: 满足"
    else
        echo "curl 版本 >= 7.0.0: 不满足"
    fi
else
    echo "curl 未安装，无法获取版本"
fi
echo ""

echo "========================================"
echo "演示完成"
echo "========================================"
