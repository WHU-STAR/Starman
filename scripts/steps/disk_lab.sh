#!/bin/bash
#
# 数据盘、fstab、lab 共享目录（OpenSpec: install-script-disk-lab）
#
# 用法：由项目根目录 install.sh source 后调用 run_step_disk_lab
#
# 依赖：scripts/lib/common.sh、tui.sh 已 source；基础工具含 lsblk/findmnt/blkid
#

# ============================================================================
# 路径
# ============================================================================

_starman_disk_steps_dir() {
    local _src="${BASH_SOURCE[0]}"
    cd "$(dirname "$_src")" && pwd
}

STARMAN_DISK_STEPS_DIR="$(_starman_disk_steps_dir)"

# ============================================================================
# sudo
# ============================================================================

_starman_disk_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ============================================================================
# 候选块设备（未挂载、非 swap、disk/part）
# ============================================================================

_disk_lab_root_source() {
    local src
    src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
    src="${src%%[*]}"
    case "$src" in
        UUID=* | LABEL=*)
            src="$(findmnt -n -o SOURCE --target / 2>/dev/null || true)"
            src="${src%%[*]}"
            ;;
    esac
    printf '%s' "$src"
}

_disk_lab_list_candidates() {
    local root_dev
    root_dev="$(_disk_lab_root_source)"

    # 使用 -P 键值输出，避免 MOUNTPOINT 为空时空格分列被 read 错拆（ext4 被当成挂载点）
    lsblk -dPpo NAME,TYPE,MOUNTPOINT,FSTYPE 2>/dev/null | while read -r line; do
        eval "$line" 2>/dev/null || continue
        [ -n "${MOUNTPOINT:-}" ] && continue
        case "${TYPE:-}" in
            disk | part) ;;
            *) continue ;;
        esac
        case "${FSTYPE:-}" in
            swap) continue ;;
        esac
        [ -b "${NAME:-}" ] || continue
        [ -n "$root_dev" ] && [ "${NAME:-}" = "$root_dev" ] && continue

        if [ "${TYPE:-}" = "disk" ]; then
            local nlines
            nlines="$(lsblk -nro NAME "${NAME:-}" 2>/dev/null | wc -l)"
            if [ "${nlines:-0}" -gt 1 ]; then
                continue
            fi
        fi

        echo "${NAME:-}"
    done
}

# ============================================================================
# lab 共享（需已有挂载点）
# ============================================================================

_disk_lab_setup_share() {
    local mp="$1"
    if [ -z "$mp" ] || [ ! -d "$mp" ]; then
        log_warn "无有效数据盘挂载点，跳过 lab 组与 share（与 OpenSpec：无盘时跳过一致）"
        return 0
    fi

    if ! mountpoint -q "$mp" 2>/dev/null && ! findmnt --target "$mp" &>/dev/null; then
        log_warn "路径未挂载：$mp，跳过 lab share"
        return 0
    fi

    if getent group lab &>/dev/null; then
        log_info "组 lab 已存在"
    else
        log_info "创建组 lab…"
        _starman_disk_sudo groupadd lab || {
            log_error "groupadd lab 失败"
            return 1
        }
    fi

    local share="${mp}/share"
    log_info "创建共享目录 $share（2775 + setgid）…"
    _starman_disk_sudo mkdir -p "$share"
    _starman_disk_sudo chgrp lab "$share"
    _starman_disk_sudo chmod 2775 "$share"
    log_success "lab 共享目录已就绪：$share"
}

# ============================================================================
# fstab + mount
# ============================================================================

_disk_lab_backup_fstab() {
    local stamp
    stamp="$(date +%Y%m%d%H%M%S)"
    if [ -f /etc/fstab ]; then
        _starman_disk_sudo cp -a /etc/fstab "/etc/fstab.bak.${stamp}"
        log_info "已备份 /etc/fstab -> /etc/fstab.bak.${stamp}"
    fi
}

_disk_lab_append_fstab() {
    local uuid="$1"
    local mp="$2"
    local fst="$3"
    if [ -f /etc/fstab ] && _starman_disk_sudo grep -qF "UUID=${uuid}" /etc/fstab 2>/dev/null; then
        log_error "fstab 中已存在该 UUID，拒绝重复写入"
        return 1
    fi
    local tmp
    tmp="$(mktemp)"
    _starman_disk_sudo cat /etc/fstab 2>/dev/null >>"$tmp" || true
    {
        echo ""
        echo "# Starman data disk (install-script-disk-lab)"
        echo "UUID=${uuid}  ${mp}  ${fst}  defaults,nofail  0  2"
    } >>"$tmp"
    _starman_disk_sudo install -m 0644 "$tmp" /etc/fstab
    rm -f "$tmp"
}

