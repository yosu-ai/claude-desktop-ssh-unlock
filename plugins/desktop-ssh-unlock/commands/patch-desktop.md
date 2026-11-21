---
description: 给 Claude Desktop 打/重打 SSH 补丁(3p 模式解锁 SSH 环境),并打开(macOS)
allowed-tools: Bash, Bash(open:*)
---
根据当前系统解锁 Claude Desktop 3p 模式下的 SSH 环境:

- **macOS**(`uname` = Darwin):运行 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/patch-macos.sh"`。
  它会:对比官方 Claude.app 版本,若更新过则重打补丁+ad-hoc 重签并打开,否则直接打开补丁版。
  完成后提醒:若这次重打了补丁,首启会弹钥匙串授权 —— 输 Mac 密码点"始终允许"(一次性)。

- **Windows**:PowerShell 补丁脚本在 `${CLAUDE_PLUGIN_ROOT}/scripts/patch-windows.ps1`。
  告诉用户完全退出 Claude 后运行:`powershell -ExecutionPolicy Bypass -File "<该路径>"`,再重启 Claude。
  (Windows 无需重签,改完重启即可。)

若脚本报"没有守卫被改动",说明 Claude 新版 UI 结构变了,需重新定位 SSH 组守卫(见本插件 skill `desktop-3p-ssh`),提示用户可让你重新分析。

这是一键命令,不要做多余的事;执行后简要报告结果即可。
