//! Full-screen TUI using ratatui + crossterm.

use crate::cli::{Cli, CreateUserCli};
use crate::config;
use crate::config::StarmanConfig;
use crate::create_user;
use crate::doctor;
use crate::i18n::{self, Lang};
use crate::quota;
use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::layout::{Constraint, Direction, Layout, Margin, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph, Wrap};
use ratatui::{Frame, Terminal};
use std::io::stdout;
use std::time::Duration;

enum Screen {
    Main,
    Message(String),
    CreateUser(CreateUserWizard),
}

enum MenuAction {
    Doctor,
    Version,
    CreateUser,
    Quit,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CuPhase {
    Username,
    Group,
    Shell,
    BrewYn,
    QuotaYn,
    QuotaSize,
    Confirm,
}

struct CreateUserWizard {
    phase: CuPhase,
    line_buf: String,
    username: String,
    group: Option<String>,
    shell: Option<String>,
    no_brew: bool,
    no_quota: bool,
    home_quota: Option<String>,
    err: Option<String>,
}

impl CreateUserWizard {
    fn new() -> Self {
        Self {
            phase: CuPhase::Username,
            line_buf: String::new(),
            username: String::new(),
            group: None,
            shell: None,
            no_brew: false,
            no_quota: false,
            home_quota: None,
            err: None,
        }
    }

    fn body_text(&self, lang: Lang, cfg: &StarmanConfig) -> String {
        let mut out = String::new();
        if let Some(ref e) = self.err {
            out.push_str(e);
            out.push_str("\n\n");
        }
        match self.phase {
            CuPhase::Username => {
                out.push_str(i18n::tui_cu_prompt_username(lang));
                out.push_str("\n\n> ");
                out.push_str(&self.line_buf);
            }
            CuPhase::Group => {
                out.push_str(i18n::tui_cu_prompt_group(lang));
                let g = cfg
                    .default_user_group
                    .as_deref()
                    .unwrap_or("lab");
                out.push_str(&format!("\n[{g}]"));
                out.push_str("\n\n> ");
                out.push_str(&self.line_buf);
            }
            CuPhase::Shell => {
                out.push_str(i18n::tui_cu_prompt_shell(lang));
                let s = cfg.default_shell.as_deref().unwrap_or("/bin/bash");
                out.push_str(&format!("\n[{s}]"));
                out.push_str("\n\n> ");
                out.push_str(&self.line_buf);
            }
            CuPhase::BrewYn => {
                out.push_str(i18n::tui_cu_prompt_brew(lang));
                out.push_str("\n\n");
                out.push_str(i18n::tui_cu_hint_yn(lang));
            }
            CuPhase::QuotaYn => {
                out.push_str(i18n::tui_cu_prompt_quota(lang));
                out.push_str("\n\n");
                out.push_str(i18n::tui_cu_hint_yn(lang));
            }
            CuPhase::QuotaSize => {
                out.push_str(i18n::tui_cu_prompt_quota_size(lang));
                out.push_str("\n\n> ");
                out.push_str(&self.line_buf);
                out.push_str("\n\n");
                out.push_str(i18n::tui_cu_hint_text(lang));
            }
            CuPhase::Confirm => {
                let g = self
                    .group
                    .clone()
                    .or_else(|| cfg.default_user_group.clone())
                    .unwrap_or_else(|| "lab".into());
                let sh = self
                    .shell
                    .clone()
                    .or_else(|| cfg.default_shell.clone())
                    .unwrap_or_else(|| "/bin/bash".into());
                let brew = if self.no_brew { "no" } else { "yes" };
                let quota_s = if self.no_quota {
                    "off".to_string()
                } else {
                    self.home_quota
                        .clone()
                        .or_else(|| cfg.default_home_quota.clone())
                        .unwrap_or_else(|| "200G".into())
                };
                match lang {
                    Lang::Zh => {
                        out.push_str(&format!(
                            "确认创建用户？\n\n\
                             登录名: {}\n\
                             组: {}\n\
                             shell: {}\n\
                             Linuxbrew: {}\n\
                             配额: {}\n",
                            self.username, g, sh, brew, quota_s
                        ));
                    }
                    Lang::En => {
                        out.push_str(&format!(
                            "Confirm create user?\n\n\
                             username: {}\n\
                             group: {}\n\
                             shell: {}\n\
                             Linuxbrew: {}\n\
                             quota: {}\n",
                            self.username, g, sh, brew, quota_s
                        ));
                    }
                }
                out.push_str("\n");
                out.push_str(i18n::tui_cu_confirm_hint(lang));
            }
        }
        if matches!(
            self.phase,
            CuPhase::Username | CuPhase::Group | CuPhase::Shell
        ) {
            out.push_str("\n\n");
            out.push_str(i18n::tui_cu_hint_text(lang));
        }
        out
    }

