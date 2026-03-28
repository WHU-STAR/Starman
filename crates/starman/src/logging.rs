//! Initialize `tracing` with `STARMAN_LOG` taking precedence over `RUST_LOG`.

use crate::cli::Cli;
use anyhow::Result;
use tracing_subscriber::EnvFilter;

pub fn init(_cli: &Cli) -> Result<()> {
    // STARMAN_LOG overrides default filter when set (still maps into RUST_LOG for tracing-subscriber).
    if let Ok(v) = std::env::var("STARMAN_LOG") {
        std::env::set_var("RUST_LOG", v);
    }

    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_writer(std::io::stderr)
        .without_time()
        .with_target(false)
        .try_init()
        .ok(); // ignore double-init in tests

    Ok(())
}
