# install-autostart.ps1 — 让补丁在官方插件升级后被自动恢复
#
# 默认做法：往 Windows「启动」文件夹放一个 vbs，每次登录时在后台跑一次
# check-and-restore.ps1。不需要管理员，不需要计划任务服务，卸载就是删文件。
#
# 用法（普通 PowerShell 窗口即可）：
#   powershell -ExecutionPolicy Bypass -File .\install-autostart.ps1          # 部署启动项
#   powershell -ExecutionPolicy Bypass -File .\install-autostart.ps1 -Remove  # 删除启动项
#   powershell -ExecutionPolicy Bypass -File .\install-autostart.ps1 -Task    # 改用计划任务
#
# 日志：脚本目录下的 restore.log

param(
    [switch]$Remove,
    [switch]$Task
)

$ErrorActionPreference = 'Stop'

$checker   = Join-Path $PSScriptRoot 'check-and-restore.ps1'
$taskName  = 'DSH-WeChat-Approvals-Restore'
$startup   = [Environment]::GetFolderPath('Startup')
$vbsPath   = Join-Path $startup 'DSH-WeChat-Approvals-Restore.vbs'

# 把任意字符串变成 VBScript 表达式：ASCII 用字面量，非 ASCII 用 ChrW() 拼，
# 这样生成的 vbs 文件本身永远是纯 ASCII，不受系统代码页影响。
function ToVbsString([string]$s) {
    $parts = @()
    $run = ''
    foreach ($ch in $s.ToCharArray()) {
        $code = [int]$ch
        if ($code -ge 32 -and $code -lt 127 -and $ch -ne '"') {
            $run += [string]$ch
        }
        else {
            if ($run -ne '') { $parts += '"' + $run + '"'; $run = '' }
            $parts += "ChrW($code)"
        }
    }
    if ($run -ne '') { $parts += '"' + $run + '"' }
    if ($parts.Count -eq 0) { return '""' }
    return ($parts -join ' & ')
}

if ($Remove) {
    if (Test-Path $vbsPath) {
        Remove-Item $vbsPath -Force
        Write-Host "已删除启动项：$vbsPath"
    }
    else { Write-Host "没有找到启动项：$vbsPath" }

    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "已删除计划任务：$taskName"
    }
    exit 0
}

if (-not (Test-Path $checker)) { throw "找不到检查脚本：$checker" }

if ($Task) {
    # 计划任务模式：优先用系统 PowerShell 7，没有就用 5.1
    $candidates = @(
        (Join-Path ${env:ProgramFiles} 'PowerShell\7\pwsh.exe'),
        (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    )
    $exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe) { throw '找不到系统 PowerShell' }
    Write-Host "使用 PowerShell：$exe"

    $action  = New-ScheduledTaskAction -Execute $exe -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Quiet' -f $checker)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal `
        -Description '登录时检查 DSH 微信双端审批补丁，被官方版覆盖就自动恢复' -Force | Out-Null
    Write-Host "已注册计划任务：$taskName"
    exit 0
}

# 启动文件夹模式（默认，不需要管理员）
$expr = ToVbsString $checker
$vbs = @"
' Startup check for the DSH WeChat dual-approval patch (auto-generated).
' Restores the patch after an official plugin update overwrites it.
' Uninstall: delete this file.
Set sh = CreateObject("WScript.Shell")
p = $expr
sh.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & p & """ -Quiet", 0, False
"@

[System.IO.File]::WriteAllText($vbsPath, $vbs, [System.Text.Encoding]::ASCII)
Write-Host "已部署启动项：$vbsPath"
Write-Host '下次登录 Windows 时后台自动检查（现在也可以手动跑一次验证）：'
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$checker`""
Write-Host "日志：$(Join-Path $PSScriptRoot 'restore.log')"
