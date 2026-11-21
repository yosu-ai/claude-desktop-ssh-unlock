# Claude Desktop SSH Unlock (3p 模式)

在**第三方推理模式**(用 `ANTHROPIC_BASE_URL` 网关而非 claude.ai 订阅,`deploymentMode:"3p"`)下,
Claude Desktop 的 Code 标签会**隐藏 SSH 远程环境**,环境下拉里只剩 Local。
这个插件把它**解锁**,让你能在桌面版里用 SSH 连自己的远程机器跑 Claude Code。

> 这是一个 Claude Code 插件 + marketplace,可在多台电脑(macOS / Windows)复用。

---

## 为什么能解锁

隐藏纯粹发生在**远程 UI 层**——桌面版的 Web 界面(`resources/ion-dist/assets/v1/` 里的 JS)
用一个布尔守卫 `X && (SSH 环境组)` 把 SSH 组藏了,3p 下 `X` 为假。
但**后端 SSH 能力完整可用**,而且 3p 模式下 host 会通过 `CLAUDE_CODE_HOST_CREDS_FILE`
**把你的网关凭据转发给远端**,所以远端会话自动复用本地网关,远程机器无需额外配置。

补丁只做一件事:把那个守卫 `X&&` 改成 `!0&&`(恒真),SSH 组就恒显。
SSH 添加走桌面版原生的 "Add SSH host…" 对话框,完全可用。

---

## 安装(Claude Code 插件)

```
# 1. 把本仓库 push 到你的 GitHub(私有即可)
# 2. 在任意机器的 Claude Code 里:
/plugin marketplace add <你的github用户名>/claude-desktop-ssh-unlock
/plugin install desktop-ssh-unlock@yosu-ai
```

装好后就有:
- 斜杠命令 **`/patch-desktop`** — 一键打/重打补丁并打开(自动识别 macOS/Windows)
- skill **`desktop-3p-ssh`** — 版本结构变动时定位新守卫的说明
- 跨平台脚本 `scripts/patch-macos.sh` / `scripts/patch-windows.ps1`

> 也可以不装插件,直接跑 `scripts/` 里对应平台的脚本。

---

## 使用

### 前置:配好网关(让桌面版进 3p 模式)
`~/.claude/settings.json`(Windows: `%USERPROFILE%\.claude\settings.json`):
```json
{ "env": { "ANTHROPIC_BASE_URL": "https://你的网关", "ANTHROPIC_AUTH_TOKEN": "sk-..." } }
```

### 打补丁
- **Claude Code 里**:输 `/patch-desktop`
- **或手动**:
  - macOS: `bash scripts/patch-macos.sh`
  - Windows: `powershell -ExecutionPolicy Bypass -File scripts\patch-windows.ps1`

### 用
1. macOS 首启会弹**钥匙串授权** → 输 Mac 登录密码 → 点**"始终允许"**(ad-hoc 重签导致,一次性)。Windows 无此步。
2. Code 标签 → 底部环境下拉 → 出现 **SSH** 组 → **"Add SSH host…"** → 填 Name + SSH Host(`user@host` 或 `~/.ssh/config` 别名)→ 保存。
3. 选中该 SSH 环境 → 选远端目录 → 开会话。首次连接桌面版会自动在远端装 Claude Code。

---

## 平台差异

| | macOS | Windows |
|---|---|---|
| 补丁产物 | 复制成 `~/Applications/Claude-Patched.app` | **原地改**已安装目录 |
| 重签名 | 需要(逐层 ad-hoc,脚本自动做) | **不需要** |
| 钥匙串授权 | 首启需"始终允许" | 无 |
| 改的内容 | 同一份 ion-dist JS 守卫 | 同一份 |

---

## 每次 Claude 更新后

官方更新会覆盖补丁(mac 是新版覆盖来源、win 是新 `app-<版本>` 目录)。
**重新跑 `/patch-desktop`(或脚本)一次即可**。macOS 版会先比对版本,没变就直接打开、不重打。

---

## 脚本报「没有守卫被改动」怎么办

说明 Claude 新版把 UI 结构改了,锚点失效。SSH 组 Header 的 i18n id `waUHa40VD6` 通常稳定,
失效多半是外层结构调整。定位:
```
grep -l "Add SSH host" <ion-dist>/assets/v1/*.js         # 找含 SSH 选择器的 chunk
# 看该 chunk 里 id:"waUHa40VD6" 前紧邻的 X&& 守卫,把 X 改成 !0
```
或者在 Claude Code 里让 AI 参考 skill `desktop-3p-ssh` 重新分析。

---

## 风险 / 免责

- 修改并(macOS)重签官方 app **可能违反 Anthropic ToS**,仅供本机个人使用,自担风险。
- ad-hoc 签名 + 每次更新需重打;钥匙串每次重签需重新授权。
- 走网关做推理属**付费 API 用法**,不是订阅绕过。
- 每次官方更新后补丁失效,属预期。
