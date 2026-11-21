# Windows: 解锁 Claude Desktop 3p 模式下的 SSH 环境(改 ion-dist,无需重签)。
# 用法: powershell -ExecutionPolicy Bypass -File patch-windows.ps1
$ErrorActionPreference = "Stop"
Write-Host "▶ 定位 ion-dist"
$roots = @("$env:LOCALAPPDATA\AnthropicClaude","$env:LOCALAPPDATA\Programs\Claude","$env:LOCALAPPDATA\Claude") | Where-Object { Test-Path $_ }
$files = @()
foreach ($r in $roots) {
  $files += Get-ChildItem -Path $r -Recurse -Filter "*.js" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "ion-dist[\\/]assets[\\/]v1" }
}
if (-not $files) { Write-Error "未找到 ion-dist/assets/v1。手动在安装目录搜 'ion-dist' 确认路径。"; exit 1 }
Write-Host "▶ 补丁 SSH 环境(可见性 + 主机列表自动填充)"
# 3p 版把 sshApisAvailable 编译期折叠成 false 并 DCE,连带削掉 SSH 可见性守卫、配置拉取 effect、
# sshEnvItems 列表映射。底层 IPC(getSSHConfigs)仍在,故纯客户端可全解:
#   可见性 = A(渲染守卫)+ B(根标志翻转);主机列表 = C(恢复拉取)+ D(重建映射)。
$MID = "waUHa40VD6"
# A 回退:旧版内联结构守卫(守卫直接包 Fragment>Separator>Group>Header)
$oldPat = '(?<guard>(?:\([^()]{0,80}\)|[\w$]+))&&(?<body>\w+\.jsxs\(\w+\.Fragment,\{children:\[\w+\.jsx\(\w+\.Separator,\{\}\),\w+\.jsxs\(\w+\.Group,\{children:\[\w+\.jsx\(\w+\.Header,\{children:\w+\.jsx\(\w+,\{defaultMessage:"[^"]*",id:"' + $MID + '")'
$vis = 0; $hostN = 0
$targets = $files | Where-Object { $c = Get-Content $_.FullName -Raw; $c -match $MID -or $c -match 'sshApisAvailable' -or $c -match 'sshEnvItems' } | Sort-Object FullName -Unique
foreach ($f in $targets) {
  $s = Get-Content $f.FullName -Raw
  $orig = $s; $fv = 0; $fh = 0
  # A) SSH 组渲染守卫(新结构:标签抽成变量 LBL;submenu/group 两布局各一处)。
  #    body 用 [^&] 禁跨越兄弟守卫的 &&;(?<![!\w$]) 防重复运行反转成 !!0。
  if ($s -match $MID) {
    $m = [regex]::Match($s, '([\w$]+)=\w+\.jsx\(\w+,\{defaultMessage:"[^"]*",id:"' + $MID + '"\}\)')
    if ($m.Success) {
      $lbl = [regex]::Escape($m.Groups[1].Value)
      $guardPat = '(?<![!\w$])(?<guard>[\w$]+)&&(?<body>\w+\.jsxs\([^&]{1,300}?children:' + $lbl + '\})'
      $fv += ([regex]::Matches($s, $guardPat)).Count
      $s = [regex]::Replace($s, $guardPat, '!0&&${body}')
    }
    $fv += ([regex]::Matches($s, $oldPat)).Count
    $s = [regex]::Replace($s, $oldPat, '!0&&${body}')
  }
  # B) 根标志:sshApisAvailable 的 const=!1 -> !0(锚定语义属性名,最稳)。
  $bPat = '(?<pre>sshApisAvailable:\w+,refresh:\w+\}=function\(\)\{const )(?<v>\w+)=!1,'
  $fv += ([regex]::Matches($s, $bPat)).Count
  $s = [regex]::Replace($s, $bPat, '${pre}${v}=!0,')
  # C) 主机列表自动加载:被削空的 useEffect(()=>{},[t,r]) -> 调 refresh()。
  $cPat = '(?<pre>return \w+\.useEffect\(\(\)=>\{)\}(?<post>,\[\w+,(?<r>\w+)\]\),\{sshConfigs:)'
  $fh += ([regex]::Matches($s, $cPat)).Count
  $s = [regex]::Replace($s, $cPat, '${pre}${r}()}${post}')
  # D) 主机列表重建:sshEnvItems 的 useMemo(()=>[]) -> map(sshConfigs)。变量名动态发现。
  $md = [regex]::Match($s, 'sshEnvItems:(\w+),sshSectionVisible:')
  if ($md.Success) {
    $items = $md.Groups[1].Value
    $mm2 = [regex]::Match($s, '\{sshConfigs:(\w+),sshConfigsLoaded:\w+,sshApisAvailable:')
    $mcf = [regex]::Match($s, 'currentSshConfig:(\w+)[,}]')
    $msl = [regex]::Match($s, '\.useCallback\(\w+=>\{\w+\(\)\.then\(\(\)=>\{\w+&&(\w+)\((\w+)\(\w+\)\)\}\)')
    $mme = [regex]::Match($s, [regex]::Escape($items) + '=(\w+)\.useMemo\(\(\)=>\[\],\[([^\]]*)\]\)')
    if ($mm2.Success -and $mcf.Success -and $msl.Success -and $mme.Success) {
      $sshcfg = $mm2.Groups[1].Value; $cur = $mcf.Groups[1].Value
      $sel = $msl.Groups[1].Value; $ae = $msl.Groups[2].Value
      $E = $mme.Groups[1].Value; $deps = $mme.Groups[2].Value
      if (($deps -split ',') -notcontains $cur) { $deps = $deps + ',' + $cur }
      $nm = $items + '=' + $E + '.useMemo(()=>' + $sshcfg + '.map(sshCfg=>({config:sshCfg,label:sshCfg.name||sshCfg.sshHost,checked:' + $cur + '?.id===sshCfg.id,onSelect:()=>' + $sel + '(' + $ae + '(sshCfg))})),[' + $deps + '])'
      $dPat = [regex]::Escape($items) + '=\w+\.useMemo\(\(\)=>\[\],\[[^\]]*\]\)'
      $ev = [System.Text.RegularExpressions.MatchEvaluator]{ param($x) $nm }   # 委托返回值按字面替换,避免 $ 被当替换符
      $s2 = [regex]::Replace($s, $dPat, $ev)
      if ($s2 -ne $s) { $s = $s2; $fh += 1 }
    }
  }
  if ($s -ne $orig) { Copy-Item $f.FullName "$($f.FullName).bak" -Force; Set-Content $f.FullName $s -NoNewline -Encoding utf8; Write-Host "   ✓ $($f.Name): 可见性+$fv 主机列表+$fh" }
  $vis += $fv; $hostN += $fh
}
if ($vis -eq 0) { Write-Error "没有守卫被改动(已打过或结构变化,需重新分析)。"; exit 2 }
if ($hostN -lt 2) { Write-Warning "主机列表自动填充未完全应用(结构或有变);SSH 仍可用『Add SSH host…』手动添加。" }
Write-Host "✅ 完成:可见性 $vis 处,主机列表 $hostN 处。完全退出并重启 Claude Desktop。"
