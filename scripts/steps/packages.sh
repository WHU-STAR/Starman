#!/bin/bash
#
# 软件包安装、配置模板与 EDITOR 交互步骤
#
# 用法：由项目根目录 install.sh source 本文件后调用 run_step_packages
#
# 依赖：scripts/lib/common.sh、tui.sh、pkgmgr.sh 已 source
#

# ============================================================================
# 包列表（与设计文档一致，便于 diff）
# ============================================================================

PACKAGES_BASE=(
    git
    curl
    wget
    vim
    tmux
    ca-certificates
    openssh-client
    rsync
    unzip
)

# 默认可选：默认勾选安装
PACKAGES_OPT_DEFAULT_ON=(
    htop
    tree
    jq
    ripgrep
    fd
)

# 默认可选：默认不勾选（重包或开发向）
PACKAGES_OPT_DEFAULT_OFF=(
    docker
    neovim
    fzf
    build-essential
)

# ============================================================================
# 路径
# ============================================================================

_starman_steps_dir() {
    local _src="${BASH_SOURCE[0]}"
    cd "$(dirname "$_src")" && pwd
}

STARMAN_STEPS_DIR="$(_starman_steps_dir)"
STARMAN_ROOT="$(cd "$STARMAN_STEPS_DIR/../.." && pwd)"

# ============================================================================
# sudo 包装
# ============================================================================

_starman_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# 与 pkgmgr_update 等价，但经 sudo（非 root 用户安装系统包时需要）
_starman_pkgmgr_update() {
    case "$PKGMGR" in
        apt)
            _starman_sudo env DEBIAN_FRONTEND=noninteractive apt-get update
            ;;
        yum)
            _starman_sudo yum makecache
            ;;
        dnf)
            _starman_sudo dnf makecache
            ;;
        pacman)
            _starman_sudo pacman -Sy
            ;;
        zypper)
            _starman_sudo zypper refresh
            ;;
        *)
            log_error "不支持的包管理器：$PKGMGR"
            return 1
            ;;
    esac
}

# 与 pkgmgr_install 等价，但经 sudo
_starman_pkgmgr_install() {
    case "$PKGMGR" in
        apt)
            _starman_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
            ;;
        yum)
            _starman_sudo yum install -y "$@"
            ;;
        dnf)
            _starman_sudo dnf install -y "$@"
            ;;
        pacman)
            _starman_sudo pacman -S --noconfirm "$@"
            ;;
        zypper)
            _starman_sudo zypper install -y "$@"
            ;;
        *)
            log_error "不支持的包管理器：$PKGMGR"
            return 1
            ;;
    esac
}

# ============================================================================
# 包索引更新（含重试）
# ============================================================================

pkgmgr_update_with_retry() {
    local max="${1:-3}"
    local n=0
    local delay=3

    while [ "$n" -lt "$max" ]; do
        if _starman_pkgmgr_update; then
            return 0
        fi
        n=$((n + 1))
        log_warn "包索引更新失败（第 ${n}/${max} 次），${delay}s 后重试..."
        sleep "$delay"
    done

    log_error "包索引更新失败，已重试 ${max} 次。请检查网络与软件源配置。"
    return 1
}

_pkgmgr_install_one_mapped() {
    local canonical="$1"
    local mapped
    mapped=$(pkgmgr_map_name "$canonical")

    if [ "$canonical" = "build-essential" ]; then
        case "$PKGMGR" in
            apt)
                mapped="build-essential"
                ;;
            dnf|yum)
                _starman_pkgmgr_install gcc make || return 1
                log_success "已安装 build-essential 等价包（gcc, make）"
                return 0
                ;;
            pacman)
                _starman_pkgmgr_install base-devel || return 1
                log_success "已安装 build-essential 等价包（base-devel）"
                return 0
                ;;
            zypper)
                _starman_sudo zypper install -y -t pattern devel_basis 2>/dev/null || _starman_pkgmgr_install gcc make
                return $?
                ;;
        esac
    fi

    if pkgmgr_is_installed "$mapped"; then
        log_info "已安装：$mapped"
        return 0
    fi
    log_info "安装：$canonical -> $mapped"
    _starman_pkgmgr_install "$mapped"
}

