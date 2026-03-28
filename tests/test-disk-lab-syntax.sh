#!/bin/bash
# 用法：bash tests/test-disk-lab-syntax.sh
# 校验 install-script-disk-lab 步骤脚本语法。
# 三台 VM（tmux）交互式冒烟：bash tests/vm-test/scripts/vm-disk-lab-smoke.sh（curl -o 再 bash，禁止管道）
# 带第二块盘做真实格式化时仍需在控制台人工操作验证。

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/scripts/steps/disk_lab.sh"
bash -n "$ROOT/install.sh"
echo "OK: disk_lab.sh + install.sh 语法检查通过"
