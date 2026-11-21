---
name: desktop-3p-ssh
description: 解锁 Claude Desktop 第三方推理(3p/网关)模式下被隐藏的 SSH 远程环境。当用户提到"Claude 桌面版看不到/用不了 SSH"、"3p 解锁 SSH"、"给 Claude Desktop 打补丁"、"更新后重打补丁"时使用。
---

# 解锁 Claude Desktop 3p 模式下的 SSH 环境

## 原理
Claude Desktop 在第三方推理模式(`deploymentMode:"3p"`,即用 `ANTHROPIC_BASE_URL` 网关而非 claude.ai 订阅)下,
在 Code 标签环境下拉里**隐藏 SSH 远程环境**。关键:这**不是运行时判断 `3p` 才隐藏**——而是 3p 构建在**编译期
把 `sshApisAvailable` 常量折叠成 `false`**,再由 DCE(死代码消除)连带削掉三处:①SSH 组可见性守卫 ②SSH 配置
拉取 `useEffect` ③`sshEnvItems` 列表映射。底层原生 IPC(`getSSHConfigs`/`setSSHConfigs`/`listSSHDirectory`、
会话枚举 `sn.getAll`)**全部还在**,读的是本机 `~/.ssh`,不经服务端——所以纯客户端可全解,无需订阅/后端。
3p 下 host 还会经 `CLAUDE_CODE_HOST_CREDS_FILE` 把网关凭据转发给远端,远端会话自动复用本地网关,fsn 等无需额外配置。

补丁分四处(都在 `Contents/Resources/ion-dist/assets/v1/` 的 chunk 里,`c5610fbe3*`=选择器、`c06173196*`=视图模型 hook):
- **可见性**:A 渲染守卫 `d&&(..children:LBL..)` 改 `!0&&`(`LBL` 是 SSH 标签变量,def `LBL=..jsx(..{defaultMessage:"SSH",id:"waUHa40VD6"})`;submenu/group 两布局各一处);B 根标志 `sshApisAvailable` 的 `const t=!1` 改 `!0`。
- **主机列表**:C 把被削空的 `useEffect(()=>{},[t,r])` 恢复成 `useEffect(()=>{r()},…)`(启动即拉配置);D 把 `sshEnvItems` 的 `useMemo(()=>[])` 重建成 `map(sshConfigs)`(变量名全动态发现)。
- **会话列表自愈**:远程 SSH 会话枚举本就没门控;只要 SSH 主机能选中,其会话就从真实 `sn.getAll()` 渲染,无需单独补丁。

> 只解锁 SSH:Cloud/Projects/Pools 各有独立守卫(`canCreateCloudEnv`/`projectsSectionVisible`/`poolsSectionVisible`),
> 与 SSH 互不相干,补 SSH **不会**误开付费 Cloud;那些后端真需订阅。

## 应用
- macOS: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/patch-macos.sh"`(改 ion-dist + ad-hoc 重签 + 打开)
- Windows: `powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/patch-windows.ps1"`(改 ion-dist,无需重签)

用补丁版:Code 标签 → 环境下拉 → **SSH**(已列出 `~/.ssh` 里保存的主机)→ 选中开会话;或 "Add SSH host…" 填 `user@host`(或 ~/.ssh/config 别名)新增。选中 SSH 主机后,其历史会话会正常出现在列表里。

## 版本适配(脚本报"没有守卫被改动"或"主机列表未完全应用"时)
锚点均为**语义稳定串**,不依赖压缩变量名(变量名每版都变,脚本一律动态发现):
- 可见性 A:i18n id `waUHa40VD6`(SSH 组标签)→ 反查标签变量 `LBL` → 改 `<guard>&&..jsxs(..children:LBL..)`(body 用 `[^&]` 界定不越过兄弟守卫,`(?<![!\w$])` 防反转成 `!!0`;submenu/group 两布局各一)。
- 可见性 B:属性名 `sshApisAvailable:..,refresh:..}=function(){const X=!1,` → `X=!0`。
- 主机列表 C:`return ..useEffect(()=>{},[t,r]),{sshConfigs:` 的空 effect → 补 `r()`。
- 主机列表 D:`sshEnvItems:<Xn>` 反查列表变量 → 把 `<Xn>=..useMemo(()=>[],[..])` 重建为 `map(sshConfigs)`;所需 `sshConfigs`/`currentSshConfig`/选择fn/`配置→envid` 均从稳定串动态发现(`{sshConfigs:.. }`、`currentSshConfig:..`、`onSshConfigsChanged` 里的 `Rs(ae(e))`)。参照未被削的兄弟 `wslEnvItems` 的 `map` 形状。
若手工重定位:在含 `Add SSH host` 的 chunk 搜 `waUHa40VD6`(可见性)、在含 `sshApisAvailable` 的 chunk 搜该属性名(数据层)。
改完**务必 `node --check <chunk>.js` 验证语法**(D 是重建代码,最易出错);再看补丁版能否列出主机、选中后会话是否出现。

## 已知点 / 风险
- macOS ad-hoc 重签 → 首启弹钥匙串,点"始终允许"(每次重签都要);Windows 无此问题。
- **重签必须保留 `com.apple.security.virtualization` 等硬化运行时权限**:官方 app 用 Developer ID 签、带 virtualization(Cowork 本地 VM 用)、camera/mic/usb 等;若重签只给最小 entitlements,**Cowork 会报 "Invalid installation / installation appears to be corrupted"**(错误分支 `virtualization_entitlement_missing`)。脚本已把这些 `com.apple.security.*` 权限补进重签 plist(主 app + `Claude Helper.app` 都要),并去掉 team 绑定项(`application-identifier`/`keychain-access-groups`/`developer.team-identifier`,ad-hoc 下 team 不匹配会挡启动)。校验:`codesign -d --entitlements :- <app>` 应含 `com.apple.security.virtualization`。
- 每次官方更新覆盖补丁,需重跑;数据层(C/D)比可见性(A/B)更易随 hook 重构失配,失配时脚本会警告,可退化为 A/B + 手动 "Add SSH host…"。
- D 是**重建被 DCE 削掉的逻辑**(非翻布尔),脚本已用 `node --check` 思路保证语法,但形状若变需按兄弟 `wslEnvItems` 重新对齐。
- SSH **远端会话枚举**桌面版没实现(会话历史按界面隔离):桌面只显示自己开的会话,远端 `~/.claude/projects/` 里的历史看不到——这不是 3p 门控、也补不了,须 SSH 进远端 `claude --resume`。
- 改并(mac)重签官方 app 可能违反 Anthropic ToS,仅本机个人用;走网关是付费 API 用法,非订阅绕过。