_pkgmgr_install_list_mapped() {
    local p
    for p in "$@"; do
        _pkgmgr_install_one_mapped "$p" || return 1
    done
}

# ============================================================================
# 模板：备份 + 写入 / 追加 STARMAN 区块
# ============================================================================

install_template_with_backup() {
    local snippet="$1"
    local dest="$2"

    if [ ! -f "$snippet" ]; then
        log_error "模板不存在：$snippet"
        return 1
    fi

    local tmp
    tmp="$(mktemp)"
    local marker="STARMAN MANAGED"

    if [ ! -f "$dest" ]; then
        _starman_sudo mkdir -p "$(dirname "$dest")"
        _starman_sudo install -m 0644 "$snippet" "$dest"
        log_success "已写入 $dest"
        rm -f "$tmp"
        return 0
    fi

    if _starman_sudo grep -qF "$marker" "$dest" 2>/dev/null; then
        log_info "已存在 Starman 区块，跳过：$dest"
        rm -f "$tmp"
        return 0
    fi

    local stamp
    stamp="$(date +%Y%m%d%H%M%S)"
    _starman_sudo cp -a "$dest" "${dest}.bak.${stamp}"
    log_info "已备份 ${dest} -> ${dest}.bak.${stamp}"

    _starman_sudo cat "$dest" >"$tmp"
    printf '\n' >>"$tmp"
    cat "$snippet" >>"$tmp"

    _starman_sudo install -m 0644 "$tmp" "$dest"
    rm -f "$tmp"
    log_success "已追加 Starman 配置到 $dest"
}

_vim_template_target() {
    if [ -d /etc/vim ]; then
        echo "/etc/vim/vimrc.local"
    elif [ -f /etc/vimrc ]; then
        echo "/etc/vimrc"
    else
        echo "/etc/vim/vimrc.local"
    fi
}

# ============================================================================
# EDITOR（README 四选项：vim / nvim / nano / emacs）
# ============================================================================

run_step_editor() {
    echo ""
    log_info "请选择默认编辑器（EDITOR / VISUAL，默认 vim）："
    echo "  1) vim"
    echo "  2) nvim（neovim）"
    echo "  3) nano"
    echo "  4) emacs"
    echo ""

    local choice="1"
    if [ -t 0 ]; then
        read -rp "请输入选项 [1-4，默认 1]: " choice
    fi
    choice="${choice:-1}"

    local ed="vim"
    case "$choice" in
        1) ed="vim" ;;
        2) ed="nvim" ;;
        3) ed="nano" ;;
        4) ed="emacs" ;;
        *)
            log_warn "无效选项，使用默认 vim"
            ed="vim"
            ;;
    esac

    local profile_d="/etc/profile.d/starman-editor.sh"
    local tmp
    tmp="$(mktemp)"
    {
        echo "# Starman: 默认编辑器（install-script-packages-config）"
        printf 'export EDITOR=%q\n' "$ed"
        printf 'export VISUAL=%q\n' "$ed"
    } >"$tmp"

    _starman_sudo install -m 0644 "$tmp" "$profile_d"
    rm -f "$tmp"
    log_success "已写入 $profile_d（EDITOR=$ed）"
}

# ============================================================================
# 可选包：TUI 勾选 + try_fzf_or_menu 二次确认未安装项
# ============================================================================

