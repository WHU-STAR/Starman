# Starman: STAR 实验室服务器管理系统

## 快速安装

### 在线安装（推荐）

下载安装脚本后执行（需要交互式终端，不支持管道模式）：

```bash
# Gitee（国内推荐）
curl -fsSL -o /tmp/bootstrap.sh https://gitee.com/ajgamma/starman/raw/master/installers/bootstrap.sh && bash /tmp/bootstrap.sh

# 或使用 wget
wget -qO /tmp/bootstrap.sh https://gitee.com/ajgamma/starman/raw/master/installers/bootstrap.sh && bash /tmp/bootstrap.sh

# GitHub（TODO: 待配置）
# curl -fsSL -o /tmp/bootstrap.sh https://github.com/ajgamma/starman/raw/main/installers/bootstrap.sh && bash /tmp/bootstrap.sh
```

### 离线安装

无法访问互联网的设备，请参考 [离线安装指引](docs/OFFLINE_INSTALL.md)。

## 功能特性

### TUI 交互式菜单

项目提供纯 Bash 实现的 TUI 菜单库 (`scripts/lib/tui.sh`)，支持：

- **勾选式选项**：空格键切换勾选状态
- **配置式选项**：←→/hl 键切换预定义值（时区、语言等）

**示例**：

```bash
source scripts/lib/tui.sh

menu_id=$(tui_menu_create "系统配置")

# 勾选式选项
tui_menu_add "$menu_id" "Docker" "docker" true

# 配置式选项
tui_menu_add "$menu_id" "时区" "timezone"
tui_menu_set_options "$menu_id" 1 "Asia/Shanghai" "America/New_York" "Europe/London"

# 运行并获取结果
result=$(tui_menu_run "$menu_id")

# 解析结果
checked=$(tui_parse_result "$result" "CHECKED")
values=$(tui_parse_result "$result" "VALUE")
```

完整示例参考 `examples/tui-env-demo.sh`。

### 系统管理

- 快速配置系统环境
- 自动化挂载数据盘
- 自动化安装常用软件
- 生成系统级管理员工具

详细设计文档请参阅 [开发设计文档](openspec/DEV_FLOW.md)。

## 开发流程

本项目使用 OpenSpec 规范驱动开发流程。详细的开发计划、依赖关系和里程碑请参阅：

- [开发流程设计](openspec/DEV_FLOW.md) - 完整的开发路线图
- [OpenSpec 配置](openspec/config.yaml) - 项目规范配置

## 测试

使用虚拟机进行自动化测试：

```bash
# Ubuntu 22.04 (apt 系)
tmux attach -t vm-ubuntu

# CentOS 7 (yum 系)
tmux attach -t vm-centos
```

## 许可证

GPL License
