<#
    resolve_godot.ps1 —— 光线游戏 · Godot 路径解析器（唯一有“智能”的地方）

    职责：找到本机可用的 Godot 4.7+，校验版本，把结果写成环境变量文件供 .bat 调用。

    探测顺序（命中即停，快 → 慢）：
      1. 环境变量 GODOT
      2. tools\godot_path.cfg        本机覆盖，不提交 git（写文件夹或写 exe 都认）
      3. tools\.cache\godot.txt      上次探测结果缓存（exe 大小/时间变了才重探）
      4. PATH 里的 godot / godot4
      5. 白名单目录浅扫（D:\、C:\、Programs、Downloads、桌面、文档、Program Files）
      6. 找不到 → 退出码 1，并给出明确提示

    设计要点：
      * 允许把“文件夹”当路径传入。解压后目录常常就叫 Godot_v4.7.2-stable_win64.exe，
        解析器会自动进一层找真正的 exe（这是最容易踩的坑）。
      * 版本低于 4.7 一律硬拦截（project.godot 已声明 features=4.7）。
      * 同时给出 GUI 版和 _console.exe 版：前者跑游戏/编辑器，后者跑无头测试（才有 stdout）。

    用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\resolve_godot.ps1
      powershell ... -File tools\resolve_godot.ps1 -Set "D:\Godot\Godot_v4.7.exe"
      powershell ... -File tools\resolve_godot.ps1 -Force        # 忽略缓存
#>
[CmdletBinding()]
param(
    [string]$Set,
    [string]$ProjectDir,
    [switch]$Force,
    [switch]$NoWrite,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$ToolsDir  = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectDir)) { $ProjectDir = Split-Path -Parent $ToolsDir }
