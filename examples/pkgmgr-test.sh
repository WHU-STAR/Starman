#!/bin/bash
#
# Package Manager Tests - 测试 pkgmgr 库的功能
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/pkgmgr.sh"

PASS=0
FAIL=0

test_result() {
    local name="$1"
    local expected="$2"
    local actual="$3"

    if [ "$expected" = "$actual" ]; then
        echo "✓ PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "✗ FAIL: $name (expected: $expected, actual: $actual)"
        FAIL=$((FAIL + 1))
    fi
}

echo "========================================"
echo "  Package Manager 测试"
echo "========================================"
echo ""

# 检测包管理器
echo "=== 包管理器检测 ==="
if pkgmgr_detect; then
    echo "✓ PASS: pkgmgr_detect 成功"
    echo "PKGMGR = $PKGMGR"
    PASS=$((PASS + 1))
else
    echo "✗ FAIL: pkgmgr_detect 失败"
    FAIL=$((FAIL + 1))
fi
echo ""

# 测试包名映射
echo "=== 包名映射测试 ==="
PKGMGR="apt"
test_result "fd (apt)" "fd-find" "$(pkgmgr_map_name fd)"
test_result "ripgrep (apt)" "ripgrep" "$(pkgmgr_map_name ripgrep)"

PKGMGR="dnf"
test_result "fd (dnf)" "fd" "$(pkgmgr_map_name fd)"
test_result "ripgrep (dnf)" "ripgrep" "$(pkgmgr_map_name ripgrep)"

PKGMGR="pacman"
test_result "fd (pacman)" "fd" "$(pkgmgr_map_name fd)"

PKGMGR="yum"
test_result "fd (yum)" "fd" "$(pkgmgr_map_name fd)"
echo ""

# 测试版本比较
echo "=== 版本比较测试 ==="
if pkgmgr_version_compare "1.2.3" "1.2.0"; then
    test_result "1.2.3 >= 1.2.0" "true" "true"
else
    test_result "1.2.3 >= 1.2.0" "true" "false"
fi

if pkgmgr_version_compare "1.2.0" "1.2.3"; then
    test_result "1.2.0 >= 1.2.3" "false" "true"
else
    test_result "1.2.0 >= 1.2.3" "false" "false"
fi

if pkgmgr_version_compare "2.0.0" "1.9.9"; then
    test_result "2.0.0 >= 1.9.9" "true" "true"
else
    test_result "2.0.0 >= 1.9.9" "true" "false"
fi

if pkgmgr_version_compare "1.2.3" "1.2.3"; then
    test_result "1.2.3 >= 1.2.3" "true" "true"
else
    test_result "1.2.3 >= 1.2.3" "true" "false"
fi
echo ""

# 测试 pkgmgr_is_installed（需要包管理器已初始化）
echo "=== 包安装状态测试 ==="
# Re-detect to get the actual package manager
pkgmgr_detect

if [ -n "$PKGMGR" ]; then
    # 测试一些常见的包
    if pkgmgr_is_installed bash; then
        echo "✓ bash 已安装"
        PASS=$((PASS + 1))
    else
        echo "✗ bash 未安装（异常）"
        FAIL=$((FAIL + 1))
    fi

    # 测试一个不太可能安装的包
    if pkgmgr_is_installed nonexistent-package-xyz-123; then
        echo "✗ nonexistent-package-xyz-123 已安装（异常）"
        FAIL=$((FAIL + 1))
    else
        echo "✓ nonexistent-package-xyz-123 未安装"
        PASS=$((PASS + 1))
    fi
else
    echo "跳过（包管理器未初始化）"
fi
echo ""

# 总结
echo "========================================"
echo "  测试结果：$PASS PASS, $FAIL FAIL"
echo "========================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi
exit 0
