# starman CLI

Rust 实现的 Starman 运维入口：子命令、`completion`、TUI、`doctor`、`create-user`。

## `create-user`（需 root）

创建 UNIX 用户、加入协作组（默认 `lab`，可配置）、向 `~/.bashrc` 与 `~/.zshrc` 写入 Starman 标记块（`HOMEBREW_PREFIX=~/.linuxbrew` 等）、可选执行 `brew bundle`（需该用户已安装 `~/.linuxbrew/bin/brew` 且存在 Brewfile 模板）、**家目录所在文件系统上的用户块配额**（默认 **200G**，`setquota`；需挂载选项 `usrquota` 等，否则命令会提示警告但用户已创建）。

```bash
sudo starman create-user alice -g lab
sudo starman create-user bob --shell /bin/zsh --no-brew
sudo starman create-user carol --home-quota 100G
sudo starman create-user dave --no-quota
```

系统配置 `/etc/starman/config.toml` 可选键：

| 键 | 说明 |
|----|------|
| `default_user_group` | 未传 `-g` 时使用的组名 |
| `default_shell` | 登录 shell，默认 `/bin/bash` |
| `brewfile_template_path` | Brewfile 模板，默认 `/home/linuxbrew/Brewfile.starman` |
| `default_home_quota` | 默认家目录配额，如 `200G`；可用 `--no-quota` 关闭 |

元数据写入 `/etc/starman/users.yaml`。

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

### 宿主机无 cargo：用 Docker 官方镜像构建

仓库提供脚本，在容器内安装 `musl-tools`、添加 musl target 并执行 `cargo build`（镜像版本应与 `rust-toolchain.toml` 一致，当前为 **1.88**）：

```bash
bash scripts/docker-build-starman.sh
# 可选：RUST_DOCKER_IMAGE=rust:1.88-bookworm（默认即此）
```

说明：

- 官方 `rust:*-bookworm` 镜像内 **`cargo`/`rustup` 在 `/usr/local/cargo/bin`**，脚本已设置 `PATH`；若自行 `docker run ... bash -c`，需先 `export PATH="/usr/local/cargo/bin:$PATH"`，否则会出现 `rustup: command not found`。
- 若曾使用 `rust:1.85-bookworm`，与当前工具链 **1.88** 不一致；请改用 **`rust:1.88-bookworm`**（或与 `rust-toolchain.toml` 同步的版本）。

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

输出到仓库 `assets/completions/`：

| 文件 | Shell |
|------|--------|
| `starman.bash` | Bash |
| `starman.zsh` | Zsh |
| `starman.fish` | Fish |
| `starman.elv` | Elvish |
| `_starman.ps1` | PowerShell |

运行时生成（与上表等价，且支持子命令别名 `completions`）：

```bash
starman completion bash
starman completion zsh
starman completion powershell
```

## 在测试机中验证（tmux + libvirt）

详见仓库根目录下 **`docs/VM_TEST_FLOW.md`**（若本地未忽略 `docs/` 可打开）。推荐流程概要：

1. `bash scripts/vm/backup-vm.sh ubuntu22-test`（或目标 VM）。  
2. 将 `target/release/starman` 拷入客体 `PATH` 或 `/usr/sbin/starman`（需客体 sudo）。  
3. 加载 bash 补全：`source <(starman completion bash)` 或安装 `assets/completions/starman.bash`。  
4. 在客体 **真实 TTY** 或 `tmux` 窗格中运行 `starman` / `starman tui`；无 TTY 时默认 TUI 会失败，请使用 `starman version` 等子命令。  
5. 结束后 `bash scripts/vm/restore-vm.sh ubuntu22-test`。

自动化冒烟示例：

- `tests/vm-test/scenarios/starman-cli-smoke.sh`（宿主机需 `cargo` 与 `tmux`）。
- `tests/vm-test/scenarios/starman-completion-smoke.sh` — 客体已安装 `starman` 后，在 tmux（默认 `vm-ubuntu:virsh`）验证各 shell 的 `starman completion …` 与别名 `completions`。
- `tests/vm-test/scenarios/starman-create-user-smoke.sh` — 客体上 **sudo** 执行 `create-user`（`--no-brew`），校验家目录 shell 标记块与 `lab` 组（需已部署含 `create-user` 的二进制）。

## CI 构建矩阵

GitHub Actions：`.github/workflows/rust.yml` — 本机 `x86_64` 测试 + `aarch64-unknown-linux-gnu` 交叉 `cargo build`（需 `gcc-aarch64-linux-gnu`）。
