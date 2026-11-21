#!/bin/bash
# macOS: 解锁 Claude Desktop 3p 模式下的 SSH 环境。补丁 ion-dist 守卫 + ad-hoc 重签。
# 用法: patch-macos.sh [--force|status] [源.app] [目标.app]
set -euo pipefail
MODE="${1:-run}"; case "$MODE" in --force|status) shift;; run|"") MODE="run";; *) MODE="run";; esac
SRC="${1:-/Applications/Claude.app}"
DST="${2:-$HOME/Applications/Claude-Patched.app}"
MARK="$HOME/Applications/.claude-patched.version"
ver(){ /usr/bin/defaults read "$1/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?"; }
[ -d "$SRC" ] || { echo "❌ 未找到官方 $SRC"; exit 1; }
SRCVER="$(ver "$SRC")"; DSTVER="$( [ -f "$MARK" ] && cat "$MARK" || echo none )"

if [ "$MODE" = status ]; then
  echo "官方版: $SRCVER  |  补丁版: 基于 $DSTVER  |  $( [ "$SRCVER" = "$DSTVER" ] && echo '✓最新' || echo '⚠需重打')"; exit 0
fi

need=0; [ ! -d "$DST" ] && need=1; [ "$SRCVER" != "$DSTVER" ] && need=1; [ "$MODE" = --force ] && need=1
if [ "$need" = 0 ]; then echo "✓ 补丁版已最新(基于 $SRCVER),直接打开"; open "$DST"; exit 0; fi

echo "▶ 复制 $SRC -> $DST"; rm -rf "$DST"; ditto "$SRC" "$DST"; xattr -cr "$DST" 2>/dev/null || true
ION="$DST/Contents/Resources/ion-dist/assets/v1"
[ -d "$ION" ] || { echo "❌ 未找到 ion-dist(版本结构可能已变)"; exit 1; }
echo "▶ 补丁 SSH 环境(可见性 + 主机列表自动填充)"
python3 - "$ION" <<'PY'
import re,sys,glob,os
# 3p 版并非"运行时判断 3p 才隐藏 SSH",而是编译期把 sshApisAvailable 常量折叠成 false,
# DCE 连带削掉:①SSH 组可见性守卫 ②SSH 配置拉取 effect ③sshEnvItems 列表映射。
# 底层原生 IPC(getSSHConfigs/listSSHDirectory)仍在,故纯客户端可全解:
#   可见性 = A(渲染守卫)+ B(根标志翻转);主机列表 = C(恢复拉取)+ D(重建映射)。
ion=sys.argv[1]; MID="waUHa40VD6"  # SSH 组 i18n id(跨版本最稳,作锚点)
g=r'(?:\([^()]{0,80}\)|[\w$]+)'
old_body=(r'(\w+\.jsxs\(\w+\.Fragment,\{children:\[\w+\.jsx\(\w+\.Separator,\{\}\),'
      r'\w+\.jsxs\(\w+\.Group,\{children:\[\w+\.jsx\(\w+\.Header,\{children:'
      r'\w+\.jsx\(\w+,\{defaultMessage:"[^"]*",id:"'+MID+r'")')
