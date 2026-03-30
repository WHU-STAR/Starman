#!/bin/bash
#
# Linuxbrew 模板用户与 curated formula（OpenSpec: install-script-brew）
#
# 用法：由项目根目录 install.sh source 后调用 run_step_brew
#
# 目的：在专用用户 linuxbrew 下安装 Homebrew 至 /home/linuxbrew/.linuxbrew，作为后续「每用户
# 独立 brew」的模板；预装 fzf、btop 等 apt 体验偏弱的 CLI。
#
# 多用户后续（设计摘要）：
#   - 推荐：在新用户自己的 ~/.linuxbrew 初始化后，使用本模板生成的 Brewfile 执行
#     brew bundle install --file=/home/linuxbrew/Brewfile.starman
#   - 备选：将 /home/linuxbrew/.linuxbrew 整树复制到目标用户 ~/.linuxbrew 后 chown；因 Cellar
#     内可能存在绝对路径，须在目标环境实测后再依赖此方式。
#
# 依赖：git、sudo；HTTP 下载优先 wget、回退 curl；建议先完成 scripts/steps/packages.sh
#
# 国内镜像（清华 TUNA）：若无法访问 GitHub，自动改用镜像安装与 bottles。
#   https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/
#   https://mirrors.tuna.tsinghua.edu.cn/help/homebrew-bottles/
# 环境变量：
#   STARMAN_HOMEBREW_MIRROR=auto|github|tuna
#     auto（默认）：探测 https://raw.githubusercontent.com/.../install.sh ，失败则用 TUNA
#     github：强制官方安装脚本（需可达 GitHub）
#     tuna：强制国内路径（git clone install + TUNA bottles/API）
#

# ============================================================================
# sudo（root 直接执行，否则 sudo）
# ============================================================================

_starman_brew_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ============================================================================
# 常量
# ============================================================================

STARMAN_BREW_USER="${STARMAN_BREW_USER:-linuxbrew}"
STARMAN_BREW_HOME="/home/${STARMAN_BREW_USER}"
STARMAN_LINUXBREW_PREFIX="${STARMAN_LINUXBREW_PREFIX:-${STARMAN_BREW_HOME}/.linuxbrew}"
STARMAN_BREWFILE_PATH="${STARMAN_BREWFILE_PATH:-${STARMAN_BREW_HOME}/Brewfile.starman}"

# 与 design.md 一致：最小 curated 集（须含 fzf、btop）
STARMAN_BREW_FORMULAS=(fzf btop ripgrep fd bat)

# 清华 TUNA Homebrew / Linuxbrew（与官方帮助页一致）
_STARMAN_TUNA_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
_STARMAN_TUNA_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
_STARMAN_TUNA_INSTALL_GIT="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.git"
_STARMAN_TUNA_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
_STARMAN_TUNA_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"

# 由 _starman_brew_select_mirror_mode 设置：空 | tuna
_STARMAN_BREW_MIRROR_MODE=""

# ============================================================================
# GitHub / 镜像探测
# ============================================================================

# 以能否拉取官方 install.sh 作为「可走 GitHub 安装链」的判据
_starman_brew_github_install_reachable() {
    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        return 1
    fi
    starman_http_probe "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
}

_starman_brew_select_mirror_mode() {
    _STARMAN_BREW_MIRROR_MODE=""
    local policy="${STARMAN_HOMEBREW_MIRROR:-auto}"
    case "$policy" in
        tuna)
            _STARMAN_BREW_MIRROR_MODE="tuna"
            log_info "Homebrew：已强制使用清华 TUNA 镜像（STARMAN_HOMEBREW_MIRROR=tuna）"
            ;;
        github)
            _STARMAN_BREW_MIRROR_MODE=""
            log_info "Homebrew：已强制使用 GitHub 官方安装源（STARMAN_HOMEBREW_MIRROR=github）"
            ;;
        auto | *)
            if _starman_brew_github_install_reachable; then
                _STARMAN_BREW_MIRROR_MODE=""
                log_info "Homebrew：探测到可访问 GitHub 安装脚本，使用官方源"
            else
                _STARMAN_BREW_MIRROR_MODE="tuna"
                log_warn "Homebrew：无法访问 GitHub 安装脚本，改用清华 TUNA 镜像安装"
            fi
            ;;
    esac
}

# ============================================================================
# 占位：未来「新用户独立 brew」自动化可接此钩子（当前不实现克隆逻辑）
# ============================================================================

starman_brew_clone_for_new_user() {
    log_warn "starman_brew_clone_for_new_user：尚未实现；请使用 Brewfile 或见 openspec 后续变更"
    return 1
}

# ============================================================================
# linuxbrew 用户与 sudoers
# ============================================================================

_starman_brew_ensure_user() {
    local u="$STARMAN_BREW_USER"
    if id "$u" &>/dev/null; then
        log_info "用户已存在：$u"
        return 0
    fi
    log_info "创建用户：$u（家目录 ${STARMAN_BREW_HOME}）"
    if ! _starman_brew_sudo useradd -m -s /bin/bash "$u" 2>/dev/null; then
        log_error "useradd 失败（是否已存在同名 UID？）"
        return 1
    fi
    return 0
}

