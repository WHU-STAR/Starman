//! Load `/etc/starman/config.toml` and XDG user config with merge (user overrides system).

use anyhow::Context;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub const SYSTEM_CONFIG_PATH: &str = "/etc/starman/config.toml";

#[derive(Debug, Clone, Default, Deserialize, Serialize, PartialEq, Eq)]
pub struct StarmanConfig {
    /// Preferred UI language tag: `zh`, `en`, etc.
    pub lang: Option<String>,
    /// `starman create-user` 默认协作组（如 `lab`）
    pub default_user_group: Option<String>,
    /// 新用户登录 shell（如 `/bin/bash`）
    pub default_shell: Option<String>,
    /// Linuxbrew Brewfile 模板路径（默认 `/home/linuxbrew/Brewfile.starman`）
    pub brewfile_template_path: Option<String>,
    /// `create-user` 默认家目录块配额（如 `200G`），可用 `--no-quota` 关闭
    pub default_home_quota: Option<String>,
}

/// Merge: `user` fields override `system` when `Some`.
pub fn merge(system: StarmanConfig, user: StarmanConfig) -> StarmanConfig {
    StarmanConfig {
        lang: user.lang.or(system.lang),
        default_user_group: user
            .default_user_group
            .or(system.default_user_group),
        default_shell: user.default_shell.or(system.default_shell),
        brewfile_template_path: user
            .brewfile_template_path
            .or(system.brewfile_template_path),
        default_home_quota: user
            .default_home_quota
            .or(system.default_home_quota),
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
            ..Default::default()
        };
        let user = StarmanConfig {
            lang: Some("zh".into()),
            ..Default::default()
        };
        let m = merge(sys, user);
        assert_eq!(m.lang.as_deref(), Some("zh"));
    }

    #[test]
    fn merge_falls_back_to_system() {
        let sys = StarmanConfig {
            lang: Some("en".into()),
            ..Default::default()
        };
        let user = StarmanConfig {
            lang: None,
            ..Default::default()
        };
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
