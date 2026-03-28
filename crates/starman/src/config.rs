//! Load `/etc/starman/config.toml` and XDG user config with merge (user overrides system).

use anyhow::Context;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub const SYSTEM_CONFIG_PATH: &str = "/etc/starman/config.toml";

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct StarmanConfig {
    /// Preferred UI language tag: `zh`, `en`, etc.
    pub lang: Option<String>,
}

/// Merge: `user` fields override `system` when `Some`.
pub fn merge(system: StarmanConfig, user: StarmanConfig) -> StarmanConfig {
    StarmanConfig {
        lang: user.lang.or(system.lang),
    }
}

pub fn user_config_path() -> Option<PathBuf> {
    dirs::config_dir().map(|p| p.join("starman").join("config.toml"))
}

/// Try read TOML from path; missing file => Ok(None).
pub fn try_load(path: &std::path::Path) -> anyhow::Result<Option<StarmanConfig>> {
    if !path.is_file() {
        return Ok(None);
    }
    let raw = std::fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    let c: StarmanConfig = toml::from_str(&raw).with_context(|| format!("parse {}", path.display()))?;
    Ok(Some(c))
}

/// Load merged config (system then user).
pub fn load_merged() -> anyhow::Result<StarmanConfig> {
    let sys = try_load(std::path::Path::new(SYSTEM_CONFIG_PATH))?.unwrap_or_default();
    let user_path = user_config_path();
    let user = user_path
        .as_ref()
        .map(|p| try_load(p))
        .transpose()?
        .flatten()
        .unwrap_or_default();
    Ok(merge(sys, user))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn merge_prefers_user_lang() {
        let sys = StarmanConfig {
            lang: Some("en".into()),
        };
        let user = StarmanConfig {
            lang: Some("zh".into()),
        };
        let m = merge(sys, user);
        assert_eq!(m.lang.as_deref(), Some("zh"));
    }

    #[test]
    fn merge_falls_back_to_system() {
        let sys = StarmanConfig {
            lang: Some("en".into()),
        };
        let user = StarmanConfig { lang: None };
        let m = merge(sys, user);
        assert_eq!(m.lang.as_deref(), Some("en"));
    }

    #[test]
    fn try_load_parses_toml() {
        let mut tmp = tempfile::NamedTempFile::new().unwrap();
        writeln!(tmp, r#"lang = "zh""#).unwrap();
        let c = try_load(tmp.path()).unwrap().unwrap();
        assert_eq!(c.lang.as_deref(), Some("zh"));
    }
}