_starman_brew_ensure_sudoers() {
    local u="$STARMAN_BREW_USER"
    local f="/etc/sudoers.d/starman-linuxbrew"
    if _starman_brew_sudo test -f "$f"; then
        return 0
    fi
    log_info "写入 $f（${u} 免密 sudo，供 Homebrew 安装系统依赖）"
    # shellcheck disable=SC2024
    echo "${u} ALL=(ALL) NOPASSWD: ALL" | _starman_brew_sudo tee "$f" >/dev/null
    _starman_brew_sudo chmod 0440 "$f"
    if command -v visudo &>/dev/null; then
        _starman_brew_sudo visudo -c -f "$f" || {
            log_error "visudo 校验失败，已删除 $f"
            _starman_brew_sudo rm -f "$f"
            return 1
        }
    fi
    return 0
}

# ============================================================================
# Homebrew 安装与 formula
# ============================================================================

_starman_brew_run_as_template() {
    local cmd="$1"
    if [ "${_STARMAN_BREW_MIRROR_MODE:-}" = "tuna" ]; then
        # shellcheck disable=SC2016
        _starman_brew_sudo -u "$STARMAN_BREW_USER" -H \
            env HOME="$STARMAN_BREW_HOME" \
            HOMEBREW_NO_ANALYTICS=1 \
            HOMEBREW_BREW_GIT_REMOTE="$_STARMAN_TUNA_BREW_GIT_REMOTE" \
            HOMEBREW_CORE_GIT_REMOTE="$_STARMAN_TUNA_CORE_GIT_REMOTE" \
            HOMEBREW_INSTALL_FROM_API=1 \
            HOMEBREW_API_DOMAIN="$_STARMAN_TUNA_API_DOMAIN" \
            HOMEBREW_BOTTLE_DOMAIN="$_STARMAN_TUNA_BOTTLE_DOMAIN" \
            PATH="/usr/local/bin:/usr/bin:/bin" \
            bash -lc "$cmd"
    else
        # shellcheck disable=SC2016
        _starman_brew_sudo -u "$STARMAN_BREW_USER" -H \
            env HOME="$STARMAN_BREW_HOME" \
            HOMEBREW_NO_ANALYTICS=1 \
            PATH="/usr/local/bin:/usr/bin:/bin" \
            bash -lc "$cmd"
    fi
}

# 将 TUNA 环境写入模板用户 profile，便于后续登录与 brew update
_starman_brew_persist_tuna_profile() {
    [ "${_STARMAN_BREW_MIRROR_MODE:-}" = "tuna" ] || return 0
    local pf="${STARMAN_BREW_HOME}/.profile"
    if _starman_brew_sudo test -f "$pf" && _starman_brew_sudo grep -q 'Starman: Homebrew TUNA' "$pf" 2>/dev/null; then
        return 0
    fi
    log_info "写入 ${pf}（Homebrew 清华镜像环境变量）"
    # shellcheck disable=SC2024
    {
        echo ""
        echo "# Starman: Homebrew TUNA（https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/）"
        echo "export HOMEBREW_BREW_GIT_REMOTE=\"${_STARMAN_TUNA_BREW_GIT_REMOTE}\""
        echo "export HOMEBREW_CORE_GIT_REMOTE=\"${_STARMAN_TUNA_CORE_GIT_REMOTE}\""
        echo "export HOMEBREW_INSTALL_FROM_API=1"
        echo "export HOMEBREW_API_DOMAIN=\"${_STARMAN_TUNA_API_DOMAIN}\""
        echo "export HOMEBREW_BOTTLE_DOMAIN=\"${_STARMAN_TUNA_BOTTLE_DOMAIN}\""
    } | _starman_brew_sudo tee -a "$pf" >/dev/null
    _starman_brew_sudo chown "${STARMAN_BREW_USER}:${STARMAN_BREW_USER}" "$pf" 2>/dev/null || true
}