old_pat=re.compile('('+g+')&&('+old_body+')')
vis=0; host=0
for f in glob.glob(os.path.join(ion,"*.js")):
    s=open(f,encoding="utf-8",errors="surrogatepass").read(); o=s; fv=0; fh=0
    # A) 可见性:SSH 组渲染守卫(标签抽成变量 LBL,submenu/group 两布局各一处)。
    #    body 用 [^&] 禁跨越兄弟守卫的 &&;(?<![!\w$]) 防重复运行反转成 !!0。
    if MID in s:
        mm=re.search(r'([\w$]+)=\w+\.jsx\(\w+,\{defaultMessage:"[^"]*",id:"'+MID+r'"\}\)', s)
        if mm:
            LBL=re.escape(mm.group(1))
            s,k=re.subn(r'(?<![!\w$])([\w$]+)&&(\w+\.jsxs\([^&]{1,300}?children:'+LBL+r'\})', r'!0&&\2', s); fv+=k
        s,k=old_pat.subn(r'!0&&\2', s); fv+=k
    # B) 可见性根标志:sshApisAvailable 的 const t=!1 -> !0(锚定语义属性名,最稳)。
    s,k=re.subn(r'(sshApisAvailable:\w+,refresh:\w+\}=function\(\)\{const )(\w+)=!1,', r'\g<1>\g<2>=!0,', s); fv+=k
    # C) 主机列表自动加载:被削空的 useEffect(()=>{},[t,r]) -> 调 refresh():useEffect(()=>{r()},[t,r])。
    s,k=re.subn(r'(return \w+\.useEffect\(\(\)=>\{)\}(,\[\w+,(\w+)\]\),\{sshConfigs:)', r'\g<1>\g<3>()}\g<2>', s); fh+=k
    # D) 主机列表重建:sshEnvItems 的 useMemo(()=>[]) -> map(sshConfigs)。变量名全动态发现(跨版本稳)。
    md=re.search(r'sshEnvItems:(\w+),sshSectionVisible:', s)
    if md:
        items=md.group(1)
        mm2=re.search(r'\{sshConfigs:(\w+),sshConfigsLoaded:\w+,sshApisAvailable:', s)  # 主机数组
        mc =re.search(r'currentSshConfig:(\w+)[,}]', s)                                  # 当前选中配置
        ms =re.search(r'\.useCallback\(\w+=>\{\w+\(\)\.then\(\(\)=>\{\w+&&(\w+)\((\w+)\(\w+\)\)\}\)', s)  # 选择fn, 配置->envid
        me =re.search(re.escape(items)+r'=(\w+)\.useMemo\(\(\)=>\[\],\[([^\]]*)\]\)', s)  # React别名, 依赖
        if mm2 and mc and ms and me:
            sshcfg=mm2.group(1); cur=mc.group(1); sel,ae=ms.group(1),ms.group(2)
            E,deps=me.group(1),me.group(2)
            if cur not in deps.split(','): deps=deps+','+cur
            nm=(items+'='+E+'.useMemo(()=>'+sshcfg+'.map(sshCfg=>({config:sshCfg,'
                'label:sshCfg.name||sshCfg.sshHost,checked:'+cur+'?.id===sshCfg.id,'
                'onSelect:()=>'+sel+'('+ae+'(sshCfg))})),['+deps+'])')
            s2=re.sub(re.escape(items)+r'=\w+\.useMemo\(\(\)=>\[\],\[[^\]]*\]\)', lambda _:nm, s, count=1)
            if s2!=s: s=s2; fh+=1
    if s!=o:
        open(f,"w",encoding="utf-8",errors="surrogatepass").write(s)
        print(f"   ✓ {os.path.basename(f)}: 可见性+{fv} 主机列表+{fh}")
    vis+=fv; host+=fh
print(f"   合计:可见性 {vis} 处;主机列表(加载+重建) {host} 处")
if vis==0:
    print("⚠ 没有守卫被改动——版本结构可能已变,需重新分析"); sys.exit(2)
if host<2:
    print("⚠ 主机列表自动填充未完全应用(结构或有变);SSH 仍可用『Add SSH host…』手动添加")
PY
echo "▶ ad-hoc 重签(保留 virtualization 等权限 → Cowork 可用)"
# 重签必须保留官方的硬化运行时权限,否则功能受损:
#   com.apple.security.virtualization  → Cowork 本地虚拟机;缺了会报 "Invalid installation / installation appears to be corrupted"
#   device.* / personal-information.*  → 摄像头/麦克风/蓝牙/USB/位置等
# 但 team 绑定项(application-identifier / keychain-access-groups / developer.team-identifier)在 ad-hoc 下 team 不匹配,
# 反而会挡启动,故一律去掉。以上保留项都是 com.apple.security.*,ad-hoc 自签名即可携带(第三方虚拟机工具同理)。
ENT="$(mktemp -t cent).plist"
cat > "$ENT" <<'PL'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.allow-jit</key><true/><key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/><key>com.apple.security.cs.disable-library-validation</key><true/><key>com.apple.security.cs.allow-dyld-environment-variables</key><true/><key>com.apple.security.virtualization</key><true/><key>com.apple.security.device.audio-input</key><true/><key>com.apple.security.device.bluetooth</key><true/><key>com.apple.security.device.camera</key><true/><key>com.apple.security.device.usb</key><true/><key>com.apple.security.device.print</key><true/><key>com.apple.security.personal-information.location</key><true/><key>com.apple.security.personal-information.photos-library</key><true/></dict></plist>
PL
FW="$DST/Contents/Frameworks"
find "$DST/Contents/Resources/app.asar.unpacked" -type f \( -name "*.node" -o -name "*.dylib" -o -name "spawn-helper" \) 2>/dev/null -print0 | while IFS= read -r -d '' f; do codesign --force -s - --options runtime "$f" 2>/dev/null||true; done
for fwk in Mantle ReactiveObjC Squirrel "Electron Framework"; do [ -d "$FW/$fwk.framework" ] && codesign --force -s - "$FW/$fwk.framework" 2>/dev/null||true; done
for h in "Claude Helper" "Claude Helper (GPU)" "Claude Helper (Plugin)" "Claude Helper (Renderer)"; do [ -d "$FW/$h.app" ] && codesign --force -s - --options runtime --entitlements "$ENT" "$FW/$h.app" 2>/dev/null||true; done
codesign --force -s - --options runtime --entitlements "$ENT" "$DST"; rm -f "$ENT"
echo "$SRCVER" > "$MARK"
echo "✅ 完成。首启弹钥匙串授权时输 Mac 密码点\"始终允许\"(一次性)"
open "$DST"
