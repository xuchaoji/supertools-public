<#
.SYNOPSIS
    通过 hdc 远程解锁鸿蒙真机，恢复可调试状态。

.DESCRIPTION
    流程：亮屏 (power-shell wakeup) -> 上划 -> 注入锁屏密码 (uitest uiInput text)。
    全程不截图、不识别页面，用系统窗口/电源状态判断是否真的解锁。

    密码来源优先级：-Password 参数 > 环境变量 HDC_UNLOCK_PASSWORD > .dsh/devices.json 台账。
    遇到台账里没有的设备且没给密码时直接报错退出，绝不盲猜。

.PARAMETER Target
    hdc 目标，如 192.168.3.144:12345。省略时要求当前只有一台已连接设备。

.PARAMETER Status
    只查询状态（电源状态 + 是否锁屏），不做任何解锁动作。

.EXAMPLE
    pwsh -File tools/unlock.ps1 -Status
    pwsh -File tools/unlock.ps1 -Target 192.168.3.144:12345 -Password <你的锁屏密码>
    pwsh -File tools/unlock.ps1            # 单设备 + 台账里有密码
#>
[CmdletBinding()]
param(
    [string]$Target,
    [string]$Password,
    [switch]$Status,
    [int]$SwipeFromX = 542,
    [int]$FromY = 2300,
    [int]$ToY = 500,
    [int]$Velocity = 3000
)

$ErrorActionPreference = 'Stop'
$repoRoot   = Split-Path -Parent $PSScriptRoot
$ledgerPath = Join-Path $repoRoot '.dsh\devices.json'

function Get-HdcExe {
    $cmd = Get-Command hdc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @()
    if ($env:DEVECO_HOME) {
        $candidates += (Join-Path $env:DEVECO_HOME 'sdk\default\openharmony\toolchains\hdc.exe')
    }
    $candidates += 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw 'hdc 未找到：请安装 DevEco Studio，或把 hdc 所在目录加入 PATH。'
}

function Read-Ledger {
    if (-not (Test-Path $ledgerPath)) { return @() }
    try { return @(Get-Content $ledgerPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { throw "设备台账解析失败：$ledgerPath" }
}

function Resolve-Target {
    param([string]$HdcExe)
    if ($Target) { return $Target }
    $out = @(& $HdcExe list targets 2>&1 | ForEach-Object { "$_".Trim() } |
             Where-Object { $_ -and $_ -ne '[Empty]' -and $_ -notmatch '^\s*$' })
    if ($out.Count -eq 0) { throw '没有已连接的 hdc 设备。' }
    if ($out.Count -gt 1) {
        throw ("检测到 {0} 台设备，必须用 -Target 指定：{1}" -f $out.Count, ($out -join ', '))
    }
    return $out[0]
}

function Get-PowerState {
    param([string]$HdcExe, [string]$T)
    $lines = & $HdcExe -t $T shell hidumper -s PowerManagerService -a '-a' 2>&1
    $m = ($lines | Select-String -Pattern 'Current State:\s*(\w+)' | Select-Object -First 1)
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return 'UNKNOWN'
}

function Test-Locked {
    param([string]$HdcExe, [string]$T)
    # 锁屏窗口不可见时 zOrder 为 -1；可见时为具体层级（如 2000）。
    $rows = & $HdcExe -t $T shell hidumper -s WindowManagerService -a '-a' 2>&1
    $row  = $rows | Select-String -Pattern 'SCBScreenLock' | Select-Object -First 1
    if (-not $row) { return $false }
    $tokens = @($row.Line.Trim() -split '\s+')
    if ($tokens.Count -lt 8) { return $true }
    return ($tokens[7] -ne '-1')
}

function Show-Status {
    param([string]$HdcExe, [string]$T)
    $state  = Get-PowerState -HdcExe $HdcExe -T $T
    $locked = Test-Locked  -HdcExe $HdcExe -T $T
    Write-Host ("device : {0}" -f $T)
    Write-Host ("power  : {0}" -f $state)
    Write-Host ("locked : {0}" -f $(if ($locked) { 'YES (锁屏中)' } else { 'NO (已解锁)' }))
    return [pscustomobject]@{ Target = $T; Power = $state; Locked = $locked }
}

$hdc = Get-HdcExe
$t   = Resolve-Target -HdcExe $hdc
$ping = & $hdc -t $t shell echo hdc-ok 2>&1
if ($ping -notmatch 'hdc-ok') { throw "设备 $t 不可用：$ping" }

if ($Status) { $null = Show-Status -HdcExe $hdc -T $t; exit 0 }

# 解析密码
$entry = (Read-Ledger) | Where-Object { $_.target -eq $t } | Select-Object -First 1
if (-not $Password -and $env:HDC_UNLOCK_PASSWORD) { $Password = $env:HDC_UNLOCK_PASSWORD }
if (-not $Password -and $entry -and $entry.password) { $Password = $entry.password }
if (-not $Password) {
    throw ("未知设备 $t：台账里没有记录，也没有通过 -Password 或 HDC_UNLOCK_PASSWORD 提供锁屏密码。" +
           "请先向用户确认密码，不要尝试猜测。")
}

$before = Show-Status -HdcExe $hdc -T $t
if (-not $before.Locked) {
    Write-Host '设备已解锁，无需操作。'
    exit 0
}

$attempts = 2
for ($i = 1; $i -le $attempts; $i++) {
    Write-Host ("[*] 第 {0}/{1} 次：亮屏 -> 上划 -> 输密码" -f $i, $attempts)
    & $hdc -t $t shell power-shell wakeup 2>&1 | Out-Null
    Start-Sleep -Milliseconds 400
    & $hdc -t $t shell uitest uiInput swipe $SwipeFromX $FromY $ToY $Velocity 2>&1 | Out-Null
    Start-Sleep -Milliseconds 600
    & $hdc -t $t shell uitest uiInput text $Password 2>&1 | Out-Null
    Start-Sleep -Milliseconds 1800

    $after = Show-Status -HdcExe $hdc -T $t
    if (-not $after.Locked) {
        Write-Host 'OK: 已解锁。'
        # 只输出真正处于 FOREGROUND 的 mission（mission 行后紧跟 state #FOREGROUND）
        $lastMission = $null
        $foreground  = @()
        foreach ($line in (& $hdc -t $t shell aa dump -l 2>&1)) {
            if     ($line -match 'Mission ID #') { $lastMission = $line.Trim() }
            elseif ($line -match '^\s*state #FOREGROUND' -and $lastMission) {
                $foreground += $lastMission
                $lastMission = $null
            }
        }
        if ($foreground) {
            Write-Host '前台任务：'
            $foreground | ForEach-Object { Write-Host ("  " + $_) }
        }
        exit 0
    }
    Start-Sleep -Milliseconds 800
}

Write-Error "解锁失败：设备仍处于锁屏状态（密码错误，或锁屏界面未进入输入态）。"
exit 2
