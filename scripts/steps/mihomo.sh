#!/bin/bash
#
# mihomo 安装与 systemd 单元（OpenSpec: install-script-mihomo）
#
# 用法：由项目根 install.sh source 后调用 run_step_mihomo
#
# 环境变量：
#   STARMAN_SKIP_MIHOMO=1           — 跳过本步骤（退出码 0，会写入装机状态）
#   STARMAN_GITHUB_PROBE_URL        — GitHub 可达性探测 URL（默认 https://github.com）
#   STARMAN_MIHOMO_RELEASE_API      — Release API（默认 MetaCubeX/mihomo latest）
#   STARMAN_CURL_CONNECT_TIMEOUT    — curl 连接超时秒数（默认 5；HTTP 优先 wget）
#   STARMAN_HTTP_TIMEOUT            — wget/curl 总体超时（秒，见 common.sh）
#   STARMAN_CURL_MAX_TIME           — Release API / 二进制下载 max-time（默认 40 / 120）
#

# ============================================================================
# 路径
# ============================================================================

_starman_mihomo_repo_root() {
    (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
}

STARMAN_MIHOMO_PREFIX="${STARMAN_MIHOMO_PREFIX:-/opt/mihomo}"
STARMAN_MIHOMO_BIN="${STARMAN_MIHOMO_PREFIX}/bin/mihomo"
STARMAN_MIHOMO_CONFIG_DIR="${STARMAN_MIHOMO_CONFIG_DIR:-/etc/mihomo}"
STARMAN_MIHOMO_CONFIG="${STARMAN_MIHOMO_CONFIG:-${STARMAN_MIHOMO_CONFIG_DIR}/config.yaml}"
STARMAN_MIHOMO_UNIT="${STARMAN_MIHOMO_UNIT:-/etc/systemd/system/mihomo.service}"

STARMAN_MIHOMO_RELEASE_API="${STARMAN_MIHOMO_RELEASE_API:-https://api.github.com/repos/MetaCubeX/mihomo/releases/latest}"
STARMAN_MIHOMO_RELEASE_PAGE="${STARMAN_MIHOMO_RELEASE_PAGE:-https://github.com/MetaCubeX/mihomo/releases/latest}"

# ============================================================================
# sudo
# ============================================================================

_starman_mihomo_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ============================================================================
# 网络探测（优先 wget，见 scripts/lib/common.sh）
# ============================================================================

# 通用：URL 可 GET（静默成功即视为可达）
starman_probe_url() {
    local url="$1"
    [ -n "$url" ] || return 1
    starman_http_probe "$url"
}

starman_probe_github() {
    starman_probe_url "${STARMAN_GITHUB_PROBE_URL:-https://github.com}"
}

# ============================================================================
# 架构 → 资源名
# ============================================================================

_starman_mihomo_go_arch() {
    case "$(uname -m)" in
        x86_64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        *)
            log_error "不支持的架构：$(uname -m)（仅测试 x86_64 / aarch64）"
            return 1
            ;;
    esac
}

# 从 GitHub API JSON 选取 linux-$arch 的 .gz 资源（优先稳定命名 mihomo-linux-$arch-vX.Y.Z.gz）
_starman_mihomo_pick_download_url() {
    local arch="$1"
    local json="$2"
    STARMAN_MIHOMO_ASSET_NAME=""
    STARMAN_MIHOMO_DOWNLOAD_URL=""
    local jf out name url
    jf="$(mktemp)"
    printf '%s' "$json" >"$jf"
    out="$(python3 - "$arch" "$jf" <<'PY'
import json, re, sys
arch = sys.argv[1]
with open(sys.argv[2], encoding="utf-8") as f:
    data = json.load(f)
assets = data.get("assets") or []
pat = re.compile(rf"^mihomo-linux-{re.escape(arch)}-v\\d+\\.\\d+\\.\\d+\\.gz$")
best = None
for a in assets:
    name = a.get("name") or ""
    if pat.match(name):
        best = a
        break
if not best:
    for a in assets:
        name = a.get("name") or ""
        if name.startswith(f"mihomo-linux-{arch}-") and name.endswith(".gz"):
            if "go" not in name and "compatible" not in name.lower():
                best = a
                break
if not best:
    for a in assets:
        name = a.get("name") or ""
        if name.startswith(f"mihomo-linux-{arch}-") and name.endswith(".gz"):
            best = a
            break
if best:
    print(best.get("name", "") or "")
    print(best.get("browser_download_url", "") or "")
PY
)"
    rm -f "$jf"
    name="$(printf '%s' "$out" | sed -n '1p')"
    url="$(printf '%s' "$out" | sed -n '2p')"
    if [ -z "$url" ]; then
        return 1
    fi
    STARMAN_MIHOMO_ASSET_NAME="$name"
    STARMAN_MIHOMO_DOWNLOAD_URL="$url"
    return 0
}

