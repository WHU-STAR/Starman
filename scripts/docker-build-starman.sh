#!/usr/bin/env bash
# Usage: 使用官方 Docker 镜像在容器内构建 starman（与仓库 rust-toolchain 一致）。
#   宿主机未装 Rust，或需避免 glibc 版本污染时，用本脚本生成 musl 静态二进制，便于在旧发行版（如 Ubuntu 22.04）客体上运行。
#
# 环境变量:
#   RUST_DOCKER_IMAGE  默认 rust:1.88-bookworm（须与 rust-toolchain.toml 大版本一致）
#   STARMAN_TARGET     默认 x86_64-unknown-linux-musl；可改为 x86_64-unknown-linux-gnu 等
#
# 示例:
#   bash scripts/docker-build-starman.sh
#   RUST_DOCKER_IMAGE=rust:1.88-bookworm bash scripts/docker-build-starman.sh
#
# 产物: target/<STARMAN_TARGET>/release/starman

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUST_DOCKER_IMAGE="${RUST_DOCKER_IMAGE:-rust:1.88-bookworm}"
STARMAN_TARGET="${STARMAN_TARGET:-x86_64-unknown-linux-musl}"

docker run --rm \
  -e STARMAN_TARGET="$STARMAN_TARGET" \
  -v "$ROOT:/work" \
  -w /work \
  "$RUST_DOCKER_IMAGE" \
  bash -lc '
    set -euo pipefail
    export PATH="/usr/local/cargo/bin:${PATH:-}"
    if [[ "${STARMAN_TARGET}" == *-musl ]]; then
      apt-get update -qq
      apt-get install -y -qq musl-tools
      rustup target add "${STARMAN_TARGET}"
    fi
    cargo build --release -p starman --locked --target "${STARMAN_TARGET}"
  '

echo "OK: ${ROOT}/target/${STARMAN_TARGET}/release/starman"
