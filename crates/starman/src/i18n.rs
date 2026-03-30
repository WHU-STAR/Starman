//! Minimal zh/en strings (no external i18n crate).

use crate::config::StarmanConfig;

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum Lang {
    Zh,
    En,
}

pub fn detect_lang(config: &StarmanConfig) -> Lang {
    if let Ok(l) = std::env::var("STARMAN_LANG") {
        if l.to_ascii_lowercase().starts_with("zh") {
            return Lang::Zh;
        }
        if l.to_ascii_lowercase().starts_with("en") {
            return Lang::En;
        }
    }
    if let Some(l) = &config.lang {
        let l = l.to_ascii_lowercase();
        if l.starts_with("zh") {
            return Lang::Zh;
        }
    }
    if let Ok(lc) = std::env::var("LC_MESSAGES") {
        if lc.contains("zh") || lc.contains("ZH") {
            return Lang::Zh;
        }
    }
    if let Ok(lang) = std::env::var("LANG") {
        if lang.contains("zh") {
            return Lang::Zh;
        }
    }
    Lang::En
}

pub fn tty_required_message() -> String {
    match std::env::var("LC_MESSAGES")
        .ok()
        .or_else(|| std::env::var("LANG").ok())
        .unwrap_or_default()
        .contains("zh")
    {
        true => "错误：需要交互式终端（TTY）才能使用 TUI。请使用 `starman tui` 在真实终端中运行，或使用子命令如 `starman version` / `starman doctor`。"
            .to_string(),
        false => "error: an interactive terminal (TTY) is required for the TUI. Run `starman tui` in a real terminal, or use e.g. `starman version` / `starman doctor`."
            .to_string(),
    }
}

pub fn tui_title(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "Starman 主菜单",
        Lang::En => "Starman main menu",
    }
}

pub fn tui_hint(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "↑/↓ j/k 移动 · Enter 执行 · q/Esc 退出 · ? 帮助",
        Lang::En => "↑/↓ j/k move · Enter run · q/Esc quit · ? help",
    }
}

pub fn tui_item_doctor(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "运行 doctor（环境检查）",
        Lang::En => "Run doctor (environment check)",
    }
}

pub fn tui_item_version(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "显示版本信息",
        Lang::En => "Show version",
    }
}

pub fn tui_item_create_user(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "创建用户（向导）",
        Lang::En => "Create user (wizard)",
    }
}

pub fn tui_cu_need_root(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "创建用户需要 root。请使用: sudo starman tui",
        Lang::En => "create-user requires root. Run: sudo starman tui",
    }
}

pub fn tui_cu_title(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "创建用户",
        Lang::En => "Create user",
    }
}

pub fn tui_cu_prompt_username(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "登录名（小写字母、数字、_、-；1–32 字符）",
        Lang::En => "Username (lower, digits, _,-; 1–32 chars)",
    }
}

pub fn tui_cu_prompt_group(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "协作 UNIX 组（留空则使用配置中的 default_user_group）",
        Lang::En => "UNIX group (empty = default_user_group from config)",
    }
}

pub fn tui_cu_prompt_shell(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "登录 shell 路径（留空则使用配置中的 default_shell）",
        Lang::En => "Login shell path (empty = default_shell from config)",
    }
}

pub fn tui_cu_prompt_brew(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "是否运行 Linuxbrew bundle（模板见 brewfile_template_path）？",
        Lang::En => "Run Linuxbrew bundle (see brewfile_template_path)?",
    }
}

pub fn tui_cu_prompt_quota(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "是否设置家目录块配额？",
        Lang::En => "Set home directory block quota?",
    }
}

pub fn tui_cu_prompt_quota_size(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "配额大小（如 200G、500M；与 --home-quota 相同）",
        Lang::En => "Quota size (e.g. 200G, 500M; same as --home-quota)",
    }
}

pub fn tui_cu_hint_yn(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "Enter/Y：是 · N：否 · Esc：取消向导",
        Lang::En => "Enter/Y: yes · N: no · Esc: cancel wizard",
    }
}

pub fn tui_cu_hint_text(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "Enter：下一步 · Backspace：删除 · Esc：取消向导",
        Lang::En => "Enter: next · Backspace: delete · Esc: cancel wizard",
    }
}

pub fn tui_cu_confirm_hint(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "Enter：执行创建 · Esc：取消",
        Lang::En => "Enter: run · Esc: cancel",
    }
}

pub fn tui_cu_done_ok(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "用户已创建（详见日志）。按任意键返回菜单。",
        Lang::En => "User created (see logs). Press any key to return.",
    }
}

pub fn tui_item_quit(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "退出",
        Lang::En => "Quit",
    }
}

pub fn tui_help_overlay(lang: Lang) -> &'static str {
    match lang {
        Lang::Zh => "帮助：与装机脚本 TUI 类似，使用 j/k 或方向键导航。",
        Lang::En => "Help: like the install TUI — use j/k or arrows to navigate.",
    }
}
