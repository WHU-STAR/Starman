#!/bin/bash
#
# OpenSSH 服务端 Starman 片段合并（OpenSpec: install-script-ssh）
#
# 用法：由项目根目录 install.sh source 后调用 run_step_ssh
#
# 环境变量：
#   STARMAN_SKIP_SSH=1     — 跳过本步骤
#   STARMAN_SSH_PORT       — 交互选端口时的默认值（默认 9527）
#   STARMAN_SSH_CONFIG     — sshd_config 路径（默认 /etc/ssh/sshd_config）
#

# ============================================================================
# 路径
# ============================================================================

_starman_ssh_repo_root() {
    (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
}

STARMAN_SSH_CONFIG="${STARMAN_SSH_CONFIG:-/etc/ssh/sshd_config}"

# ============================================================================
# sudo
# ============================================================================

_starman_ssh_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ============================================================================
# 片段生成与合并
# ============================================================================

_starman_ssh_build_block() {
    local port="$1"
    local root
    root="$(_starman_ssh_repo_root)"
    local tpl="${root}/templates/ssh/sshd_snippet.conf"
    if [ ! -f "$tpl" ]; then
        log_error "未找到模板：$tpl"
        return 1
    fi
    sed "s/__PORT__/${port}/g" "$tpl"
}

_starman_ssh_merge_into_config() {
    local cfg="$1"
    local block="$2"
    local tmp
    tmp="$(mktemp)"
    if grep -q '^# BEGIN STARMAN_SSH$' "$cfg" 2>/dev/null; then
        awk '
            /^# BEGIN STARMAN_SSH$/ { skip=1; next }
            /^# END STARMAN_SSH$/ { skip=0; next }
            !skip { print }
        ' "$cfg" >"$tmp" || return 1
    else
        cat "$cfg" >"$tmp" || return 1
    fi
    printf '\n%s\n' "$block" >>"$tmp"
    cat "$tmp"
    rm -f "$tmp"
}

_starman_ssh_validate_port() {
    local p="$1"
    case "$p" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

_starman_ssh_prompt_port() {
    local def="${1:-9527}"
    local input
    read -r -p "SSH 监听端口 [${def}]: " input >&2 || true
    input="${input:-$def}"
    printf '%s' "$input"
}

# 写入、sshd -t、失败回滚；参数：端口
_starman_ssh_apply() {
    local port="$1"
    local block
    block="$(_starman_ssh_build_block "$port")" || return 1

    local backup
    backup="${STARMAN_SSH_CONFIG}.bak.starman.$(date +%Y%m%d%H%M%S)"
    log_info "备份 ${STARMAN_SSH_CONFIG} → ${backup}"
    _starman_ssh_sudo cp -a "$STARMAN_SSH_CONFIG" "$backup" || {
        log_error "备份失败"
        return 1
    }

    local merged
    merged="$(_starman_ssh_merge_into_config "$STARMAN_SSH_CONFIG" "$block")" || {
        log_error "合并配置失败"
        return 1
    }

    # shellcheck disable=SC2024
    printf '%s\n' "$merged" | _starman_ssh_sudo tee "$STARMAN_SSH_CONFIG" >/dev/null || {
        log_error "写入 ${STARMAN_SSH_CONFIG} 失败"
        _starman_ssh_sudo cp -a "$backup" "$STARMAN_SSH_CONFIG"
        return 1
    }

    if ! _starman_ssh_sudo sshd -t -f "$STARMAN_SSH_CONFIG" 2>/dev/null; then
        log_error "sshd -t 校验失败，正在回滚…"
        if _starman_ssh_sudo cp -a "$backup" "$STARMAN_SSH_CONFIG"; then
            _starman_ssh_sudo sshd -t -f "$STARMAN_SSH_CONFIG" 2>/dev/null || log_warn "回滚后仍建议人工检查 sshd"
        fi
        if declare -F ui_err &>/dev/null; then
            ui_err "sshd 配置无效，已恢复备份：${backup}"
        else
            log_error "sshd 配置无效，已恢复备份：${backup}"
        fi
        return 1
    fi

    log_warn "已写入 SSH 监听端口 ${port}：请在防火墙/安全组中放行该端口（脚本不会自动修改 ufw/firewalld）"
    log_warn "若已改端口，请在新会话用 ssh -p ${port} 连接验证后再关闭旧会话"
    log_success "SSH 服务端步骤完成（备份：${backup}）"
}

# ============================================================================
# 主步骤
# ============================================================================

run_step_ssh() {
    if [ -n "${STARMAN_SKIP_SSH:-}" ]; then
        log_warn "已设置 STARMAN_SKIP_SSH，跳过 SSH 服务端步骤"
        return 0
    fi

    log_info "SSH 服务端（sshd_config）步骤…"

    if ! command -v sshd &>/dev/null; then
        log_warn "未找到 sshd，跳过 SSH 步骤"
        return 3
    fi

    if ! command -v sudo &>/dev/null && [ "$(id -u)" -ne 0 ]; then
        log_error "需要 sudo 以修改 ${STARMAN_SSH_CONFIG}"
        return 1
    fi

    if [ ! -f "$STARMAN_SSH_CONFIG" ]; then
        log_error "未找到 ${STARMAN_SSH_CONFIG}"
        return 1
    fi

    local port=""

    if ! declare -F tui_menu_create &>/dev/null; then
        log_warn "TUI 未加载，跳过 SSH 步骤"
        return 3
    fi

    tui_clear
    tui_menu_create "SSH 服务端（sshd_config Starman 片段）"
    local mid="$TUI_LAST_MENU_ID"
    tui_menu_set_radio "$mid"
    tui_menu_add "$mid" "跳过（不修改 sshd_config）" "skip" true
    tui_menu_add "$mid" "合并 Starman 片段（端口、X11、安全项）" "apply" false

    tui_menu_run "$mid"
    local result="${TUI_LAST_RESULT:-}"
    case "$result" in
        SELECTED:1) ;;
        *)
            log_warn "已跳过 SSH 服务端步骤"
            return 3
            ;;
    esac

    port="$(_starman_ssh_prompt_port "${STARMAN_SSH_PORT:-9527}")"

    if ! _starman_ssh_validate_port "$port"; then
        log_error "非法端口：$port（须为 1–65535 的整数）"
        return 1
    fi

    if [ "$port" -eq 22 ]; then
        log_warn "已选择端口 22：与常见全网扫描目标一致，请确认有意使用"
    fi

    _starman_ssh_apply "$port"
}
