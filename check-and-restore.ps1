# check-and-restore.ps1 — 检查双端审批补丁是否还在，不在就自动恢复
#
# 给计划任务或手动用。判断依据是插件版本号里的 "-desknotify" 后缀，
# 覆盖前会先做接口自检，官方新版接口变了就拒绝覆盖（避免把插件搞坏）。
#
# 用法：
#   pwsh -ExecutionPolicy Bypass -File .\check-and-restore.ps1          # 手动，输出到控制台
#   pwsh -ExecutionPolicy Bypass -File .\check-and-restore.ps1 -Quiet   # 计划任务，只写日志
#   pwsh -ExecutionPolicy Bypass -File .\check-and-restore.ps1 -ProfileDir 'D:\test\desktop'   # 指定别的 profile（测试用）
#
# 退出码：0 已就绪/已恢复，2 官方接口不兼容（未覆盖），3 官方插件没装

param(
    [switch]$Quiet,
    [string]$ForkDir,
    [string]$ProfileDir
)

$ErrorActionPreference = 'Stop'

$fork       = if ($ForkDir) { $ForkDir } else { $PSScriptRoot }
$dshHome    = Join-Path $env:USERPROFILE '.dsh'
if (-not $ProfileDir) { $ProfileDir = Join-Path $dshHome 'profiles\desktop' }
$profileDir = $ProfileDir
$pluginDir  = Join-Path $profileDir 'node_modules\dsh-wechat-plugin'
$opsFile    = Join-Path $profileDir 'node_modules\dsh-ops\lib\workspace-preparation.js'
$cordis     = Join-Path $profileDir 'cordis.yml'
$logFile    = Join-Path $fork 'restore.log'

function SaveText($path, $text) {
    # 用 .NET 写 UTF-8 无 BOM：Windows PowerShell 5.1 的 Set-Content -Encoding utf8 会带 BOM，
    # YAML/JS 解析器可能因此报错。
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Log($msg) {
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    if (-not $Quiet) { Write-Host $line }
    try {
        $dir = Split-Path $logFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $logFile -Value $line -Encoding utf8
    } catch { }
}

function Fail($code, $msg) {
    Log "错误：$msg"
    exit $code
}

Log '=== 检查开始 ==='

# 1. fork 源
if (-not (Test-Path (Join-Path $fork 'lib\host.js'))) { Fail 3 "找不到 fork 源：$fork" }
$forkVersion = (Get-Content (Join-Path $fork 'package.json') -Raw | ConvertFrom-Json).version
if ($forkVersion -notlike '*-desknotify*') { Fail 3 "fork 源版本号不像补丁版：$forkVersion" }

# 2. 已装插件
if (-not (Test-Path (Join-Path $pluginDir 'package.json'))) {
    Fail 3 '官方微信插件没有安装，先 dsh plugin --profile desktop add dsh-wechat-plugin@0.43.1'
}
$curVersion = (Get-Content (Join-Path $pluginDir 'package.json') -Raw | ConvertFrom-Json).version
Log "已装版本：$curVersion，fork 版本：$forkVersion"

$needCopy = $curVersion -ne $forkVersion

if ($needCopy) {
    # 3. 接口自检：fork 直接调官方内部接口，官方改了就拒绝覆盖
    Log '接口自检中……'
    $problems = @()

    $interactions = Join-Path $pluginDir 'lib\interactions.js'
    if (Test-Path $interactions) {
        $t = Get-Content $interactions -Raw
        if ($t -notmatch 'presentApproval') { $problems += 'lib/interactions.js 缺少 presentApproval' }
        if ($t -notmatch 'parseApprovalReply') { $problems += 'lib/interactions.js 缺少 parseApprovalReply' }
    } else { $problems += 'lib/interactions.js 不存在' }

    $state = Join-Path $pluginDir 'dist\core\lib\state.js'
    if (Test-Path $state) {
        $t = Get-Content $state -Raw
        if ($t -notmatch 'bindings') { $problems += 'dist/core/lib/state.js 缺少 bindings' }
    } else { $problems += 'dist/core/lib/state.js 不存在' }

    $services = Join-Path $pluginDir 'lib\services.js'
    if (Test-Path $services) {
        $t = Get-Content $services -Raw
        if ($t -notmatch 'readStreamFrame') { $problems += 'lib/services.js 缺少 readStreamFrame' }
    } else { $problems += 'lib/services.js 不存在' }

    if ($problems.Count -gt 0) {
        Fail 2 ("官方新版的内部接口变了，拒绝覆盖（否则插件会坏）：" + ($problems -join '；') + '。需要人工适配 fork。')
    }

    # 4. 备份并覆盖
    $backup = "$pluginDir.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Move-Item $pluginDir $backup
    Log "已备份到：$backup"
    Copy-Item $fork $pluginDir -Recurse -Force
    Log "已恢复 fork：$pluginDir"
}

# 5. cordis.yml 开关
if (Test-Path $cordis) {
    $text = Get-Content $cordis -Raw
    if ($text -match 'relayUnboundApprovals') {
        Log 'cordis.yml 开关已存在'
    }
    else {
        $pattern = "(?m)^(\s*name:\s*'?dsh-wechat-plugin'?\s*\r?\n\s*config:\s*\r?\n)"
        $replacement = "`$1    relayUnboundApprovals: true`r`n    relayDelayMs: 10000`r`n    notifyTurnEnd: true`r`n    notifyTurnEndMinMs: 60000`r`n    notifyTurnEndMinTools: 5`r`n"
        $patched = $text -replace $pattern, $replacement
        if ($patched -ne $text) {
            SaveText $cordis $patched
            Log '已补上 relayUnboundApprovals / relayDelayMs / notifyTurnEnd / 阈值两键'
        }
        else { Log '[!] cordis.yml 里没找到插件配置段，需要手工补开关' }
    }
}
else { Log "[!] 找不到 $cordis" }

# 6. dsh-ops 执行策略补丁
if (Test-Path $opsFile) {
    $ops = Get-Content $opsFile -Raw
    if ($ops -match '-ExecutionPolicy') { Log 'dsh-ops 补丁已打好' }
    else {
        $patched = $ops -replace "'-NoProfile', '-NonInteractive', '-File'", "'-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File'"
        if ($patched -ne $ops) {
            SaveText $opsFile $patched
            Log '已给 dsh-ops 打上 -ExecutionPolicy Bypass'
        }
        else { Log '[!] dsh-ops 里没找到替换位置（上游改版），需要手工检查' }
    }
}
else { Log '[!] 找不到 dsh-ops 文件（DSH 版本可能变了）' }

# 7. 语法自检（有 node 就查，没有就跳过）
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    try {
        & $node.Source --check (Join-Path $pluginDir 'lib\host.js') 2>$null
        if ($LASTEXITCODE -eq 0) { Log '语法检查通过' }
        else { Log '[!] lib/host.js 语法检查失败' }
    } catch { Log '[!] 语法检查执行失败' }
} else { Log '未找到 node，跳过语法检查' }

Log '=== 检查结束 ==='
if ($needCopy) { Log '已恢复补丁，重启 DSH 生效' } else { Log '一切就绪，无需改动' }
exit 0
