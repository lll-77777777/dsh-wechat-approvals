# restore.ps1 — 把「双端审批 + 完成通知」补丁重新装回 DSH
#
# 什么时候用：DSH 或微信插件升级后，改动会被官方版本覆盖，跑一次这个脚本就恢复。
#
# 用法：
#   pwsh -ExecutionPolicy Bypass -File "E:\大肥鱼人设\dsh-wechat-approvals\restore.ps1"
#
# 幂等：已经装好时什么也不做，只报告状态。

$ErrorActionPreference = 'Stop'

$fork       = 'E:\大肥鱼人设\dsh-wechat-approvals'
$dshHome    = Join-Path $env:USERPROFILE '.dsh'
$profileDir = Join-Path $dshHome 'profiles\desktop'
$pluginDir  = Join-Path $profileDir 'node_modules\dsh-wechat-plugin'
$opsFile    = Join-Path $profileDir 'node_modules\dsh-ops\lib\workspace-preparation.js'
$cordis     = Join-Path $profileDir 'cordis.yml'

function Step($msg) { Write-Host "== $msg" }

Step '检查 fork 源'
if (-not (Test-Path (Join-Path $fork 'lib\host.js'))) { throw "找不到 fork 源：$fork" }
$forkVersion = (Get-Content (Join-Path $fork 'package.json') -Raw | ConvertFrom-Json).version
Write-Host "  fork 版本：$forkVersion"

Step '检查已安装的微信插件'
$needCopy = $true
if (Test-Path (Join-Path $pluginDir 'package.json')) {
    $curVersion = (Get-Content (Join-Path $pluginDir 'package.json') -Raw | ConvertFrom-Json).version
    if ($curVersion -eq $forkVersion) {
        $needCopy = $false
        Write-Host "  已是 $curVersion，不需要覆盖"
    }
    else {
        Write-Host "  当前是 $curVersion（官方版或旧版），需要覆盖"
    }
}
else {
    Write-Host '  插件目录不存在，将全新安装'
}

if ($needCopy) {
    Step '替换插件'
    if (Test-Path $pluginDir) {
        $backup = "$pluginDir.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Move-Item $pluginDir $backup
        Write-Host "  旧版本已备份到：$backup"
    }
    Copy-Item $fork $pluginDir -Recurse -Force
    Write-Host "  已复制 fork 到：$pluginDir"
}

Step '检查 cordis.yml 里的开关'
if (Test-Path $cordis) {
    $text = Get-Content $cordis -Raw
    if ($text -match 'relayUnboundApprovals') {
        Write-Host '  开关已存在'
    }
    else {
        $pattern = "(?m)^(\s*name:\s*'?dsh-wechat-plugin'?\s*\r?\n\s*config:\s*\r?\n)"
        $replacement = "`$1    relayUnboundApprovals: true`r`n    notifyTurnEnd: true`r`n    relayDelayMs: 10000`r`n"
        $patched = $text -replace $pattern, $replacement
        if ($patched -ne $text) {
            Set-Content $cordis $patched -Encoding utf8 -NoNewline
            Write-Host '  已补上：relayUnboundApprovals / notifyTurnEnd / relayDelayMs'
        }
        else {
            Write-Host '  [!] 没找到插件配置段，需要手工补三个开关'
        }
    }
}
else {
    Write-Host "  [!] 找不到 $cordis"
}

Step '检查 dsh-ops 的执行策略补丁'
if (Test-Path $opsFile) {
    $ops = Get-Content $opsFile -Raw
    if ($ops -match '-ExecutionPolicy') {
        Write-Host '  已打好'
    }
    else {
        $patched = $ops -replace "'-NoProfile', '-NonInteractive', '-File'", "'-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File'"
        if ($patched -ne $ops) {
            Set-Content $opsFile $patched -Encoding utf8 -NoNewline
            Write-Host '  已打上 -ExecutionPolicy Bypass'
        }
        else {
            Write-Host '  [!] 没找到替换位置（dsh-ops 改版了），需要手工检查'
        }
    }
}
else {
    Write-Host '  [!] 找不到 dsh-ops 文件（DSH 版本可能变了），需要手工检查'
}

Step '完成'
Write-Host '重启 DSH 后生效。'