# ============================================================================
# 主步骤
# ============================================================================

run_step_disk_lab() {
    if [ -n "${STARMAN_SKIP_DISK_LAB:-}" ]; then
        log_warn "已设置 STARMAN_SKIP_DISK_LAB，跳过数据盘与 lab 步骤"
        return 0
    fi

    log_info "数据盘与 lab 共享步骤…"

    if ! command -v lsblk &>/dev/null || ! command -v findmnt &>/dev/null; then
        log_error "需要 lsblk/findmnt（util-linux），请先完成基础包安装步骤"
        return 1
    fi

    if ! declare -F tui_menu_create &>/dev/null; then
        log_warn "TUI 未加载，跳过数据盘与 lab"
        return 0
    fi

    tui_clear
    tui_menu_create "数据盘与 lab 共享"
    local mid="$TUI_LAST_MENU_ID"
    tui_menu_set_radio "$mid"
    tui_menu_add "$mid" "跳过（不格式化、不配置 lab share）" "skip" true
    tui_menu_add "$mid" "配置未挂载数据盘（格式化、fstab、lab/share）" "setup" false

    tui_menu_run "$mid"
    local result="${TUI_LAST_RESULT:-}"
    case "$result" in
        SELECTED:1) ;;
        *)
            log_warn "已跳过数据盘；无挂载点，不创建 lab share"
            return 0
            ;;
    esac

    local candidates
    candidates="$(_disk_lab_list_candidates)"
    if [ -z "$candidates" ]; then
        log_warn "未检测到未挂载的候选块设备，跳过格式化与 lab share"
        return 0
    fi

    local -a devs=()
    while IFS= read -r d; do
        [ -n "$d" ] && devs+=("$d")
    done <<<"$candidates"

    local dev
    dev="$(try_fzf_or_menu "选择要格式化的块设备" "${devs[@]}")"
    if [ -z "$dev" ]; then
        log_warn "未选择设备，已取消"
        return 0
    fi

    local fstype
    fstype="$(try_fzf_or_menu "文件系统类型" "ext4" "xfs")"
    [ -z "$fstype" ] && fstype="ext4"

    local default_mp="/data"
    local mpoint
    read -r -p "挂载点 [${default_mp}]: " mpoint
    mpoint="${mpoint:-$default_mp}"
    if [[ "$mpoint" != /* ]]; then
        log_error "挂载点须为绝对路径"
        return 1
    fi

    echo ""
    log_warn "即将格式化：$dev → $fstype，挂载到 $mpoint（破坏性操作）"
    local confirm
    read -r -p "确认请输入大写 YES: " confirm
    if [ "$confirm" != "YES" ]; then
        log_warn "未确认，已取消数据盘步骤"
        return 0
    fi

    case "$fstype" in
        ext4)
            _starman_disk_sudo mkfs.ext4 -F "$dev" || {
                log_error "mkfs.ext4 失败"
                return 1
            }
            ;;
        xfs)
            _starman_disk_sudo mkfs.xfs -f "$dev" || {
                log_error "mkfs.xfs 失败"
                return 1
            }
            ;;
        *)
            log_error "不支持的文件系统：$fstype（首版仅 ext4/xfs）"
            return 1
            ;;
    esac

    local uuid
    uuid="$(blkid -s UUID -o value "$dev" 2>/dev/null)"
    if [ -z "$uuid" ]; then
        log_error "无法读取 UUID：$dev"
        return 1
    fi

    _starman_disk_sudo mkdir -p "$mpoint" || return 1
    _disk_lab_backup_fstab
    _disk_lab_append_fstab "$uuid" "$mpoint" "$fstype"

    if _starman_disk_sudo mount "$mpoint"; then
        log_success "已挂载 $mpoint"
    else
        log_error "mount $mpoint 失败，请检查 fstab 与设备"
        return 1
    fi

    if ! mountpoint -q "$mpoint" 2>/dev/null && ! findmnt --target "$mpoint" &>/dev/null; then
        log_error "未验证到挂载点：$mpoint（mountpoint/findmnt）"
        return 1
    fi
    log_success "挂载点校验通过：$mpoint"

    _disk_lab_setup_share "$mpoint"
    log_success "数据盘与 lab 步骤完成"
}