$ProjectDir = [IO.Path]::GetFullPath($ProjectDir).TrimEnd('\')
$CacheDir  = Join-Path $ToolsDir '.cache'
$CacheFile = Join-Path $CacheDir 'godot.txt'
$EnvFile   = Join-Path $CacheDir 'env.cmd'
$CfgFile   = Join-Path $ToolsDir 'godot_path.cfg'

$MinMajor = 4
$MinMinor = 7

function Say  { param([string]$m) if (-not $Quiet) { Write-Host $m } }
function SayE { param([string]$m) Write-Host $m -ForegroundColor Red }

# ---------- 工具函数 ----------

function Get-NameVersion([string]$fileName) {
    $m = [regex]::Match($fileName, '(\d+)\.(\d+)(\.(\d+))?')
    if ($m.Success) {
        $patch = 0
        if ($m.Groups[4].Success) { $patch = [int]$m.Groups[4].Value }
        return [version]("{0}.{1}.{2}" -f [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, $patch)
    }
    return [version]'0.0.0'
}

# 把一个“路径”（可能是文件夹、exe、带引号的拖拽路径）解析成候选 exe 列表
function Resolve-Candidates([string]$raw) {
    $result = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrWhiteSpace($raw)) { return $result }

    $p = $raw.Trim().Trim('"').Trim()
    if ($p -eq '') { return $result }
    # 支持 %USERPROFILE% 之类
    $p = [Environment]::ExpandEnvironmentVariables($p)
    if (-not (Test-Path -LiteralPath $p)) { return $result }
    $item = Get-Item -LiteralPath $p -Force

    if ($item.PSIsContainer) {
        # 1) 文件夹里直接就是 exe
        $direct = Get-ChildItem -LiteralPath $item.FullName -Filter 'Godot*.exe' -File -ErrorAction SilentlyContinue
        # 2) 再往里一层（解压后常见 xxx\Godot_v4.7...\ 或 xxx\Godot_v4.7...\bin\）
        $deep = Get-ChildItem -LiteralPath $item.FullName -Filter 'Godot*.exe' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                Where-Object { $direct.FullName -notcontains $_.FullName }
        foreach ($f in @($direct) + @($deep)) { if ($f) { [void]$result.Add($f.FullName) } }
    }
    elseif ($item.Extension -ieq '.exe' -and $item.BaseName -like 'Godot*') {
        [void]$result.Add($item.FullName)
    }
    return $result
}

# 从一堆候选里挑主 exe（优先 GUI 版、版本号最高），并找出对应的 console 版
function Select-Best([object[]]$candidates) {
    $exes = @($candidates | Where-Object { $_ } | Sort-Object -Unique)
    if ($exes.Count -eq 0) { return $null }

    $gui = @($exes | Where-Object { $_ -notmatch '_console\.exe$' })
    $pool = if ($gui.Count -gt 0) { $gui } else { $exes }
    $best = $pool | Sort-Object -Property @{ Expression = { Get-NameVersion (Split-Path -Leaf $_) } } -Descending | Select-Object -First 1

    # 只给了 _console.exe 时，回退到同目录的 GUI 版做“主 exe”（GUI 版不会额外弹控制台窗口）
    if ($best -match '_console\.exe$') {
        $guiSibling = Join-Path (Split-Path -Parent $best) (([IO.Path]::GetFileNameWithoutExtension($best) -replace '_console$', '') + '.exe')
        if (Test-Path -LiteralPath $guiSibling) { $best = $guiSibling }
    }

    $dir  = Split-Path -Parent $best
    $base = [IO.Path]::GetFileNameWithoutExtension($best)
    if ($base -match '_console$') { $base = $base -replace '_console$', '' }
    $console = Join-Path $dir ($base + '_console.exe')
    if (-not (Test-Path -LiteralPath $console)) {
        $any = Get-ChildItem -LiteralPath $dir -Filter 'Godot*_console.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($any) { $console = $any.FullName } else { $console = $best }
    }
    return [pscustomobject]@{ Exe = $best; Console = $console }
}

# 用 console 版查版本（GUI 版拿不到 stdout）
function Get-GodotVersion([string]$consoleExe, [string]$fallbackName) {
    try {
        $out = & $consoleExe --version 2>$null
        foreach ($line in @($out)) {
            $m = [regex]::Match([string]$line, '^\s*(\d+)\.(\d+)(?:\.(\d+))?')
            if ($m.Success) {
                $patch = 0
                if ($m.Groups[3].Success) { $patch = [int]$m.Groups[3].Value }
                return [version]("{0}.{1}.{2}" -f [int]$m.Groups[1].Value, [int]$m.Groups[2].Value, $patch)
            }
        }
    } catch { }
    return Get-NameVersion $fallbackName
}

function Test-TooOld($ver) {
    if ($null -eq $ver) { return $false }
    if ($ver.Major -ne $MinMajor) { return ($ver.Major -lt $MinMajor) }
    return ($ver.Minor -lt $MinMinor)
}

# 浅扫：只找名字像 Godot* 的目录/文件，避免全盘遍历
function Find-InRoots([string]$root) {
    $found = New-Object System.Collections.ArrayList
    if (-not (Test-Path -LiteralPath $root)) { return $found }
    foreach ($f in (Get-ChildItem -LiteralPath $root -Filter 'Godot*.exe' -File -ErrorAction SilentlyContinue)) {
        [void]$found.Add($f.FullName)
    }
    foreach ($d in (Get-ChildItem -LiteralPath $root -Directory -Filter 'Godot*' -ErrorAction SilentlyContinue)) {
        foreach ($f in (Get-ChildItem -LiteralPath $d.FullName -Filter 'Godot*.exe' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue)) {
            [void]$found.Add($f.FullName)
        }
    }
    return $found
}

# ---------- 结果落地 ----------

function Save-Env($pick, $ver, [string]$source) {
    if ($NoWrite) { return }
    if (-not (Test-Path -LiteralPath $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }

    $lines = @(
        ("set `"GODOT_EXE={0}`"" -f $pick.Exe),
        ("set `"GODOT_CONSOLE_EXE={0}`"" -f $pick.Console),
        ("set `"GODOT_VERSION={0}`"" -f $ver.ToString()),
        ("set `"GODOT_PROJECT={0}`"" -f $ProjectDir),
        ("set `"GODOT_FOUND_BY={0}`"" -f $source)
    )
    [IO.File]::WriteAllText($EnvFile, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

    $info = Get-Item -LiteralPath $pick.Exe
    $cache = "{0}|{1}|{2}|{3}" -f $pick.Exe, $ver.ToString(), $info.Length, $info.LastWriteTimeUtc.Ticks
    [IO.File]::WriteAllText($CacheFile, $cache, (New-Object System.Text.UTF8Encoding($false)))
}

function Finish($pick, $ver, [string]$source) {
    Save-Env $pick $ver $source
    Say ""
    Say ("  Godot      : {0}" -f $pick.Exe)
    Say ("  版本       : {0}  (最低要求 {1}.{2})" -f $ver.ToString(), $MinMajor, $MinMinor)
    Say ("  来源       : {0}" -f $source)
    Say ("  工程目录   : {0}" -f $ProjectDir)
    Say ""
    exit 0
}

function Fail([string]$msg, [string[]]$hints) {
    SayE ""
    SayE ("  [错误] " + $msg)
    foreach ($h in $hints) { SayE ("         " + $h) }
    SayE ""
    exit 1
}

# ---------- 手动设置模式 ----------

if ($PSBoundParameters.ContainsKey('Set')) {
    $cands = Resolve-Candidates $Set
    $pick  = Select-Best $cands
    if (-not $pick) {
        Fail ("这个路径下没找到 Godot 可执行文件：{0}" -f $Set) @(
            "请指到 exe 本身，或它所在的文件夹。",
            "例如：D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
        )
    }
    $ver = Get-GodotVersion $pick.Console (Split-Path -Leaf $pick.Exe)
    if (Test-TooOld $ver) {
        Fail ("检测到 Godot {0}，本工程需要 {1}.{2} 及以上。" -f $ver.ToString(), $MinMajor, $MinMinor) @(
            "请下载新版：https://godotengine.org/download/windows/"
        )
    }
    [IO.File]::WriteAllText($CfgFile, ("# 本机 Godot 路径（不要提交 git，每台机器自己一份）`r`n{0}`r`n" -f $pick.Exe), (New-Object System.Text.UTF8Encoding($false)))
    Say ("  已写入本机配置：{0}" -f $CfgFile)
    Save-Env $pick $ver 'cfg'
    Finish $pick $ver '手动设置'
}

# ---------- 1. 环境变量 ----------

if ($env:GODOT) {
    $pick = Select-Best (Resolve-Candidates $env:GODOT)
    if ($pick) {
        $ver = Get-GodotVersion $pick.Console (Split-Path -Leaf $pick.Exe)
        if (-not (Test-TooOld $ver)) { Finish $pick $ver '环境变量 GODOT' }
    }
}

# ---------- 2. 本机配置 ----------

if (Test-Path -LiteralPath $CfgFile) {
    $raw = (Get-Content -LiteralPath $CfgFile -TotalCount 5 -Encoding UTF8) |
           Where-Object { $_ -and $_.Trim() -ne '' -and -not $_.TrimStart().StartsWith('#') } |
           Select-Object -First 1
    if ($raw) {
        $pick = Select-Best (Resolve-Candidates $raw)
        if ($pick) {
            $ver = Get-GodotVersion $pick.Console (Split-Path -Leaf $pick.Exe)
            if (-not (Test-TooOld $ver)) { Finish $pick $ver 'godot_path.cfg' }
            SayE ("  [注意] godot_path.cfg 里的 Godot 是 {0}，低于要求的 {1}.{2}，继续寻找……" -f $ver, $MinMajor, $MinMinor)
        } else {
            SayE "  [注意] godot_path.cfg 里的路径已失效，继续探测……"
        }
    }
}

# ---------- 3. 缓存 ----------

if (-not $Force -and (Test-Path -LiteralPath $CacheFile)) {
    $parts = ([IO.File]::ReadAllText($CacheFile)).Trim().Split('|')
    if ($parts.Count -ge 4 -and (Test-Path -LiteralPath $parts[0])) {
        $info = Get-Item -LiteralPath $parts[0]
        if ($info.Length -eq [long]$parts[2] -and $info.LastWriteTimeUtc.Ticks -eq [long]$parts[3]) {
            $pick = Select-Best @($parts[0])
            if ($pick) {
                $ver = $null
                [void][version]::TryParse($parts[1], [ref]$ver)
                if ($ver -and -not (Test-TooOld $ver)) { Finish $pick $ver '缓存' }
            }
        }
    }
}

# ---------- 4. PATH ----------

foreach ($name in @('godot', 'godot4', 'Godot')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Path) {
        $pick = Select-Best (Resolve-Candidates $cmd.Path)
        if ($pick) {
            $ver = Get-GodotVersion $pick.Console (Split-Path -Leaf $pick.Exe)
            if (-not (Test-TooOld $ver)) { Finish $pick $ver 'PATH' }
        }
    }
}

# ---------- 5. 白名单浅扫 ----------

$roots = @(
    'D:\', 'C:\', 'E:\', 'F:\',
    (Join-Path $env:LOCALAPPDATA 'Programs'),
    (Join-Path $env:USERPROFILE 'Downloads'),
    (Join-Path $env:USERPROFILE 'Desktop'),
    (Join-Path $env:USERPROFILE 'Documents'),
    'C:\Program Files',
    'C:\Program Files (x86)'
) | Select-Object -Unique

$tooOld = $null
Say "  正在常见目录里查找 Godot……"
foreach ($root in $roots) {
    foreach ($exe in (Find-InRoots $root)) {
        $pick = Select-Best @($exe)
        if (-not $pick) { continue }
        $ver = Get-GodotVersion $pick.Console (Split-Path -Leaf $pick.Exe)
        if (Test-TooOld $ver) { $tooOld = [pscustomobject]@{ Ver = $ver; Exe = $pick.Exe }; continue }
        Finish $pick $ver ('扫描 ' + $root)
    }
}

# ---------- 6. 失败 ----------

if ($tooOld) {
    Fail ("本机只找到 Godot {0}，本工程需要 {1}.{2} 及以上。" -f $tooOld.Ver, $MinMajor, $MinMinor) @(
        ("找到的位置：{0}" -f $tooOld.Exe),
        "请下载新版：https://godotengine.org/download/windows/",
        "下载后解压，双击 tools\tasks\05_设置Godot路径.bat 指定一次即可。"
    )
}

$zips = @()
foreach ($dir in @((Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop'), 'D:\')) {
    if (Test-Path -LiteralPath $dir) {
        $zips += Get-ChildItem -LiteralPath $dir -Filter '*odot*.zip' -File -ErrorAction SilentlyContinue
    }
}
$hints = @("双击 tools\tasks\05_设置Godot路径.bat，把 Godot 的 exe（或文件夹）拖进去即可。")
if ($zips.Count -gt 0) { $hints += ("检测到未解压的压缩包：{0} —— Godot 是绿色版，先解压再用。" -f $zips[0].Name) }
Fail "没有找到可用的 Godot 4.7+。" $hints
