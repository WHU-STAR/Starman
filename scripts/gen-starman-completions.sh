#!/usr/bin/env bash
#
# 用法：从源码生成 assets/completions/ 下的 bash / zsh / fish / elvish / PowerShell 补全脚本。
# 依赖：cargo、Rust 工具链（见 rust-toolchain.toml）
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
exec cargo run -p starman --example generate_completions --locked
