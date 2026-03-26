#!/bin/bash
#
# Curl Installer Tests - 测试安装脚本的功能
#
# This script tests the installer logic without actually downloading
# or installing anything.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$SCRIPT_DIR/installers/install.sh"
BOOTSTRAP="$SCRIPT_DIR/installers/bootstrap.sh"

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
echo "  Curl Installer 测试"
echo "========================================"
echo ""

# Test 1: Check installer files exist
echo "=== 文件存在性测试 ==="
if [ -f "$BOOTSTRAP" ]; then
    test_result "bootstrap.sh 存在" "true" "true"
else
    test_result "bootstrap.sh 存在" "true" "false"
fi

if [ -f "$INSTALLER" ]; then
    test_result "install.sh 存在" "true" "true"
else
    test_result "install.sh 存在" "true" "false"
fi
echo ""

# Test 2: Check file permissions
echo "=== 文件权限测试 ==="
if [ -x "$BOOTSTRAP" ]; then
    test_result "bootstrap.sh 可执行" "true" "true"
else
    test_result "bootstrap.sh 可执行" "true" "false"
fi

if [ -x "$INSTALLER" ]; then
    test_result "install.sh 可执行" "true" "true"
else
    test_result "install.sh 可执行" "true" "false"
fi
echo ""

# Test 3: Check script syntax
echo "=== 语法检查 ==="
if bash -n "$BOOTSTRAP" 2>/dev/null; then
    test_result "bootstrap.sh 语法正确" "true" "true"
else
    test_result "bootstrap.sh 语法正确" "true" "false"
fi

if bash -n "$INSTALLER" 2>/dev/null; then
    test_result "install.sh 语法正确" "true" "true"
else
    test_result "install.sh 语法正确" "true" "false"
fi
echo ""

# Test 4: Check URLs are defined
echo "=== URL 定义测试 ==="
if grep -q "GITHUB_RELEASE=" "$INSTALLER" 2>/dev/null; then
    test_result "GitHub Release URL 定义" "true" "true"
else
    test_result "GitHub Release URL 定义" "true" "false"
fi

if grep -q "GITEE_RELEASE=" "$INSTALLER" 2>/dev/null; then
    test_result "Gitee Release URL 定义" "true" "true"
else
    test_result "Gitee Release URL 定义" "true" "false"
fi

if grep -q "GITHUB_BASE=" "$BOOTSTRAP" 2>/dev/null; then
    test_result "bootstrap GitHub URL 定义" "true" "true"
else
    test_result "bootstrap GitHub URL 定义" "true" "false"
fi

if grep -q "GITEE_BASE=" "$BOOTSTRAP" 2>/dev/null; then
    test_result "bootstrap Gitee URL 定义" "true" "true"
else
    test_result "bootstrap Gitee URL 定义" "true" "false"
fi
echo ""

# Test 5: Check required functions exist
echo "=== 函数存在性测试 ==="
for func in detect_arch detect_user detect_sudo detect_network download_binary install_binary; do
    if grep -q "^$func()" "$INSTALLER" 2>/dev/null; then
        test_result "函数 $func 存在" "true" "true"
    else
        test_result "函数 $func 存在" "true" "false"
    fi
done

for func in detect_downloader download_file download_and_run; do
    if grep -q "^$func()" "$BOOTSTRAP" 2>/dev/null; then
        test_result "bootstrap 函数 $func 存在" "true" "true"
    else
        test_result "bootstrap 函数 $func 存在" "true" "false"
    fi
done
echo ""

# Test 6: Check installation paths
echo "=== 安装路径测试 ==="
if grep -q 'INSTALL_DIR="/usr/sbin"' "$INSTALLER" 2>/dev/null; then
    test_result "INSTALL_DIR 正确" "true" "true"
else
    test_result "INSTALL_DIR 正确" "true" "false"
fi

if grep -q 'CONFIG_DIR="/etc/starman"' "$INSTALLER" 2>/dev/null; then
    test_result "CONFIG_DIR 正确" "true" "true"
else
    test_result "CONFIG_DIR 正确" "true" "false"
fi
echo ""

# Summary
echo "========================================"
echo "  测试结果：$PASS PASS, $FAIL FAIL"
echo "========================================"

if [ $FAIL -gt 0 ]; then
    exit 1
fi

# ============================================================================
# VM TUI Tests (可选)
# ============================================================================

echo ""
echo "========================================"
echo "  VM TUI 测试（可选）"
echo "========================================"
echo ""

VM_TEST_HARNESS="$SCRIPT_DIR/tests/vm-test/scripts/test-harness.sh"

if [ -f "$VM_TEST_HARNESS" ]; then
    echo "VM TUI 测试框架已安装"
    echo ""
    echo "运行 VM TUI 测试："
    echo "  $VM_TEST_HARNESS run-all"
    echo ""
    echo "运行单个测试："
    echo "  $VM_TEST_HARNESS run-test <test-name>"
else
    echo "VM TUI 测试框架未安装，跳过"
fi

exit 0
