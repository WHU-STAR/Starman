//! Shared CLI definition: used by the binary, tests, and `examples/generate_completions`.

use anyhow::Result;
use clap::{CommandFactory, Parser, Subcommand, ValueEnum};
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
    /// Print shell completion script to stdout
    Completion {
        #[arg(value_enum)]
        shell: CompShell,
    },
    /// Check paths, config, and basic environment
    Doctor,
}

#[derive(Copy, Clone, Debug, ValueEnum, Eq, PartialEq)]
pub enum CompShell {
    Bash,
    Zsh,
    Fish,
    Elvish,
}

impl From<CompShell> for Shell {
    fn from(s: CompShell) -> Shell {
        match s {
            CompShell::Bash => Shell::Bash,
            CompShell::Zsh => Shell::Zsh,
            CompShell::Fish => Shell::Fish,
            CompShell::Elvish => Shell::Elvish,
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

    #[test]
    fn command_factory_matches_parser() {
        let _ = Cli::command();
        let _ = command_for_completions();
    }
}