    fn build_cli(&self) -> CreateUserCli {
        CreateUserCli {
            username: self.username.clone(),
            group: self.group.clone(),
            shell: self.shell.clone(),
            no_brew: self.no_brew,
            home_quota: self.home_quota.clone(),
            no_quota: self.no_quota,
        }
    }

    fn apply_key(
        &mut self,
        key: &KeyEvent,
        cfg: &StarmanConfig,
    ) -> Result<Option<WizardCmd>> {
        if key.kind == KeyEventKind::Release {
            return Ok(None);
        }
        self.err = None;

        match key.code {
            KeyCode::Esc => return Ok(Some(WizardCmd::Exit)),
            _ => {}
        }

        match self.phase {
            CuPhase::Username | CuPhase::Group | CuPhase::Shell | CuPhase::QuotaSize => {
                match key.code {
                    KeyCode::Enter => {
                        let line = self.line_buf.trim();
                        match self.phase {
                            CuPhase::Username => {
                                if let Err(e) = create_user::validate_username(line) {
                                    self.err = Some(format!("{e:#}"));
                                    return Ok(None);
                                }
                                self.username = line.to_string();
                                self.phase = CuPhase::Group;
                                self.line_buf.clear();
                            }
                            CuPhase::Group => {
                                self.group = if line.is_empty() {
                                    None
                                } else {
                                    Some(line.to_string())
                                };
                                self.phase = CuPhase::Shell;
                                self.line_buf.clear();
                            }
                            CuPhase::Shell => {
                                self.shell = if line.is_empty() {
                                    None
                                } else {
                                    Some(line.to_string())
                                };
                                self.phase = CuPhase::BrewYn;
                                self.line_buf.clear();
                            }
                            CuPhase::QuotaSize => {
                                let spec = if line.is_empty() {
                                    cfg.default_home_quota
                                        .clone()
                                        .unwrap_or_else(|| "200G".into())
                                } else {
                                    line.to_string()
                                };
                                if let Err(e) = quota::parse_human_size_to_kb(&spec) {
                                    self.err = Some(format!("{e:#}"));
                                    return Ok(None);
                                }
                                self.home_quota = Some(spec);
                                self.phase = CuPhase::Confirm;
                                self.line_buf.clear();
                            }
                            _ => {}
                        }
                    }
                    KeyCode::Backspace => {
                        self.line_buf.pop();
                    }
                    KeyCode::Char(c) if !c.is_control() => {
                        self.line_buf.push(c);
                    }
                    _ => {}
                }
            }
            CuPhase::BrewYn => match key.code {
                KeyCode::Enter | KeyCode::Char('y') | KeyCode::Char('Y') => {
                    self.no_brew = false;
                    self.phase = CuPhase::QuotaYn;
                }
                KeyCode::Char('n') | KeyCode::Char('N') => {
                    self.no_brew = true;
                    self.phase = CuPhase::QuotaYn;
                }
                _ => {}
            },
            CuPhase::QuotaYn => match key.code {
                KeyCode::Enter | KeyCode::Char('y') | KeyCode::Char('Y') => {
                    self.no_quota = false;
                    self.phase = CuPhase::QuotaSize;
                    self.line_buf = cfg
                        .default_home_quota
                        .clone()
                        .unwrap_or_else(|| "200G".into());
                }
                KeyCode::Char('n') | KeyCode::Char('N') => {
                    self.no_quota = true;
                    self.home_quota = None;
                    self.phase = CuPhase::Confirm;
                    self.line_buf.clear();
                }
                _ => {}
            },
            CuPhase::Confirm => {
                if key.code == KeyCode::Enter {
                    return Ok(Some(WizardCmd::Run(self.build_cli())));
                }
            }
        }
        Ok(None)
    }
}

enum WizardCmd {
    Exit,
    Run(CreateUserCli),
}

pub fn run_tui(cli: &Cli) -> Result<()> {
    let cfg = config::load_merged().unwrap_or_default();
    let lang = i18n::detect_lang(&cfg);

    let use_color = !cli.no_color && std::env::var_os("NO_COLOR").is_none();

    crossterm::terminal::enable_raw_mode()?;
    let mut stdout = stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = ratatui::backend::CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut screen = Screen::Main;
    let mut state = ListState::default();
    state.select(Some(0));
    let mut show_help = false;

    let labels = vec![
        i18n::tui_item_doctor(lang),
        i18n::tui_item_version(lang),
        i18n::tui_item_create_user(lang),
        i18n::tui_item_quit(lang),
    ];

    let result = (|| -> Result<()> {
        loop {
            terminal.draw(|f| {
                draw_frame(
                    f,
                    &labels,
                    &mut state,
                    lang,
                    use_color,
                    show_help,
                    &screen,
                    &cfg,
                );
            })?;

            if event::poll(Duration::from_millis(250))? {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Release {
                        continue;
                    }

                    match &mut screen {
                        Screen::CreateUser(w) => {
                            if let Some(cmd) = w.apply_key(&key, &cfg)? {
                                match cmd {
                                    WizardCmd::Exit => {
                                        screen = Screen::Main;
                                    }
                                    WizardCmd::Run(args) => {
                                        match create_user::run(cli, &cfg, args) {
                                            Ok(()) => {
                                                screen = Screen::Message(
                                                    i18n::tui_cu_done_ok(lang).to_string(),
                                                );
                                            }
                                            Err(e) => {
                                                screen =
                                                    Screen::Message(format!("{e:#}"));
                                            }
                                        }
                                    }
                                }
                            }
                            continue;
                        }
                        Screen::Message(msg) => {
                            match key.code {
                                KeyCode::Esc | KeyCode::Char('q') => {
                                    screen = Screen::Main;
                                }
                                _ => {
                                    let _ = msg;
                                    screen = Screen::Main;
                                }
                            }
                            continue;
                        }
                        Screen::Main => {}
                    }

                    if show_help
                        && matches!(
                            key.code,
                            KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('?')
                        )
                    {
                        show_help = false;
                        continue;
                    }
                    if show_help {
                        continue;
                    }

                    match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => break,
                        KeyCode::Char('?') => show_help = true,
                        KeyCode::Down | KeyCode::Char('j') => {
                            let i = state.selected().unwrap_or(0);
                            let n = (i + 1).min(labels.len().saturating_sub(1));
                            state.select(Some(n));
                        }
                        KeyCode::Up | KeyCode::Char('k') => {
                            let i = state.selected().unwrap_or(0);
                            let n = i.saturating_sub(1);
                            state.select(Some(n));
                        }
                        KeyCode::Enter => {
                            match selected_action(state.selected()) {
                                MenuAction::Doctor => {
                                    screen = Screen::Message(doctor::format_report());
                                }
                                MenuAction::Version => {
                                    screen = Screen::Message(crate::cli::version_line());
                                }
                                MenuAction::CreateUser => {
                                    let euid = unsafe { libc::geteuid() };
                                    if euid != 0 {
                                        screen = Screen::Message(
                                            i18n::tui_cu_need_root(lang).to_string(),
                                        );
                                    } else {
                                        screen = Screen::CreateUser(CreateUserWizard::new());
                                    }
                                }
                                MenuAction::Quit => break,
                            }
                        }
                        _ => {}
                    }
                }
            }
        }
        Ok(())
    })();

    crossterm::terminal::disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    result
}

