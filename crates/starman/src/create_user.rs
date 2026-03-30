//! `starman create-user`：创建 UNIX 用户、加入协作组、写入 shell 标记块、可选 brew bundle。

use crate::cli::{Cli, CreateUserCli};
use crate::config::StarmanConfig;
use crate::quota;
use crate::shell_snippet;
use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

const SNIPPET: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/assets/shell/starman-user.snippet"
));

pub const USERS_METADATA_PATH: &str = "/etc/starman/users.yaml";

#[derive(Debug, Default, Serialize, Deserialize)]
struct UsersFile {
    users: BTreeMap<String, UserMeta>,
}

#[derive(Debug, Serialize, Deserialize)]
struct UserMeta {
    created_at: String,
    #[serde(default)]
    groups: Vec<String>,
    #[serde(default)]
    brew: bool,
    /// 计划的家目录块配额描述（如 `200G`）；未启用则为 null
    #[serde(default)]
    home_quota: Option<String>,
}

pub fn run(_cli: &Cli, cfg: &StarmanConfig, args: CreateUserCli) -> Result<()> {
    ensure_root()?;
    validate_username(&args.username)?;

    let group = args
        .group
        .clone()
        .or_else(|| cfg.default_user_group.clone())
        .unwrap_or_else(|| "lab".to_string());

    let shell = args
        .shell
        .clone()
        .or_else(|| cfg.default_shell.clone())
        .unwrap_or_else(|| "/bin/bash".to_string());

    let brewfile_path = cfg
        .brewfile_template_path
        .clone()
        .unwrap_or_else(|| "/home/linuxbrew/Brewfile.starman".to_string());

    let quota_spec: Option<String> = if args.no_quota {
        None
    } else {
        Some(
            args.home_quota
                .clone()
                .or_else(|| cfg.default_home_quota.clone())
                .unwrap_or_else(|| "200G".to_string()),
        )
    };

    if let Some(ref s) = quota_spec {
        quota::parse_human_size_to_kb(s).with_context(|| {
            format!("无效的家目录配额: {s}（--home-quota / default_home_quota）")
        })?;
    }

    ensure_group(&group)?;
    create_unix_user(&args.username, &shell, &group)?;
    write_shell_snippets(&args.username, SNIPPET)?;
    append_metadata(
        &args.username,
        &group,
        !args.no_brew,
        quota_spec.clone(),
    )?;

    if let Some(ref spec) = quota_spec {
        let kb = quota::parse_human_size_to_kb(spec)?;
        let home = home_dir(&args.username);
        match quota::set_user_block_quota(&args.username, &home, kb) {
            Ok(()) => tracing::info!(quota = %spec, "已设置家目录块配额"),
            Err(e) => {
                tracing::warn!(
                    error = %e,
                    "未能设置磁盘配额（用户已创建）；若需配额请在挂载选项启用 usrquota、quotaon，并安装 quota 工具"
                );
                eprintln!(
                    "starman: 警告: 未能设置磁盘配额: {e}\n\
                     用户 `{}` 已创建。若需配额，请确认家目录所在文件系统已启用用户配额。",
                    args.username
                );
            }
        }
    }

    if args.no_brew {
        tracing::info!(
            brewfile = %brewfile_path,
            "已跳过 Linuxbrew（--no-brew）"
        );
    } else {
        let brewfile = PathBuf::from(&brewfile_path);
        if !brewfile.is_file() {
            tracing::warn!(
                path = %brewfile.display(),
                "未找到 Brewfile 模板，跳过 brew bundle；可将模板放到该路径或在 config.toml 设置 brewfile_template_path"
            );
        } else {
            match run_user_brew_bundle(&args.username, &brewfile) {
                Ok(()) => tracing::info!("Linuxbrew bundle 完成"),
                Err(e) => {
                    tracing::error!(error = %e, "用户已创建，但 brew bundle 失败");
                    bail!(
                        "用户 `{}` 已创建，但 Linuxbrew 初始化失败: {:#}",
                        args.username,
                        e
                    );
                }
            }
        }
    }

    tracing::info!(user = %args.username, group = %group, "create-user 完成");
    let mut summary = format!(
        "已创建用户 {}（组 {}，shell {}）",
        args.username, group, shell
    );
    if let Some(ref s) = quota_spec {
        summary.push_str(&format!("，配额目标 {}", s));
    }
    println!("{summary}");
    Ok(())
}

fn ensure_root() -> Result<()> {
    let euid = unsafe { libc::geteuid() };
    if euid != 0 {
        bail!("create-user 需要 root 权限，请使用: sudo starman create-user …");
    }
    Ok(())
}

pub(crate) fn validate_username(name: &str) -> Result<()> {
    if name.is_empty() || name.len() > 32 {
        bail!("无效用户名长度（1–32）");
    }
    let mut it = name.chars();
    let first = it.next().unwrap();
    if !first.is_ascii_lowercase() && first != '_' {
        bail!("用户名须以小写 ASCII 字母或 _ 开头");
    }
    for c in it {
        if !c.is_ascii_lowercase() && !c.is_ascii_digit() && c != '_' && c != '-' {
            bail!("用户名含非法字符: {c}");
        }
    }
    Ok(())
}