_starman_mihomo_fetch_latest_json() {
    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        return 1
    fi
    local prev="${STARMAN_HTTP_TIMEOUT:-}"
    STARMAN_HTTP_TIMEOUT="${STARMAN_CURL_MAX_TIME:-40}"
    starman_http_get_stdout "${STARMAN_MIHOMO_RELEASE_API}"
    local st=$?
    if [ -n "$prev" ]; then
        STARMAN_HTTP_TIMEOUT="$prev"
    else
        unset STARMAN_HTTP_TIMEOUT
    fi
    return "$st"
}

_starman_mihomo_install_binary() {
    local tmp
    tmp="$(mktemp)"
    local prev="${STARMAN_HTTP_TIMEOUT:-}"
    STARMAN_HTTP_TIMEOUT="${STARMAN_CURL_MAX_TIME:-120}"
    if ! starman_http_get "$STARMAN_MIHOMO_DOWNLOAD_URL" "$tmp"; then
        rm -f "$tmp"
        if [ -n "$prev" ]; then
            STARMAN_HTTP_TIMEOUT="$prev"
        else
            unset STARMAN_HTTP_TIMEOUT
        fi
        log_error "下载失败：$STARMAN_MIHOMO_DOWNLOAD_URL"
        return 1
    fi
    if [ -n "$prev" ]; then
        STARMAN_HTTP_TIMEOUT="$prev"
    else
        unset STARMAN_HTTP_TIMEOUT
    fi

    _starman_mihomo_sudo mkdir -p "$(dirname "$STARMAN_MIHOMO_BIN")"
    case "$STARMAN_MIHOMO_ASSET_NAME" in
        *.gz)
            if ! gunzip -c "$tmp" | _starman_mihomo_sudo tee "$STARMAN_MIHOMO_BIN" >/dev/null; then
                rm -f "$tmp"
                return 1
            fi
            ;;
        *)
            _starman_mihomo_sudo install -m 0755 "$tmp" "$STARMAN_MIHOMO_BIN"
            ;;
    esac
    rm -f "$tmp"
    _starman_mihomo_sudo chmod 0755 "$STARMAN_MIHOMO_BIN"
    if [ ! -x "$STARMAN_MIHOMO_BIN" ]; then
        log_error "二进制不可执行：$STARMAN_MIHOMO_BIN"
        return 1
    fi
    log_success "已安装 mihomo：$STARMAN_MIHOMO_BIN"
    return 0
}

_starman_mihomo_ensure_config() {
    local root
    root="$(_starman_mihomo_repo_root)"
    local tpl="${root}/templates/mihomo/config.yaml"
    _starman_mihomo_sudo mkdir -p "$STARMAN_MIHOMO_CONFIG_DIR"
    if [ ! -f "$STARMAN_MIHOMO_CONFIG" ]; then
        if [ -f "$tpl" ]; then
            log_info "写入占位配置：$STARMAN_MIHOMO_CONFIG"
            _starman_mihomo_sudo install -m 0644 "$tpl" "$STARMAN_MIHOMO_CONFIG"
        else
            log_warn "未找到模板 $tpl，写入最小占位 YAML"
            echo 'mode: rule' | _starman_mihomo_sudo tee "$STARMAN_MIHOMO_CONFIG" >/dev/null
            _starman_mihomo_sudo chmod 0644 "$STARMAN_MIHOMO_CONFIG"
        fi
    else
        log_info "已存在配置，跳过覆盖：$STARMAN_MIHOMO_CONFIG"
    fi
}