_starman_brew_install_homebrew() {
    # 须先于「已安装则跳过」分支执行，以便后续 formula 与 profile 使用同一镜像策略
    _starman_brew_select_mirror_mode

    if [ -x "${STARMAN_LINUXBREW_PREFIX}/bin/brew" ]; then
        log_info "已存在 ${STARMAN_LINUXBREW_PREFIX}/bin/brew，跳过官方安装脚本"
        _starman_brew_persist_tuna_profile
        return 0
    fi

    if [ "${_STARMAN_BREW_MIRROR_MODE:-}" = "tuna" ]; then
        if ! command -v git &>/dev/null; then
            log_error "使用国内镜像安装需要 git，请先安装 git（例如完成 packages 步骤）"
            return 1
        fi
        log_info "使用清华镜像克隆 install 仓库并执行 install.sh（NONINTERACTIVE）…"
        # 与 https://mirrors.tuna.tsinghua.edu.cn/help/homebrew/ 一致
        _starman_brew_run_as_template "
set -e
cd \"${STARMAN_BREW_HOME}\"
rm -rf brew-install-starman
git clone --depth=1 ${_STARMAN_TUNA_INSTALL_GIT} brew-install-starman
NONINTERACTIVE=1 CI=1 /bin/bash brew-install-starman/install.sh
rm -rf brew-install-starman
" || {
            log_error "Homebrew 镜像安装脚本失败"
            return 1
        }
    else
        if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
            log_error "需要 wget 或 curl 以下载 Homebrew 安装脚本"
            return 1
        fi
        local _hb_inst
        _hb_inst="$(mktemp)"
        local _hb_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
        log_info "下载并执行 Homebrew 官方安装脚本（NONINTERACTIVE）…"
        if command -v wget &>/dev/null; then
            wget -q --timeout="${STARMAN_HTTP_TIMEOUT:-30}" --tries=1 -O "$_hb_inst" "$_hb_url" 2>/dev/null || {
                rm -f "$_hb_inst"
                log_error "wget 下载 Homebrew 安装脚本失败"
                return 1
            }
        else
            curl -fsSL --connect-timeout "${STARMAN_CURL_CONNECT_TIMEOUT:-5}" --max-time "${STARMAN_HTTP_TIMEOUT:-30}" -o "$_hb_inst" "$_hb_url" 2>/dev/null || {
                rm -f "$_hb_inst"
                log_error "curl 下载 Homebrew 安装脚本失败"
                return 1
            }
        fi
        _starman_brew_run_as_template "NONINTERACTIVE=1 CI=1 /bin/bash '$_hb_inst'" || {
            rm -f "$_hb_inst"
            log_error "Homebrew 安装脚本失败"
            return 1
        }
        rm -f "$_hb_inst"
    fi

    if [ ! -x "${STARMAN_LINUXBREW_PREFIX}/bin/brew" ]; then
        log_error "未找到 ${STARMAN_LINUXBREW_PREFIX}/bin/brew"
        return 1
    fi
    _starman_brew_persist_tuna_profile
    return 0
}

_starman_brew_shellenv_eval() {
    printf 'eval "$(%s/bin/brew shellenv)"' "${STARMAN_LINUXBREW_PREFIX}"
}

_starman_brew_install_formulas() {
    local p
    p="$(_starman_brew_shellenv_eval)"
    local pkg
    for pkg in "${STARMAN_BREW_FORMULAS[@]}"; do
        log_info "brew install ${pkg} …"
        _starman_brew_run_as_template "${p} && brew install ${pkg}" || log_warn "brew install ${pkg} 失败（已记录，继续）"
    done
    return 0
}

_starman_brew_dump_brewfile() {
    local p
    p="$(_starman_brew_shellenv_eval)"
    log_info "生成 Brewfile：${STARMAN_BREWFILE_PATH}"
    _starman_brew_run_as_template "${p} && brew bundle dump --force --file='${STARMAN_BREWFILE_PATH}'" || {
        log_warn "brew bundle dump 失败"
        return 1
    }
    return 0
}

_starman_brew_doctor_log() {
    local p
    p="$(_starman_brew_shellenv_eval)"
    log_info "brew doctor（仅记录）"
    _starman_brew_run_as_template "${p} && brew doctor" 2>&1 | while IFS= read -r line; do
        log_info "[brew doctor] $line"
    done || true
}

# ============================================================================
# 主步骤
# ============================================================================

run_step_brew() {
    if [ -n "${STARMAN_SKIP_BREW:-}" ]; then
        log_warn "已设置 STARMAN_SKIP_BREW，跳过 Linuxbrew 步骤"
        return 0
    fi

    log_info "Linuxbrew 模板步骤…"

    if ! command -v sudo &>/dev/null; then
        log_error "需要 sudo"
        return 1
    fi

    if ! declare -F tui_menu_create &>/dev/null; then
        log_warn "TUI 未加载，跳过 Linuxbrew"
        return 3
    fi

    tui_clear
    tui_menu_create "Linuxbrew（模板用户 ${STARMAN_BREW_USER}）"
    local mid="$TUI_LAST_MENU_ID"
    tui_menu_set_radio "$mid"
    tui_menu_add "$mid" "跳过（不安装 Homebrew）" "skip" true
    tui_menu_add "$mid" "安装模板：${STARMAN_LINUXBREW_PREFIX} + curated 包" "install" false

    tui_menu_run "$mid"
    local result="${TUI_LAST_RESULT:-}"
    case "$result" in
        SELECTED:1) ;;
        *)
            log_warn "已跳过 Linuxbrew"
            return 3
            ;;
    esac

    if ! _starman_brew_ensure_user; then
        return 1
    fi
    if ! _starman_brew_ensure_sudoers; then
        return 1
    fi
    if ! _starman_brew_install_homebrew; then
        return 1
    fi
    _starman_brew_install_formulas
    _starman_brew_dump_brewfile || true
    _starman_brew_doctor_log || true

    log_success "Linuxbrew 模板步骤完成（Brewfile：${STARMAN_BREWFILE_PATH}）"
}
