# VM TUI 测试框架

基于 KVM/QEMU 和 tmux 的自动化 TUI 测试框架，用于测试 starman 安装脚本的交互式界面。

## 快速开始

```bash
# 一键设置测试环境
tests/vm-test/setup.sh

# 运行所有测试
tests/vm-test/scripts/test-harness.sh run-all

# 运行单个测试
tests/vm-test/scripts/test-harness.sh run-test root_user_guide
```

## 目录结构

```
tests/vm-test/
├── README.md              # 本文档
├── scripts/               # 测试框架脚本
│   ├── vm-manager.sh      # VM 生命周期管理
│   ├── tmux-driver.sh     # Tmux TUI 驱动
│   └── test-harness.sh    # 测试执行器
└── scenarios/             # 测试场景
    ├── root_user_guide.sh
    ├── tui_menu_navigation.sh
    └── user_creation_flow.sh
```

## 架构设计

### VM 管理层 (vm-manager.sh)

- `vm_create`: 创建 KVM/QEMU VM 实例
- `vm_start` / `vm_stop` / `vm_destroy`: VM 生命周期管理
- `vm_snapshot_create` / `vm_snapshot_restore`: 快照管理
- `vm_exec` / `vm_exec_file`: 在 VM 内执行命令
- `vm_upload` / `vm_download`: 文件传输

### Tmux 驱动层 (tmux-driver.sh)

- `tmux_session_create`: 创建后台 tmux 会话
- `tmux_send_key`: 发送按键事件（支持特殊键映射）
- `tmux_capture` / `tmux_capture_plain`: 捕获窗口内容
- `tui_get_menu_items`: 解析 TUI 菜单项
- `ansi_strip`: 去除 ANSI 转义序列

### 测试执行层 (test-harness.sh)

- `test_*`: 测试场景函数
- `assert_contains` / `assert_matches`: 断言函数
- `run_test` / `run_all_tests`: 测试执行器
- `require_manual`: 人工介入点（notify-send 通知）

## 人工介入

当测试遇到无法自动化的场景时，会发送桌面通知：

```bash
notify-send -u critical -t 0 "VM TUI 测试 - 需要人工介入" "..."
```

用户完成手动操作后，创建标记文件继续测试：

```bash
touch /tmp/vm-test-human-done
```

## 依赖要求

- KVM/QEMU (`qemu-system-x86_64`)
- tmux
- notify-send (libnotify)
- cloud-utils (可选，用于 VM 镜像准备)

## 测试示例

```bash
# 测试 root 用户引导流程
test_root_user_guide() {
    vm_snapshot_restore "clean"
    tmux_session_create "test" "./install.sh"

    assert_contains "安全警告"
    tmux_send_key "Enter"
    assert_contains "请输入新用户名"
    tmux_send_key "testuser"
    tmux_send_key "Enter"
    assert_contains "用户 testuser 创建成功"

    tmux_session_destroy "test"
}
```
