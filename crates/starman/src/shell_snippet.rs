//! 将 Starman shell 标记块合并进 `.bashrc` / `.zshrc`（幂等替换或追加）。

pub const MARKER_START: &str = "# >>> starman user init >>>";
pub const MARKER_END: &str = "# <<< starman user init <<<";

/// 合并 `block`（须含起止标记行）到已有文件内容：若已存在标记块则整段替换，否则追加。
pub fn merge_block(existing: &str, block: &str) -> String {
    let block = block.trim();
    if existing.contains(MARKER_START) && existing.contains(MARKER_END) {
        replace_marked_region(existing, block)
    } else {
        let base = existing.trim_end();
        if base.is_empty() {
            format!("{}\n", block)
        } else {
            format!("{}\n\n{}\n", base, block)
        }
    }
}

fn replace_marked_region(existing: &str, new_block: &str) -> String {
    let Some(start_idx) = existing.find(MARKER_START) else {
        return merge_block("", new_block);
    };
    let Some(rel_end) = existing[start_idx..].find(MARKER_END) else {
        return format!("{}{}\n", &existing[..start_idx], new_block);
    };
    let end_idx = start_idx + rel_end + MARKER_END.len();
    let before = &existing[..start_idx];
    let after = &existing[end_idx..];
    format!("{}{}\n{}", before.trim_end(), new_block, after)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merge_appends_when_no_markers() {
        let out = merge_block("echo hello\n", "X\nY\n");
        assert!(out.contains("echo hello"));
        assert!(out.contains("X"));
    }

    #[test]
    fn merge_replaces_block() {
        let old = format!(
            "before\n{}\nold\n{}\nafter\n",
            MARKER_START, MARKER_END
        );
        let new_b = format!("{}\nnew\n{}", MARKER_START, MARKER_END);
        let out = merge_block(&old, &new_b);
        assert!(out.contains("new"));
        assert!(!out.contains("old"));
        assert!(out.contains("before"));
        assert!(out.contains("after"));
    }
}
