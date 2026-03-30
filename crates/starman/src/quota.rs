//! 家目录所在文件系统的用户块配额（`setquota`），大小字符串解析为 KB（与 Linux quota 一致）。

use anyhow::{bail, Context, Result};
use std::path::{Path, PathBuf};
use std::process::Command;

/// 将 `200G`、`500M`、`1024K` 或纯数字（视为 KB）解析为 **KB**（1024 字节块数，与 `setquota` 一致）。
pub fn parse_human_size_to_kb(s: &str) -> Result<u64> {
    let s = s.trim();
    if s.is_empty() {
        bail!("配额不能为空");
    }
    let upper = s.to_ascii_uppercase();
    // 输出为 **KB**（与 setquota 块限制一致）：G=M*1024, M=K*1024，K 与裸数字均为 KB。
    let (num, mult): (&str, u64) = if let Some(rest) = upper.strip_suffix('G') {
        (rest.trim(), 1024u64 * 1024)
    } else if let Some(rest) = upper.strip_suffix('M') {
        (rest.trim(), 1024)
    } else if let Some(rest) = upper.strip_suffix('K') {
        (rest.trim(), 1)
    } else {
        (s, 1)
    };
    let v: f64 = num
        .parse()
        .with_context(|| format!("无效数字: {num}"))?;
    if v < 0.0 {
        bail!("配额不能为负");
    }
    let kb = (v * mult as f64).round() as u64;
    if kb == 0 {
        bail!("配额换算后为 0，请使用更大的值");
    }
    Ok(kb)
}

/// `df -P` 解析家目录所在挂载点（用于 `setquota` 最后一个参数）。
pub fn filesystem_mount_for_path(path: &Path) -> Result<PathBuf> {
    let p = path
        .to_str()
        .with_context(|| format!("路径需为 UTF-8: {}", path.display()))?;
    let out = Command::new("df")
        .args(["-P", p])
        .output()
        .context("执行 df -P")?;
    if !out.status.success() {
        bail!("df -P 失败: {:?}", out.status.code());
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let line = text
        .lines()
        .nth(1)
        .with_context(|| format!("df 无数据行: {}", text.trim()))?;
    let cols: Vec<&str> = line.split_whitespace().collect();
    let mnt = cols.last().with_context(|| format!("解析挂载点: {line}"))?;
    Ok(PathBuf::from(mnt))
}

/// 对用户 `username` 在 `home` 所在文件系统上设置块软/硬限制（KB，通常相同）。
pub fn set_user_block_quota(username: &str, home: &Path, size_kb: u64) -> Result<()> {
    let mount = filesystem_mount_for_path(home)?;
    let sk = size_kb.to_string();
    let st = Command::new("setquota")
        .args([
            "-u",
            username,
            sk.as_str(),
            sk.as_str(),
            "0",
            "0",
            mount.to_str().with_context(|| "挂载点 UTF-8")?,
        ])
        .status()
        .context("执行 setquota")?;
    if !st.success() {
        bail!("setquota 退出码 {:?}", st.code());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_200g() {
        let kb = parse_human_size_to_kb("200G").unwrap();
        assert_eq!(kb, 200u64 * 1024 * 1024);
    }

    #[test]
    fn parse_500m() {
        let kb = parse_human_size_to_kb("500M").unwrap();
        assert_eq!(kb, 500 * 1024);
    }

    #[test]
    fn parse_plain_kb() {
        let kb = parse_human_size_to_kb("1024").unwrap();
        assert_eq!(kb, 1024);
    }
}
