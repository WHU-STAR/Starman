//! Basic environment checks for operators.

use crate::config::{self, StarmanConfig};
use anyhow::Result;
use std::fmt::Write as _;
use std::path::Path;

/// Human-readable report (for TUI overlay and `starman doctor`).
pub fn format_report() -> String {
    let cfg: StarmanConfig = config::load_merged().unwrap_or_default();
    let mut out = String::from("Starman doctor\n\n");
    let sys = Path::new(config::SYSTEM_CONFIG_PATH);
    writeln!(
        out,
        "system config {}: {}",
        config::SYSTEM_CONFIG_PATH,
        if sys.is_file() {
            "present"
        } else {
            "missing (optional)"
        }
    )
    .ok();

    if let Some(p) = config::user_config_path() {
        writeln!(
            out,
            "user config {}: {}",
            p.display(),
            if p.is_file() {
                "present"
            } else {
                "missing (optional)"
            }
        )
        .ok();
    } else {
        writeln!(out, "user config: (no XDG config dir)").ok();
    }

    let mut warnings = 0u32;
    if !Path::new("/etc/starman").is_dir() {
        writeln!(
            out,
            "warning: /etc/starman/ directory missing (installer may create it)"
        )
        .ok();
        warnings += 1;
    }

    let _ = cfg;
    writeln!(out).ok();
    if warnings == 0 {
        writeln!(out, "OK: no issues detected (basic checks only).").ok();
    } else {
        writeln!(out, "Finished with {} warning(s).", warnings).ok();
    }
    out
}

pub fn run() -> Result<()> {
    print!("{}", format_report());
    Ok(())
}