fn ensure_group(name: &str) -> Result<()> {
    let st = Command::new("getent")
        .args(["group", name])
        .status()
        .context("执行 getent group")?;
    if st.success() {
        return Ok(());
    }
    let st = Command::new("groupadd")
        .arg(name)
        .status()
        .context("执行 groupadd")?;
    if !st.success() {
        bail!("groupadd {name} 失败（退出码 {:?}）", st.code());
    }
    tracing::info!(group = %name, "已创建 UNIX 组");
    Ok(())
}

fn create_unix_user(username: &str, shell: &str, extra_group: &str) -> Result<()> {
    if Command::new("getent")
        .args(["passwd", username])
        .status()
        .context("getent passwd")?
        .success()
    {
        bail!("用户 {username} 已存在");
    }

    let st = Command::new("useradd")
        .args(["-m", "-s", shell, username])
        .status()
        .context("useradd")?;
    if !st.success() {
        bail!("useradd 失败: {:?}", st.code());
    }

    let st = Command::new("usermod")
        .args(["-aG", extra_group, username])
        .status()
        .context("usermod")?;
    if !st.success() {
        bail!("usermod -aG 失败: {:?}", st.code());
    }
    Ok(())
}

fn home_dir(username: &str) -> PathBuf {
    PathBuf::from("/home").join(username)
}

fn write_shell_snippets(username: &str, snippet: &str) -> Result<()> {
    let home = home_dir(username);
    for fname in [".bashrc", ".zshrc"] {
        let path = home.join(fname);
        let prev = if path.is_file() {
            fs::read_to_string(&path).with_context(|| format!("read {}", path.display()))?
        } else {
            String::new()
        };
        let merged = shell_snippet::merge_block(&prev, snippet);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).with_context(|| format!("mkdir {}", parent.display()))?;
        }
        let mut f = fs::File::create(&path).with_context(|| format!("write {}", path.display()))?;
        f.write_all(merged.as_bytes())?;

        let uid = uid_of(username)?;
        let gid = gid_of(username)?;
        chown_path(&path, uid, gid)?;
    }
    Ok(())
}

fn uid_of(username: &str) -> Result<u32> {
    let out = Command::new("id")
        .args(["-u", username])
        .output()
        .context("id -u")?;
    if !out.status.success() {
        bail!("id -u 失败");
    }
    String::from_utf8_lossy(&out.stdout)
        .trim()
        .parse::<u32>()
        .context("解析 uid")
}

fn gid_of(username: &str) -> Result<u32> {
    let out = Command::new("id")
        .args(["-g", username])
        .output()
        .context("id -g")?;
    if !out.status.success() {
        bail!("id -g 失败");
    }
    String::from_utf8_lossy(&out.stdout)
        .trim()
        .parse::<u32>()
        .context("解析 gid")
}

fn chown_path(path: &Path, uid: u32, gid: u32) -> Result<()> {
    #[cfg(unix)]
    {
        std::os::unix::fs::chown(path, Some(uid), Some(gid))
            .with_context(|| format!("chown {}", path.display()))?;
    }
    #[cfg(not(unix))]
    {
        let _ = (path, uid, gid);
    }
    Ok(())
}

fn append_metadata(
    username: &str,
    group: &str,
    brew: bool,
    home_quota: Option<String>,
) -> Result<()> {
    let path = Path::new(USERS_METADATA_PATH);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| format!("mkdir {}", parent.display()))?;
    }

    let mut file: UsersFile = if path.is_file() {
        let raw = fs::read_to_string(path).context("read users.yaml")?;
        serde_yaml::from_str(&raw).unwrap_or_default()
    } else {
        UsersFile::default()
    };

    file.users.insert(
        username.to_string(),
        UserMeta {
            created_at: chrono::Utc::now().to_rfc3339(),
            groups: vec![group.to_string()],
            brew,
            home_quota,
        },
    );

    let raw = serde_yaml::to_string(&file).context("serialize users.yaml")?;
    fs::write(path, raw).with_context(|| format!("write {}", path.display()))?;
    Ok(())
}

fn run_user_brew_bundle(username: &str, brewfile: &Path) -> Result<()> {
    let home = home_dir(username);
    let brewfile = brewfile
        .canonicalize()
        .unwrap_or_else(|_| brewfile.to_path_buf());
    let bf = brewfile.to_string_lossy().into_owned();

    let inner = format!(
        r#"set -euo pipefail
export HOMEBREW_PREFIX="$HOME/.linuxbrew"
export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH"
if [ ! -x "$HOMEBREW_PREFIX/bin/brew" ]; then
  echo "starman: 未找到 $HOMEBREW_PREFIX/bin/brew；请先为该用户安装 Linuxbrew（见文档），或使用 --no-brew" >&2
  exit 127
fi
exec brew bundle install --file={}"#,
        shell_escape_single(&bf)
    );

    let st = Command::new("sudo")
        .arg("-u")
        .arg(username)
        .arg("-H")
        .env("HOME", &home)
        .env("USER", username)
        .env("LOGNAME", username)
        .arg("/bin/bash")
        .arg("-lc")
        .arg(&inner)
        .status()
        .context("sudo brew bundle")?;
    if !st.success() {
        bail!("brew bundle 退出码 {:?}", st.code());
    }
    Ok(())
}

/// 将字符串放入 bash 单引号内（不含单引号的路径安全）。
fn shell_escape_single(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\"'\"'"))
}