_starman_mihomo_write_systemd_unit() {
    local unit
    unit="$(mktemp)"
    {
        echo '[Unit]'
        echo 'Description=Mihomo (Starman install-script-mihomo)'
        echo 'After=network-online.target'
        echo 'Wants=network-online.target'
        echo ''
        echo '[Service]'
        echo 'Type=simple'
        echo "ExecStart=${STARMAN_MIHOMO_BIN} -d ${STARMAN_MIHOMO_CONFIG_DIR}"
        echo 'Restart=on-failure'
        echo ''
        echo '[Install]'
        echo 'WantedBy=multi-user.target'
    } >"$unit"
    _starman_mihomo_sudo install -m 0644 "$unit" "$STARMAN_MIHOMO_UNIT"
    rm -f "$unit"
    if command -v systemctl &>/dev/null; then
        _starman_mihomo_sudo systemctl daemon-reload
        log_info "已写入 systemd 单元（未 enable）：$STARMAN_MIHOMO_UNIT"
    else
        log_warn "未找到 systemctl，已写入单元文件但未 daemon-reload"
    fi
}

_starman_mihomo_print_offline_help() {
    log_error "无法从 GitHub 获取 mihomo，且未在约定路径找到可执行文件：$STARMAN_MIHOMO_BIN"
    echo "" >&2
    log_warn "手动安装指引："
    log_warn "  Release 页面：${STARMAN_MIHOMO_RELEASE_PAGE}"
    log_warn "  请下载与本机架构匹配的 linux 压缩包，解压后将二进制放到："
    log_warn "    ${STARMAN_MIHOMO_BIN}"
    log_warn "  从其它机器拷贝示例（在源机器上）："
    log_warn "    scp ./mihomo user@target:${STARMAN_MIHOMO_BIN}"
    log_warn "  然后重新运行本安装脚本并选择安装 mihomo。"
    echo "" >&2
}

# ============================================================================
# 主步骤
# ============================================================================

run_step_mihomo() {
    if [ -n "${STARMAN_SKIP_MIHOMO:-}" ]; then
        log_warn "已设置 STARMAN_SKIP_MIHOMO，跳过 mihomo 步骤"
        return 0
    fi

    log_info "mihomo（MetaCubeX）步骤…"

    if ! command -v sudo &>/dev/null && [ "$(id -u)" -ne 0 ]; then
        log_error "需要 sudo"
        return 1
    fi

    if ! declare -F tui_menu_create &>/dev/null; then
        log_warn "TUI 未加载，跳过 mihomo"
        return 3
    fi

    tui_clear
    tui_menu_create "mihomo（代理内核，安装至 ${STARMAN_MIHOMO_PREFIX}）"
    local mid="$TUI_LAST_MENU_ID"
    tui_menu_set_radio "$mid"
    tui_menu_add "$mid" "跳过（不安装 mihomo）" "skip" true
    tui_menu_add "$mid" "下载并安装（需可达 GitHub 或已手动放置二进制）" "install" false

    tui_menu_run "$mid"
    local result="${TUI_LAST_RESULT:-}"
    case "$result" in
        SELECTED:1) ;;
        *)
            log_warn "已跳过 mihomo 步骤"
            return 3
            ;;
    esac

    local arch
    arch="$(_starman_mihomo_go_arch)" || return 1

    local can_net=0
    if starman_probe_github; then
        can_net=1
        log_info "GitHub 探测成功（${STARMAN_GITHUB_PROBE_URL:-https://github.com}）"
    else
        log_warn "GitHub 探测失败（${STARMAN_GITHUB_PROBE_URL:-https://github.com}），将尝试 Release API / 离线路径"
    fi

    local installed=0
    if [ "$can_net" -eq 1 ] || [ -z "${STARMAN_MIHOMO_OFFLINE_ONLY:-}" ]; then
        local json
        if json="$(_starman_mihomo_fetch_latest_json)" && _starman_mihomo_pick_download_url "$arch" "$json"; then
            log_info "选用资源：$STARMAN_MIHOMO_ASSET_NAME"
            if _starman_mihomo_install_binary; then
                installed=1
            fi
        fi
    fi

    if [ "$installed" -eq 0 ] && [ -x "$STARMAN_MIHOMO_BIN" ]; then
        log_info "使用已存在的二进制：$STARMAN_MIHOMO_BIN"
        installed=1
    fi

    if [ "$installed" -eq 0 ]; then
        _starman_mihomo_print_offline_help
        return 1
    fi

    _starman_mihomo_ensure_config
    _starman_mihomo_write_systemd_unit
    log_warn "mihomo 服务未 enable；需要时请：sudo systemctl enable --now mihomo"
    log_success "mihomo 步骤完成"
    return 0
}