fn selected_action(sel: Option<usize>) -> MenuAction {
    match sel {
        Some(0) => MenuAction::Doctor,
        Some(1) => MenuAction::Version,
        Some(2) => MenuAction::CreateUser,
        Some(3) => MenuAction::Quit,
        _ => MenuAction::Doctor,
    }
}

/// 弹层内正文区（有颜色：深底白字；无颜色：在「全屏反色底」上再铺一层正常视频，避免与主菜单叠画）。
fn modal_panel_style(use_color: bool) -> Style {
    if use_color {
        Style::default()
            .bg(Color::Rgb(30, 30, 38))
            .fg(Color::White)
    } else {
        Style::default()
    }
}

/// 弹窗打开时整屏底色（不绘制主菜单，仅铺底 + 居中弹窗）。
fn fullscreen_backdrop_style(use_color: bool) -> Style {
    if use_color {
        Style::default()
            .bg(Color::Rgb(12, 12, 18))
            .fg(Color::DarkGray)
    } else {
        Style::default().add_modifier(Modifier::REVERSED)
    }
}

/// Paint every cell in `area` with spaces + `style` so nothing from the previous frame shows through.
/// `Paragraph`/`Block` alone may leave gaps; tmux 串口控制台尤甚。
fn paint_rect_solid(f: &mut Frame, area: Rect, style: Style) {
    let buf = f.buffer_mut();
    let x1 = area.x.saturating_add(area.width);
    let y1 = area.y.saturating_add(area.height);
    for y in area.y..y1 {
        for x in area.x..x1 {
            if let Some(cell) = buf.cell_mut((x, y)) {
                cell.set_symbol(" ");
                cell.set_style(style);
            }
        }
    }
}

