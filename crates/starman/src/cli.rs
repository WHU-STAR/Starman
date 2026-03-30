//! Shared CLI definition: used by the binary, tests, and `examples/generate_completions`.

use anyhow::Result;
use clap::{Args, CommandFactory, Parser, Subcommand, ValueEnum};
use clap_complete::{generate, Shell};
use std::io;

const LONG_ABOUT: &str = "\
Starman 服务器运维 CLI。无子命令时：若标准输出为 TTY，则进入全屏 TUI；否则报错退出。\n\
\n\
环境：\n\
  - 日志：RUST_LOG 或 STARMAN_LOG（如未设置 STARMAN_LOG，则仅使用 RUST_LOG）。\n\
  - 颜色：NO_COLOR 或 --no-color 禁用 ANSI。\n\
  - 语言：LANG / LC_MESSAGES 或 STARMAN_LANG（zh|en）。\n\
";

/// Starman — server management CLI
#[derive(Parser, Debug)]
#[command(
    name = "starman",
    version,
    about = "Starman server management CLI",
    long_about = LONG_ABOUT,
    propagate_version = true
)]
pub struct Cli {
    /// Disable ANSI colors (also respects NO_COLOR)
    #[arg(long, global = true, action = clap::ArgAction::SetTrue)]
    pub no_color: bool,

    #[command(subcommand)]
    pub command: Option<Commands>,
}

#[derive(Subcommand, Debug, Clone)]
pub enum Commands {
    /// Interactive full-screen TUI (requires a TTY on stdout)
    Tui,
    /// Print version and exit
    Version,
    /// Print shell completion script to stdout (redirect or eval — see long help)
    #[command(
        visible_alias = "completions",
        long_about = "将补全脚本打印到标准输出。常见用法：\n\
            \n\
            • Bash：  source <(starman completion bash)\n\
              或写入文件： starman completion bash | sudo tee /etc/bash_completion.d/starman >/dev/null\n\
            • Zsh：   见 starman completion zsh 输出首行说明；或放入 fpath 片段\n\
            • Fish：  starman completion fish | source\n\
            • Elvish / PowerShell：见各自输出\n\
            \n\
            仓库内预生成文件：assets/completions/（bash / zsh / fish / elvish / PowerShell）。"
    )]
    Completion {
        /// Target shell
        #[arg(value_enum, value_name = "SHELL")]
        shell: CompShell,
    },
    /// Check paths, config, and basic environment
    Doctor,
    /// Create a UNIX user with shell snippets, optional group & Linuxbrew (requires root)
    CreateUser(CreateUserCli),
}

/// Arguments for `starman create-user` (see `openspec/changes/starman-create-user-environment/`).
#[derive(Debug, Clone, Args)]
pub struct CreateUserCli {
    /// 新登录名（小写字母、数字、_、-）
    pub username: String,

    /// 协作 UNIX 组（默认见配置 `default_user_group`，一般为 lab）
    #[arg(short = 'g', long)]
    pub group: Option<String>,

    /// 登录 shell（默认见配置 `default_shell`）
    #[arg(long)]
    pub shell: Option<String>,

    /// 不初始化 Linuxbrew（跳过 `brew bundle`）
    #[arg(long, action = clap::ArgAction::SetTrue)]
    pub no_brew: bool,

    /// 家目录所在文件系统上的用户磁盘配额（软/硬相同，块配额）；如 `200G`、`500M`。默认 200G，见配置 `default_home_quota`
    #[arg(long = "home-quota", value_name = "SIZE")]
    pub home_quota: Option<String>,

    /// 不设置磁盘配额（忽略默认 200G）
    #[arg(long, action = clap::ArgAction::SetTrue)]
    pub no_quota: bool,
}

#[derive(Copy, Clone, Debug, ValueEnum, Eq, PartialEq)]
pub enum CompShell {
    Bash,
    Zsh,
    Fish,
    Elvish,
    PowerShell,
}

impl From<CompShell> for Shell {
    fn from(s: CompShell) -> Shell {
        match s {
            CompShell::Bash => Shell::Bash,
            CompShell::Zsh => Shell::Zsh,
            CompShell::Fish => Shell::Fish,
            CompShell::Elvish => Shell::Elvish,
            CompShell::PowerShell => Shell::PowerShell,
        }
    }
}

/// Single line for `version` subcommand / messages.
pub fn version_line() -> String {
    format!(
        "{} {} ({})",
        env!("CARGO_PKG_NAME"),
        env!("CARGO_PKG_VERSION"),
        std::option_env!("CARGO_PKG_REPOSITORY").unwrap_or("starman")
    )
}

/// Shared `clap::Command` for completions and tooling (must stay in sync with [`Cli`]).
pub fn command_for_completions() -> clap::Command {
    Cli::command()
}

pub fn print_completion(shell: CompShell) -> Result<()> {
    let mut cmd = command_for_completions();
    let bin = "starman";
    let sh: Shell = shell.into();
    generate(sh, &mut cmd, bin, &mut io::stdout());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap_complete::generate;

    #[test]
    fn command_factory_matches_parser() {
        let _ = Cli::command();
        let _ = command_for_completions();
    }

    /// 各 Shell 的补全脚本应非空且包含命令名（与 `starman completion <shell>` 一致）。
    #[test]
    fn parse_create_user() {
        let c = Cli::try_parse_from([
            "starman",
            "create-user",
            "alice",
            "-g",
            "lab",
            "--no-brew",
        ])
        .unwrap();
        match c.command {
            Some(Commands::CreateUser(a)) => {
                assert_eq!(a.username, "alice");
                assert_eq!(a.group.as_deref(), Some("lab"));
                assert!(a.no_brew);
            }
            _ => panic!("expected CreateUser"),
        }
    }

    /// 各 Shell 的补全脚本应非空且包含命令名（与 `starman completion <shell>` 一致）。
    #[test]
    fn generated_completion_scripts_contain_bin_name() {
        use clap_complete::Shell as GenShell;
        let shells = [
            GenShell::Bash,
            GenShell::Zsh,
            GenShell::Fish,
            GenShell::Elvish,
            GenShell::PowerShell,
        ];
        for sh in shells {
            let mut cmd = command_for_completions();
            let mut buf = Vec::new();
            generate(sh, &mut cmd, "starman", &mut buf);
            assert!(
                buf.len() > 80,
                "completion for {sh:?} unexpectedly short ({} bytes)",
                buf.len()
            );
            let text = String::from_utf8_lossy(&buf);
            assert!(
                text.contains("starman"),
                "completion for {sh:?} missing bin name"
            );
        }
    }
}
