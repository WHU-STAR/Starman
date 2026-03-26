# VM 测试框架使用文档

## 快速开始

### 1. 设置测试环境

运行一键 setup 脚本：

```bash
tests/vm-test/setup.sh
```

此脚本会：
- 检查依赖（QEMU、tmux、socat）
- 检查 KVM 模块
- 创建目录结构
- 引导下载 cloud image
- 生成 SSH Key（可选）

### 2. 运行测试

```bash
# 运行所有测试
tests/vm-test/scripts/test-harness.sh run-all

# 运行单个测试
tests/vm-test/scripts/test-harness.sh run-test root_user_guide
```

## 架构组件

### vm-manager.sh - VM 生命周期管理

```bash
source tests/vm-test/scripts/vm-manager.sh

# 创建 VM
vm_create "tests/vm-test/images/ubuntu-cloud.img"

# 启动 VM
vm_start

# 创建快照
vm_snapshot_create "clean"

# 恢复快照
vm_snapshot_restore "clean"

# 执行命令
vm_exec "echo hello"

# 上传文件
vm_upload ./local.sh /tmp/remote.sh

# 停止 VM
vm_stop

# 销毁 VM
vm_destroy
```

### tmux-driver.sh - Tmux TUI 驱动

```bash
source tests/vm-test/scripts/tmux-driver.sh

# 创建会话
tmux_session_create "test" "./install.sh"

# 发送按键
tmux_send_key "test" "j"        # 下移
tmux_send_key "test" "Enter"    # 确认
tmux_send_key "test" "Space"    # 空格
tmux_send_key "test" "C-c"      # Ctrl+C

# 捕获内容
tmux_capture "test"             # 保留 ANSI 序列
tmux_capture_plain "test"       # 纯文本

# 解析 TUI 状态
tui_get_menu_items "test"       # 获取菜单项
tui_get_cursor_position "test"  # 获取光标位置
tui_get_checked_items "test"    # 获取已勾选项
```

### test-harness.sh - 测试执行器

```bash
source tests/vm-test/scripts/test-harness.sh

# 初始化
test_init

# 运行测试
run_test root_user_guide
run_all_tests

# 断言
assert_contains "安全警告"
assert_matches ".*root.*"
assert_tui_menu_count 3

# 人工介入
require_manual "请确认 TUI 颜色是否正确"

# 生成报告
generate_test_report /tmp/report.txt
```

## 编写测试场景

测试场景文件位于 `tests/vm-test/scenarios/` 目录下。

### 测试函数命名

```bash
test_<场景名称>() {
    # 设置
    # 执行
    # 断言
    # 清理
}
```

### 示例

```bash
#!/bin/bash

test_root_user_guide() {
    # 恢复干净快照
    vm_snapshot_restore "clean"

    # 创建 tmux 会话运行安装脚本
    tmux_session_create "test" "./install.sh"
    sleep 2

    # 断言：显示 root 用户警告
    assert_contains "安全警告"

    # 操作：选择"新建 sudo 用户"
    tmux_send_key "test" "Enter"

    # 断言：提示输入用户名
    assert_contains "请输入新用户名"

    # 操作：输入用户名
    tmux_send_string "test" "testuser"
    tmux_send_key "test" "Enter"

    # 断言：用户创建成功
    assert_contains "用户 testuser 创建成功"

    # 清理
    tmux_session_destroy "test"
}
```

## 人工介入

当测试遇到无法自动化的场景时，会使用 `notify-send` 发送桌面通知：

```bash
notify-send -u critical -t 0 "VM TUI 测试 - 需要人工介入" "操作说明..."
```

用户完成手动操作后，创建标记文件继续测试：

```bash
touch /tmp/vm-test-human-done
```

测试框架会轮询检测标记文件，检测到后自动继续。

## 依赖要求

| 依赖 | 用途 | 安装命令 |
|------|------|----------|
| QEMU | VM 虚拟化 | `apt-get install qemu-kvm` |
| tmux | TUI 测试驱动 | `apt-get install tmux` |
| socat | 串行控制台通信 | `apt-get install socat` |
| notify-send | 桌面通知 | `apt-get install libnotify-bin` |

## 故障排查

### VM 启动失败

检查 KVM 模块是否加载：

```bash
lsmod | grep kvm
```

未加载则手动加载：

```bash
sudo modprobe kvm_intel  # Intel CPU
sudo modprobe kvm_amd    # AMD CPU
```

### SSH 连接失败

确保 SSH Key 已生成并配置：

```bash
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ''
```

### 桌面通知不显示

检查 notify-send 是否可用：

```bash
notify-send "测试通知"
```

不可用则安装：

```bash
sudo apt-get install libnotify-bin
```

## 清理

测试完成后清理资源：

```bash
# 清理 tmux 会话
tmux_session_cleanup

# 停止 VM
vm_stop

# 销毁 VM（删除磁盘镜像）
vm_destroy
```
