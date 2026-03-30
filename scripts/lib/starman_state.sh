#!/bin/bash
#
# 装机状态持久化（OpenSpec: install-script-mihomo 等）
#
# 用法：由 install.sh 在 source common/tui 之后 source 本文件；勿单独直接执行。
#
# 默认：/etc/starman/install-state.json（须 sudo 写入；可用 STARMAN_STATE_FILE 覆盖）
# 依赖：python3（用于读写 JSON）；若不存在则续跑功能降级为「始终完整执行」
#

STARMAN_STATE_FILE="${STARMAN_STATE_FILE:-/etc/starman/install-state.json}"

_starman_state_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

starman_state_python_ok() {
    command -v python3 &>/dev/null
}

# 返回 0 表示该步骤在状态中标记为已完成
starman_state_step_done() {
    local step="$1"
    if ! starman_state_python_ok; then
        return 1
    fi
    if [ ! -f "$STARMAN_STATE_FILE" ]; then
        return 1
    fi
    _starman_state_sudo test -r "$STARMAN_STATE_FILE" || return 1
    _starman_state_sudo python3 - "$STARMAN_STATE_FILE" "$step" <<'PY'
import json, sys
path, step = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        d = json.load(f)
    steps = d.get("steps") or {}
    sys.exit(0 if steps.get(step) is True else 1)
except Exception:
    sys.exit(1)
PY
}

starman_state_mark_step() {
    local step="$1"
    if ! starman_state_python_ok; then
        log_warn "未找到 python3，跳过写入装机状态（${step}）"
        return 0
    fi
    if ! command -v sudo &>/dev/null && [ "$(id -u)" -ne 0 ]; then
        log_warn "无法 sudo，跳过写入装机状态"
        return 0
    fi
    _starman_state_sudo mkdir -p "$(dirname "$STARMAN_STATE_FILE")" 2>/dev/null || true
    _starman_state_sudo python3 - "$STARMAN_STATE_FILE" "$step" <<'PY'
import json, os, sys
from datetime import datetime, timezone

path, step = sys.argv[1], sys.argv[2]
data = {"version": 1, "steps": {}, "options": {}, "updated": None}
if os.path.isfile(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        bak = path + ".bad." + datetime.now().strftime("%Y%m%d%H%M%S")
        try:
            os.rename(path, bak)
        except OSError:
            pass
data.setdefault("steps", {})[step] = True
data.setdefault("options", {})
data["updated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
}

starman_state_clear() {
    if ! starman_state_python_ok; then
        return 0
    fi
    _starman_state_sudo rm -f "$STARMAN_STATE_FILE" 2>/dev/null || true
}

# 若存在任一已完成步骤则返回 0
starman_state_has_progress() {
    if ! starman_state_python_ok || [ ! -f "$STARMAN_STATE_FILE" ]; then
        return 1
    fi
    _starman_state_sudo test -r "$STARMAN_STATE_FILE" || return 1
    _starman_state_sudo python3 - "$STARMAN_STATE_FILE" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        d = json.load(f)
    steps = d.get("steps") or {}
    sys.exit(0 if any(steps.values()) else 1)
except Exception:
    sys.exit(1)
PY
}

# 在 TUI 前调用：设置 STARMAN_INSTALL_FLOW=full|resume（第三项为占位说明后仍续跑）
starman_install_flow_prompt() {
    STARMAN_INSTALL_FLOW="${STARMAN_INSTALL_FLOW:-full}"

    if ! starman_state_python_ok; then
        log_warn "未找到 python3，装机状态续跑不可用，将执行完整步骤"
        STARMAN_INSTALL_FLOW=full
        return 0
    fi

    if ! starman_state_has_progress; then
        STARMAN_INSTALL_FLOW=full
        return 0
    fi

    if ! declare -F tui_menu_create &>/dev/null; then
        STARMAN_INSTALL_FLOW=full
        return 0
    fi

    tui_clear
    tui_menu_create "装机流程（检测到上次进度：${STARMAN_STATE_FILE}）"
    local mid="$TUI_LAST_MENU_ID"
    tui_menu_set_radio "$mid"
    tui_menu_add "$mid" "完整安装（清空状态记录，重新执行各步骤）" "full" true
    tui_menu_add "$mid" "续跑（跳过已在状态中标记为完成的步骤）" "resume" false
    tui_menu_add "$mid" "二次启动与扩展（NFS / Clash 等，当前为占位说明）" "secondary" false

    tui_menu_run "$mid"
    local result="${TUI_LAST_RESULT:-}"

    case "$result" in
        SELECTED:0)
            starman_state_clear
            STARMAN_INSTALL_FLOW=full
            log_info "已清空装机状态，将完整执行各步骤"
            ;;
        SELECTED:1)
            STARMAN_INSTALL_FLOW=resume
            log_info "续跑模式：将跳过已完成步骤"
            ;;
        SELECTED:2)
            log_warn "[占位] NFS 服务端、Clash 兼容与二次启动编排尚未实现，详见 OpenSpec install-script-mihomo / 后续变更"
            STARMAN_INSTALL_FLOW=resume
            ;;
        *)
            STARMAN_INSTALL_FLOW=full
            ;;
    esac
}

# 包装：续跑模式下跳过已完成步骤
# 子步骤返回 0：视为完成并写入状态；返回 3：用户跳过/不写入状态；其它：失败
# 注意：install.sh 使用 set -e；若此处直接 "$@" 且步骤返回 3，会在捕获 rc 之前触发 errexit 并整脚本退出。
# 故先用 set +e 执行步骤，再恢复 -e。
starman_run_step_maybe_skip() {
    local step_name="$1"
    shift
    if [ "${STARMAN_INSTALL_FLOW:-full}" = "resume" ] && starman_state_step_done "$step_name"; then
        log_info "续跑：跳过已完成步骤「${step_name}」"
        return 0
    fi
    set +e
    "$@"
    local rc=$?
    set -e
    if [ "$rc" -eq 3 ]; then
        return 0
    fi
    if [ "$rc" -eq 0 ]; then
        starman_state_mark_step "$step_name"
        return 0
    fi
    return "$rc"
}