_run_optional_tui() {
    local menu_id
    tui_menu_create "可选软件包（空格切换，Enter 确认）"
    menu_id="$TUI_LAST_MENU_ID"

    local p
    for p in "${PACKAGES_OPT_DEFAULT_ON[@]}"; do
        tui_menu_add "$menu_id" "$p" "$p" true
    done
    for p in "${PACKAGES_OPT_DEFAULT_OFF[@]}"; do
        tui_menu_add "$menu_id" "$p" "$p" false
    done

    tui_menu_run "$menu_id"
    local result="$TUI_LAST_RESULT"
    local checked
    checked="$(tui_parse_result "$result" "CHECKED")"

    local merged=("${PACKAGES_OPT_DEFAULT_ON[@]}" "${PACKAGES_OPT_DEFAULT_OFF[@]}")
    local idx
    for idx in $checked; do
        local val="${merged[$idx]}"
        if [ -n "$val" ]; then
            _pkgmgr_install_one_mapped "$val" || log_warn "可选包安装失败：$val"
        fi
    done
}

_run_optional_fzf_round() {
    local merged=("${PACKAGES_OPT_DEFAULT_ON[@]}" "${PACKAGES_OPT_DEFAULT_OFF[@]}")
    local p mapped
    for p in "${merged[@]}"; do
        mapped=$(pkgmgr_map_name "$p")
        if [ "$p" = "build-essential" ]; then
            case "$PKGMGR" in
                apt) mapped="build-essential" ;;
                *) ;;
            esac
        fi
        if pkgmgr_is_installed "$mapped" 2>/dev/null; then
            continue
        fi
        # build-essential 在非 apt 上已展开为多个包，跳过模糊检测
        if [ "$p" = "build-essential" ] && [ "$PKGMGR" != "apt" ]; then
            continue
        fi

        local a
        a="$(try_fzf_or_menu "仍要安装未就绪的可选包：$p？" "安装" "跳过")"
        if [ "$a" = "安装" ]; then
            _pkgmgr_install_one_mapped "$p" || log_warn "安装失败：$p"
        fi
    done
}

_run_templates_interactive() {
    local vim_target
    vim_target="$(_vim_template_target)"

    tui_menu_create "是否写入配置模板（已存在则追加 STARMAN 区块并备份）"
    local mid="$TUI_LAST_MENU_ID"
    tui_menu_add "$mid" "Vim（$vim_target）" "vim" true
    tui_menu_add "$mid" "Tmux（/etc/tmux.conf）" "tmux" true
    tui_menu_add "$mid" "Bash（/etc/profile.d/starman-bash.sh）" "bash" false

    tui_menu_run "$mid"
    local result="$TUI_LAST_RESULT"
    local checked
    checked="$(tui_parse_result "$result" "CHECKED")"

    local keys=(vim tmux bash)
    local idx
    for idx in $checked; do
        local key="${keys[$idx]}"
        case "$key" in
            vim)
                install_template_with_backup "$STARMAN_ROOT/templates/vim.min.snippet" "$vim_target"
                ;;
            tmux)
                install_template_with_backup "$STARMAN_ROOT/templates/tmux.min.snippet" "/etc/tmux.conf"
                ;;
            bash)
                install_template_with_backup "$STARMAN_ROOT/templates/bash.min.snippet" "/etc/profile.d/starman-bash.sh"
                ;;
        esac
    done
}

# ============================================================================
# 主步骤
# ============================================================================

run_step_packages() {
    log_info "正在检测并安装系统包..."

    if ! declare -F pkgmgr_detect >/dev/null 2>&1; then
        log_error "pkgmgr 未加载，请确保已 source scripts/lib/pkgmgr.sh"
        return 1
    fi

    if ! pkgmgr_detect; then
        return 1
    fi
    log_info "包管理器：$PKGMGR"

    if ! pkgmgr_update_with_retry 3; then
        return 1
    fi

    log_info "安装基础工具包..."
    _pkgmgr_install_list_mapped "${PACKAGES_BASE[@]}" || return 1
    log_success "基础工具包已处理"

    if [ -t 0 ] && [ -t 1 ]; then
        _run_optional_tui
        _run_optional_fzf_round
    else
        log_warn "非交互式终端，跳过可选软件包与 fzf 确认"
    fi

    if [ -t 0 ] && [ -t 1 ]; then
        _run_templates_interactive
        run_step_editor
    else
        log_warn "非交互式终端，跳过配置模板与 EDITOR 交互"
    fi

    log_success "软件包与配置步骤完成"
}
