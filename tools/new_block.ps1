<#
    new_block.ps1 —— 从 blocks\_template 生成一个新积木（机关类）

    用法：
      powershell -NoProfile -ExecutionPolicy Bypass -File tools\new_block.ps1 -Name rotating_mirror
      powershell ... -File tools\new_block.ps1 -Name rotating_mirror -ProjectDir D:\godot\game

    做四件事：建目录、复制脚本+场景、把类名换成 PascalCase、把场景里的脚本路径改对。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$ProjectDir
)

$ErrorActionPreference = 'Stop'

function Say  { param([string]$m) Write-Host $m }
function SayE { param([string]$m) Write-Host $m -ForegroundColor Red }

$ToolsDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProjectDir)) { $ProjectDir = Split-Path -Parent $ToolsDir }
$ProjectDir = [IO.Path]::GetFullPath($ProjectDir).TrimEnd('\')

$Name = $Name.Trim().ToLower()
if ($Name -notmatch '^[a-z][a-z0-9_]*$') {
    SayE "  积木名只能用 小写字母 + 数字 + 下划线，且以字母开头。例如：rotating_mirror"
    exit 1
}

$Pascal = ($Name -split '_' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1) }) -join ''
$Pascal = $Pascal.Substring(0,1).ToUpper() + $Pascal.Substring(1)
if ($Pascal -notmatch '^[A-Za-z][A-Za-z0-9]*$') { SayE "  无法从 '$Name' 生成合法类名。"; exit 1 }

$tplDir  = Join-Path $ProjectDir 'blocks\_template'
$tplGd   = Join-Path $tplDir '_template.gd'
$tplTscn = Join-Path $tplDir '_template.tscn'
if (-not (Test-Path -LiteralPath $tplGd) -or -not (Test-Path -LiteralPath $tplTscn)) {
    SayE "  找不到模板：$tplDir（需要 blocks\_template\_template.gd 和 _template.tscn）"
    exit 1
}

$targetDir = Join-Path (Join-Path $ProjectDir 'blocks') $Name
if (Test-Path -LiteralPath $targetDir) {
    SayE "  blocks\$Name 已经存在了，换一个名字，或先删掉旧的。"
    exit 1
}

# 类名冲突检查（扫 blocks / core / scenes 下所有 .gd）
$conflict = Get-ChildItem -LiteralPath $ProjectDir -Recurse -Filter '*.gd' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\\.godot\\' } |
            Select-String -Pattern ("^\s*class_name\s+" + [regex]::Escape($Pascal) + "\s*$") -List -ErrorAction SilentlyContinue
if ($conflict) {
    SayE "  类名 $Pascal 已经被使用了：$($conflict[0].Path)"
    SayE "  换一个积木名，或改模板里的类名。"
    exit 1
}

New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

$gdOut   = Join-Path $targetDir ($Name + '.gd')
$tscnOut = Join-Path $targetDir ($Name + '.tscn')

$enc = New-Object System.Text.UTF8Encoding($false)

$gdText = [IO.File]::ReadAllText($tplGd)
$gdText = $gdText.Replace('class_name BlockTemplate', ('class_name ' + $Pascal))
# 把模板头部那一整行注释换掉（按行匹配，避免残留半句话）
$header = '## 【' + $Pascal + '】积木（由 90_新建积木.bat 从模板生成，可自由修改）'
$gdText = [regex]::Replace($gdText, '##\s*【积木模板.*', $header)
[IO.File]::WriteAllText($gdOut, $gdText, $enc)

$tscnText = [IO.File]::ReadAllText($tplTscn)
$tscnText = $tscnText.Replace('res://blocks/_template/_template.gd', ('res://blocks/' + $Name + '/' + $Name + '.gd'))
$tscnText = $tscnText.Replace('[node name="Template"', ('[node name="' + $Pascal + '"'))
[IO.File]::WriteAllText($tscnOut, $tscnText, $enc)

Say ""
Say ("  已生成积木：blocks\{0}\" -f $Name)
Say ("    脚本  blocks\{0}\{0}.gd      class_name {1}" -f $Name, $Pascal)
Say ("    场景  blocks\{0}\{0}.tscn" -f $Name)
Say ""
Say "  接下来："
Say "    1. 打开编辑器，在 blocks\$Name\$Name.gd 里实现 on_lit() / on_unlit()"
Say "    2. 调 SensorShape 的形状 = 感光区范围（别把光源包进去）"
Say "    3. 把场景拖进关卡；如果它会亮/会动，记得在 _ready 或状态变化时 queue_redraw()"
Say "    4. 回到编辑器或命令行跑 50 检查积木，确认层和类型没写错"
Say ""
exit 0
