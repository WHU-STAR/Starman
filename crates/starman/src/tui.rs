//! Full-screen TUI using ratatui + crossterm.

use crate::cli::Cli;
use crate::config;
use crate::doctor;
use crate::i18n::{self, Lang};
use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{EnterAlternateScreen, LeaveAlternateScreen};
use ratatui::layout::{Constraint, Direction, Layout, Margin};
use ratatui::style::{Color, Modifier, Style};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph, Wrap};
use ratatui::{Frame, Terminal};
use std::io::stdout;
use std::time::Duration;

enum Screen {
    Main,
    Message(String),
}

enum MenuAction {
    Doctor,
    Version,
    Quit,
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
                );
            })?;

            if event::poll(Duration::from_millis(250))? {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Release {
                        continue;
                    }

                    match &mut screen {
                        Screen::Message(msg) => {
                            match key.code {
                                KeyCode::Esc | KeyCode::Char('q') => {
                                    screen = Screen::Main;
                                }
                                _ => {
                                    // Any key dismisses
                                    let _ = msg;
                                    screen = Screen::Main;
                                }
                            }
                            continue;
                        }
                        Screen::Main => {}
                    }

                    if show_help && matches!(key.code, KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('?')) {
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
        Some(2) => MenuAction::Quit,
        _ => MenuAction::Doctor,
    }
}

/// Solid fill for modal panels so underlying TUI cells do not show through `Paragraph` gaps.
fn overlay_fill_style(use_color: bool) -> Style {
    if use_color {
        Style::default()
            .bg(Color::Rgb(30, 30, 38))
            .fg(Color::White)
    } else {
        Style::default()
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
) {
    let title = i18n::tui_title(lang);
    let hint = i18n::tui_hint(lang);

    let border_style = if use_color {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default()
    };

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

    if show_help {
        let fill = overlay_fill_style(use_color);
        let area = center_area(f.area(), 52, 7);
        f.render_widget(Clear, area);
        let block = Block::default()
            .borders(Borders::ALL)
            .title("Help")
            .border_style(border_style)
            .style(fill);
        f.render_widget(block.clone(), area);
        let inner = block.inner(area);
        let p = Paragraph::new(i18n::tui_help_overlay(lang))
            .wrap(Wrap { trim: true })
            .style(fill);
        f.render_widget(p, inner);
    }

    if let Screen::Message(text) = screen {
        let fill = overlay_fill_style(use_color);
        let area = center_area(f.area(), 64, 18);
        f.render_widget(Clear, area);
        let block = Block::default()
            .borders(Borders::ALL)
            .title("Output")
            .border_style(border_style)
            .style(fill);
        f.render_widget(block.clone(), area);
        let inner = block.inner(area);
        let p = Paragraph::new(text.as_str())
            .wrap(Wrap { trim: false })
            .style(fill);
        f.render_widget(p, inner);
    }
}

fn center_area(area: ratatui::layout::Rect, w: u16, h: u16) -> ratatui::layout::Rect {
    let w = w.min(area.width);
    let h = h.min(area.height);
    let x = area.x + (area.width.saturating_sub(w)) / 2;
    let y = area.y + (area.height.saturating_sub(h)) / 2;
    ratatui::layout::Rect::new(x, y, w, h)
}