fn draw_frame(
    f: &mut Frame,
    labels: &[&str],
    state: &mut ListState,
    lang: Lang,
    use_color: bool,
    show_help: bool,
    screen: &Screen,
    cfg: &StarmanConfig,
) {
    let border_style = if use_color {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default()
    };

    // 弹窗打开时：不绘制主界面（避免与弹层边框/文字在同一 buffer 交错成「└──┌Output」叠字）。
    // 先整屏铺底，再画居中弹窗。
    if let Screen::Message(text) = screen {
        let full = f.area();
        f.render_widget(Clear, full);
        paint_rect_solid(f, full, fullscreen_backdrop_style(use_color));
        let modal = center_area(full, 64, 18);
        if !use_color {
            // 无彩色：整屏为反色底，弹窗区域切回「正常视频」再画边框与正文。
            paint_rect_solid(f, modal, Style::default());
        }
        f.render_widget(Clear, modal);
        let fill = modal_panel_style(use_color);
        paint_rect_solid(f, modal, fill);
        let p = Paragraph::new(text.as_str())
            .wrap(Wrap { trim: false })
            .style(fill)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .title("Output")
                    .border_style(border_style)
                    .style(fill),
            );
        f.render_widget(p, modal);
        return;
    }

    if let Screen::CreateUser(w) = screen {
        let full = f.area();
        f.render_widget(Clear, full);
        paint_rect_solid(f, full, fullscreen_backdrop_style(use_color));
        let modal = center_area(full, 64, 22);
        if !use_color {
            paint_rect_solid(f, modal, Style::default());
        }
        f.render_widget(Clear, modal);
        let fill = modal_panel_style(use_color);
        paint_rect_solid(f, modal, fill);
        let body = w.body_text(lang, cfg);
        let p = Paragraph::new(body.as_str())
            .wrap(Wrap { trim: false })
            .style(fill)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .title(i18n::tui_cu_title(lang))
                    .border_style(border_style)
                    .style(fill),
            );
        f.render_widget(p, modal);
        return;
    }

    if show_help {
        let full = f.area();
        f.render_widget(Clear, full);
        paint_rect_solid(f, full, fullscreen_backdrop_style(use_color));
        let modal = center_area(full, 52, 7);
        if !use_color {
            paint_rect_solid(f, modal, Style::default());
        }
        f.render_widget(Clear, modal);
        let fill = modal_panel_style(use_color);
        paint_rect_solid(f, modal, fill);
        let p = Paragraph::new(i18n::tui_help_overlay(lang))
            .wrap(Wrap { trim: true })
            .style(fill)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .title("Help")
                    .border_style(border_style)
                    .style(fill),
            );
        f.render_widget(p, modal);
        return;
    }

    let title = i18n::tui_title(lang);
    let hint = i18n::tui_hint(lang);

    let area = f.area().inner(Margin {
        vertical: 1,
        horizontal: 2,
    });

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(5),
            Constraint::Length(3),
        ])
        .split(area);

    let title_block = Block::default()
        .borders(Borders::ALL)
        .title(title)
        .border_style(border_style);
    let title_inner = title_block.inner(chunks[0]);
    f.render_widget(title_block, chunks[0]);
    let subtitle = Paragraph::new("j/k · Enter · q — Starman TUI");
    f.render_widget(subtitle, title_inner);

    let items: Vec<ListItem> = labels
        .iter()
        .map(|s| ListItem::new(ratatui::text::Line::from(*s)))
        .collect();
    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title("Menu")
                .border_style(border_style),
        )
        .highlight_style(if use_color {
            Style::default().add_modifier(Modifier::BOLD).fg(Color::Yellow)
        } else {
            Style::default().add_modifier(Modifier::BOLD)
        });

    f.render_stateful_widget(list, chunks[1], state);

    let hint_para = Paragraph::new(hint).block(
        Block::default()
            .borders(Borders::ALL)
            .title("Keys")
            .border_style(border_style),
    );
    f.render_widget(hint_para, chunks[2]);
}

fn center_area(area: ratatui::layout::Rect, w: u16, h: u16) -> ratatui::layout::Rect {
    let w = w.min(area.width);
    let h = h.min(area.height);
    let x = area.x + (area.width.saturating_sub(w)) / 2;
    let y = area.y + (area.height.saturating_sub(h)) / 2;
    ratatui::layout::Rect::new(x, y, w, h)
}
