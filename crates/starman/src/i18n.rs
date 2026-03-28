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
