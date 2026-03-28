# starman CLI

Rust 实现的 Starman 运维入口：子命令、`completion`、TUI、`doctor`。

## 构建

需要 **Rust ≥ 1.88**（见仓库根 `rust-toolchain.toml`；`ratatui` 等依赖的 MSRV）。

```bash
cargo build --release -p starman --locked
```

在 **Ubuntu 22.04 / 较旧 glibc** 环境（如 `ubuntu22-test` 虚拟机）上，若在 **glibc 较新的宿主机**（如 `rust:latest` 镜像）里直接 `cargo build --release`，链接出的动态二进制可能要求 **GLIBC_2.39+**，客体无法运行。可选：

```bash
# 在 rust:1.88-bookworm 等环境中：先 cargo clean，再构建 musl 静态产物（与发行版 glibc 无关）
rustup target add x86_64-unknown-linux-musl
# 需 musl-tools（musl-gcc）
cargo build --release -p starman --locked --target x86_64-unknown-linux-musl
# 产物：target/x86_64-unknown-linux-musl/release/starman
```

## 环境变量

| 变量 | 说明 |
|------|------|
| `RUST_LOG` | `tracing` 日志级别（如 `info`、`starman=debug`）。 |
| `STARMAN_LOG` | 若设置，会覆盖写入 `RUST_LOG`，便于只调 Starman 相关过滤。 |
| `NO_COLOR` | 非空时禁用 ANSI 颜色；CLI 的 `--no-color` 也会设置 `NO_COLOR=1`。 |
| `STARMAN_LANG` | `zh` / `en` 等，影响部分文案（与 `LANG`/`LC_MESSAGES` 一起参与判定）。 |

## Release 资产命名（与安装脚本约定）

GitHub / Gitee Release 上建议发布：

- **tarball**：`starman-<arch>-unknown-linux-gnu.tar.gz`  
  - 内含可执行文件 `starman`（可选附带 `assets/completions/*`）。  
- **校验**：同目录 `starman-<arch>-unknown-linux-gnu.tar.gz.sha256`（或单文件 `starman.sha256`）。

`<arch>` 与 `uname -m` 对应关系：

| uname -m | `<arch>` |
|----------|----------|
| x86_64 | x86_64 |
| aarch64 / arm64 | aarch64 |

安装目标路径：`/usr/sbin/starman`；配置目录：`/etc/starman/`（可选 `config.toml`），用户覆盖：`$XDG_CONFIG_HOME/starman/config.toml`（通常为 `~/.config/starman/config.toml`）。

## 生成 shell 补全（静态文件）

```bash
cargo run -p starman --example generate_completions --locked
# 或
bash scripts/gen-starman-completions.sh
```

输出到仓库 `assets/completions/`（`starman.bash`、`starman.zsh`、`starman.fish`）。

运行时生成：

```bash
starman completion bash
starman completion zsh
```

## 在测试机中验证（tmux + libvirt）

详见仓库根目录下 **`docs/VM_TEST_FLOW.md`**（若本地未忽略 `docs/` 可打开）。推荐流程概要：

1. `bash scripts/vm/backup-vm.sh ubuntu22-test`（或目标 VM）。  
2. 将 `target/release/starman` 拷入客体 `PATH` 或 `/usr/sbin/starman`（需客体 sudo）。  
3. 加载 bash 补全：`source <(starman completion bash)` 或安装 `assets/completions/starman.bash`。  
4. 在客体 **真实 TTY** 或 `tmux` 窗格中运行 `starman` / `starman tui`；无 TTY 时默认 TUI 会失败，请使用 `starman version` 等子命令。  
5. 结束后 `bash scripts/vm/restore-vm.sh ubuntu22-test`。

自动化冒烟示例：`tests/vm-test/scenarios/starman-cli-smoke.sh`（宿主机需 `cargo` 与 `tmux`）。

## CI 构建矩阵

GitHub Actions：`.github/workflows/rust.yml` — 本机 `x86_64` 测试 + `aarch64-unknown-linux-gnu` 交叉 `cargo build`（需 `gcc-aarch64-linux-gnu`）。
