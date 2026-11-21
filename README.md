# Claude Desktop SSH Unlock (3p 模式)

在**第三方推理模式**(用 `ANTHROPIC_BASE_URL` 网关而非 claude.ai 订阅,`deploymentMode:"3p"`)下,
Claude Desktop 的 Code 标签会**隐藏 SSH 远程环境**——环境下拉里只剩 Local。
这个插件把它**解锁并补全**,让你在桌面版里用 SSH 连自己的远程机器跑 Claude Code,
并**自动列出 `~/.ssh` 里保存的主机**。

> 这是一个 Claude Code 插件 + marketplace,可在多台电脑(macOS / Windows)复用。

---

## 安装(Claude Code 插件)

在任意机器的 Claude Code 里:

```
/plugin marketplace add yosu-ai/claude-desktop-ssh-unlock
/plugin install desktop-ssh-unlock@yosu-ai
```

装好后就有:

- 斜杠命令 **`/patch-desktop`** — 一键打/重打补丁并打开(自动识别 macOS/Windows)
- skill **`desktop-3p-ssh`** — 版本结构变动时定位新守卫/门控的说明
- 跨平台脚本 `scripts/patch-macos.sh` / `scripts/patch-windows.ps1`

> 也可以不装插件,直接 clone 本仓库跑 `plugins/desktop-ssh-unlock/scripts/` 里对应平台的脚本。

---

## 为什么能解锁(且需要补 4 处)

关键认知:3p 版**不是"运行时判断 3p 才隐藏 SSH"**,而是**编译期把 `sshApisAvailable` 常量折叠成 `false`**,
再由 DCE(死代码消除)连带削掉三处逻辑。但底层原生 IPC(`getSSHConfigs`、会话枚举 `sn.getAll` 等)**全部还在**,
读的是本机 `~/.ssh`、不经服务端——所以**纯客户端就能全解**,不碰后端、不需订阅:

| 补丁 | 位置 | 作用 |
|---|---|---|
| **A** 渲染守卫 `d&&(SSH组)` → `!0&&` | 选择器 chunk | SSH 组恒显(submenu / group 两布局) |
| **B** `sshApisAvailable` 的 `const t=!1` → `!0` | 视图模型 hook | 从根上把 SSH 能力置真 |
| **C** 被削空的 `useEffect(()=>{},…)` → `{r()}` | 视图模型 hook | 启动即读 `~/.ssh` 配置 |
| **D** `sshEnvItems` 的 `useMemo(()=>[])` → `map(sshConfigs)` | 视图模型 hook | **保存的 SSH 主机自动列出** |

压缩变量名逐版会变,脚本一律靠**语义稳定串**(i18n id `waUHa40VD6`、属性名 `sshApisAvailable`/`sshEnvItems`)
**动态发现**变量,跨版本稳健;改完用 `node --check` 验证语法。
3p 下 host 还会经 `CLAUDE_CODE_HOST_CREDS_FILE` 把网关凭据转发给远端,远端会话自动复用本地网关,远程机器无需额外配置。

> 只解锁 SSH:Cloud / Projects / Pools 各有独立守卫,与 SSH 互不相干,补 SSH **不会**误开付费 Cloud。

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
  - macOS: `bash scripts/patch-macos.sh`(`--force` 强制重打,`status` 只看版本对比)
  - Windows: `powershell -ExecutionPolicy Bypass -File scripts\patch-windows.ps1`

### 用

1. macOS 首启会弹**钥匙串授权** → 输 Mac 登录密码 → 点**"始终允许"**(ad-hoc 重签导致,每次重签一次性)。Windows 无此步。
2. Code 标签 → 底部环境下拉 → 出现 **SSH** 组(已列出 `~/.ssh` 里保存的主机)→ 选中开会话;
   或 **"Add SSH host…"** 填 `user@host`(或 `~/.ssh/config` 别名)新增。
3. 选中 SSH 环境 → 选远端目录 → 开会话。首次连接桌面版会自动在远端装 Claude Code。

---

## 平台差异

| | macOS | Windows |
|---|---|---|
| 补丁产物 | 复制成 `~/Applications/Claude-Patched.app` | **原地改**已安装目录 |
| 重签名 | 需要(逐层 ad-hoc,脚本自动做,**保留 virtualization 等权限**) | **不需要** |
| 钥匙串授权 | 首启需"始终允许" | 无 |
| 改的内容 | 同一份 ion-dist JS(可见性 + 数据层) | 同一份 |

---

## 每次 Claude 更新后

官方更新会覆盖补丁(mac 是新版覆盖来源、win 是新 `app-<版本>` 目录)。
**重跑 `/patch-desktop`(或脚本)一次即可**。macOS 版会先比对版本,没变就直接打开、不重打(`--force` 强制)。

---

## 已知限制 / 排错

- **Cowork 报 "Invalid installation / installation appears to be corrupted"**:
  重签若丢了 `com.apple.security.virtualization` 权限,Cowork 的本地虚拟机会判定安装损坏。
  本脚本重签时已保留该权限(主 app + `Claude Helper.app`);校验:
  `codesign -d --entitlements :- <app>` 应含 `com.apple.security.virtualization`。
- **看不到远端"已有"会话**:Claude Code 会话历史**按界面隔离**——桌面只显示它**自己开**的会话;
  在远端终端里直接 `claude` 开的历史**不同步**进桌面(桌面里 `/resume` 不可用)。
  要看远端历史须 SSH 进远端跑 `claude --resume`;换电脑同理(会话在**远端**、不在桌面本机注册表)。
- **脚本报"没有守卫被改动 / 主机列表未完全应用"**:Claude 新版结构变了。
  可见性锚点 `waUHa40VD6`、数据层锚点 `sshApisAvailable`/`sshEnvItems` 通常稳定;
  失效时在 Claude Code 里让 AI 参考 skill `desktop-3p-ssh` 重新分析。数据层失配时脚本会警告并退化为"可见 + 手动 Add SSH host"。

---

## 风险 / 免责

- 修改并(macOS)重签官方 app **可能违反 Anthropic ToS**,仅供本机个人使用,自担风险。
- ad-hoc 签名 + 每次更新需重打;数据层补丁(C/D)比可见性(A/B)更易随版本失配。
- 走网关做推理属**付费 API 用法**,不是订阅绕过。
- 每次官方更新后补丁失效,属预期。
