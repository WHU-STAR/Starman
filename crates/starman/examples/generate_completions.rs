//! Write shell completion scripts to `assets/completions/` (run from repo root).
//!
//! ```text
//! cargo run -p starman --example generate_completions --locked
//! ```

use clap_complete::{generate, Shell};
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use starman::cli::command_for_completions;

fn main() -> std::io::Result<()> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let repo_root = manifest_dir
        .ancestors()
        .nth(2)
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidInput, "bad manifest path"))?;
    let out = repo_root.join("assets/completions");
    fs::create_dir_all(&out)?;
    for (shell, name) in [
        (Shell::Bash, "starman.bash"),
        (Shell::Zsh, "starman.zsh"),
        (Shell::Fish, "starman.fish"),
    ] {
        let mut cmd = command_for_completions();
        let path = out.join(name);
        let mut buf = Vec::new();
        generate(shell, &mut cmd, "starman", &mut buf);
        let mut f = fs::File::create(&path)?;
        f.write_all(&buf)?;
        eprintln!("wrote {}", path.display());
    }
    Ok(())
}
