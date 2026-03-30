//! Starman CLI library (binary entry in `main.rs`).

pub mod cli;
pub mod config;
pub mod create_user;
pub mod doctor;
pub mod quota;
pub mod shell_snippet;
pub mod i18n;
pub mod logging;
pub mod tui;

pub use cli::Cli;

use anyhow::Result;
use clap::Parser;
use std::io::{self, IsTerminal};

/// Run parsed CLI (`clap` + subcommands).
pub fn run() -> Result<()> {
    let cli = Cli::parse();
    logging::init(&cli)?;

    if cli.no_color {
        // Ensure downstream crates see it even if only passed as flag.
        std::env::set_var("NO_COLOR", "1");
    }

    match cli.command {
        None => {
            if io::stdout().is_terminal() {
                tui::run_tui(&cli)?;
            } else {
                anyhow::bail!(i18n::tty_required_message());
            }
        }
        Some(cli::Commands::Tui) => {
            if !io::stdout().is_terminal() {
                anyhow::bail!(i18n::tty_required_message());
            }
            tui::run_tui(&cli)?;
        }
        Some(cli::Commands::Version) => {
            println!("{}", cli::version_line());
        }
        Some(cli::Commands::Completion { shell }) => {
            cli::print_completion(shell)?;
        }
        Some(cli::Commands::Doctor) => {
            doctor::run()?;
        }
        Some(cli::Commands::CreateUser(ref args)) => {
            let cfg = config::load_merged()?;
            create_user::run(&cli, &cfg, args.clone())?;
        }
    }

    Ok(())
}
