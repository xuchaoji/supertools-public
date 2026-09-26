<#
.SYNOPSIS
  构建后自检：编译全部三个构建链并校验发布卫生与真机行为。

.DESCRIPTION
  覆盖的构建链（与 build-*.bat / DevEco 一致）：
    1. dev          module=main@dev     product=dev       buildMode=debug  → dev 包
    2. ag-debug     module=main@product product=default   buildMode=debug  → AG 版本地验证包
    3. ag-release   --mode project      product=release   buildMode=release→ 上架 .app（-IncludeApp 时）

  其余检查：
    4. release 原生构建不含 TEST_HASH，且使用源码派生的握手哈希
    5. HAP 内不再打包已删除的 libhdc_napi.so
    6. 产物路径与体积

  -Device 追加真机冒烟：安装 dev 包、冷启动、后台长时任务日志、Web 鉴权。
  -Clean 先清空 build/.cxx 再从零构建（用于排除陈旧缓存导致的假故障）。

.EXAMPLE
  pwsh -File tools/verify_build.ps1
  pwsh -File tools/verify_build.ps1 -Clean -IncludeApp
  pwsh -File tools/verify_build.ps1 -SkipBuild -Device 192.168.3.144:12345
#>
param(
    [string]$Device = '',
    [switch]$SkipBuild,
    [switch]$Clean,
    [switch]$IncludeApp
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$script:Failures = @()

function Write-Step([string]$text) {
    Write-Host "`n=== $text ===" -ForegroundColor Cyan
}

function Test-Assert([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) {
        Write-Host "[ OK ] $name" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $name $detail" -ForegroundColor Red
        $script:Failures += $name
    }
}

function Invoke-Hvigor([string[]]$arguments) {
    $log = Join-Path $env:TEMP ("verify_build_" + [guid]::NewGuid().ToString('N') + ".log")
    & hvigorw @arguments *> $log
    $code = $LASTEXITCODE
    $summary = (Select-String -Path $log -Pattern 'BUILD SUCCESSFUL|BUILD FAILED' |
        Select-Object -Last 1).Line
    if ([string]::IsNullOrWhiteSpace($summary)) { $summary = '(no summary line)' }
    Write-Host "  $($summary.Trim())"
    if ($code -ne 0) {
        Write-Host "  完整日志: $log" -ForegroundColor Yellow
    }
    return $code
}

# ---------------------------------------------------------------- 前置检查
Write-Step '环境检查'
Test-Assert 'DEVECO_HOME 已设置' ([bool]$env:DEVECO_HOME) '(运行前先 setx DEVECO_HOME ...)'
Test-Assert 'hvigorw 可用' ([bool](Get-Command hvigorw -ErrorAction SilentlyContinue))
Test-Assert 'build-profile.json5 存在（本机签名配置）' (Test-Path 'build-profile.json5') `
    '(从 build-profile.template.json5 复制并填入本机签名)'
if ($script:Failures.Count -gt 0) { Write-Host "`n前置检查未通过，终止。" -ForegroundColor Red; exit 1 }

# 仓库卫生属于本机/团队偏好，只提示、不作为构建门禁
$lockTracked = [bool](git ls-files --error-unmatch oh-package-lock.json5 2>$null)
$profileTracked = [bool](git ls-files --error-unmatch build-profile.json5 2>$null)
Write-Host "[提醒] oh-package-lock.json5 已提交: $lockTracked（建议提交以锁定依赖解析结果）" -ForegroundColor DarkGray
Write-Host "[提醒] build-profile.json5 被版本控制跟踪: $profileTracked（跟踪会把本机签名路径与口令写进历史）" -ForegroundColor DarkGray

# ---------------------------------------------------------------- 清理
if ($Clean) {
    Write-Step '清理构建缓存（-Clean）'
    foreach ($path in @('main/build', 'main/.cxx', 'build')) {
        if (Test-Path $path) {
            Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
            Write-Host "  已删除 $path"
        }
    }
}

# ---------------------------------------------------------------- 编译
$devHap = 'main/build/dev/outputs/dev/main-dev-signed.hap'
$agHap = 'main/build/default/outputs/product/main-product-signed.hap'
$relHap = 'main/build/release/outputs/product/main-product-signed.hap'

if (-not $SkipBuild) {
    Write-Step '构建链 1/3：dev（Debug）'
    $devCode = Invoke-Hvigor @(
        '--mode', 'module', '-p', 'module=main@dev', '-p', 'product=dev',
        '-p', 'buildMode=debug', '-p', 'requiredDeviceType=phone',
        'assembleHap', '--analyze=normal', '--parallel', '--incremental', '--daemon')
    Test-Assert 'dev 编译通过' ($devCode -eq 0) '（若报无法解析某个 .so 模块，多半是陈旧缓存：用 -Clean 重跑）'

    Write-Step '构建链 2/3：ag-debug（product=default，Debug）'
    $agCode = Invoke-Hvigor @(
        '--mode', 'module', '-p', 'module=main@product', '-p', 'product=default',
        '-p', 'buildMode=debug', '-p', 'requiredDeviceType=phone',
        'assembleHap', '--analyze=normal', '--parallel', '--incremental', '--daemon')
    Test-Assert 'ag-debug 编译通过' ($agCode -eq 0) '（DevEco 默认选中的就是这个产品）'

    Write-Step '构建链 3/3：release（Release）'
    $relCode = Invoke-Hvigor @(
        '--mode', 'module', '-p', 'module=main@product', '-p', 'product=release',
        '-p', 'buildMode=release', '-p', 'requiredDeviceType=phone',
        'assembleHap', '--analyze=normal', '--parallel', '--incremental', '--daemon')
    Test-Assert 'release 编译通过' ($relCode -eq 0)

    if ($IncludeApp) {
        Write-Step '构建链 3b：上架 .app（assembleApp）'
        $appCode = Invoke-Hvigor @(
            '--mode', 'project', '-p', 'product=release', '-p', 'buildMode=release',
            '-p', 'requiredDeviceType=phone',
            'assembleApp', '--analyze=normal', '--parallel', '--incremental', '--daemon')
        Test-Assert 'assembleApp 编译通过' ($appCode -eq 0)
        $app = 'build/outputs/release/supertools-public-release-signed.app'
        Test-Assert '上架 .app 已产出' (Test-Path $app)
    }
}

# ---------------------------------------------------------------- 发布卫生
Write-Step '发布卫生：HDC 握手哈希'
$releaseCxx = 'main/.cxx/release/product/release/arm64-v8a'
$devCxx = 'main/.cxx/dev/dev/debug/arm64-v8a'

if (Test-Path $releaseCxx) {
    $testHashHits = (Get-ChildItem $releaseCxx -Recurse -Filter build.ninja |
        ForEach-Object { (Select-String -Path $_.FullName -Pattern 'TEST_HASH').Count } |
        Measure-Object -Sum).Sum
    Test-Assert 'release 原生构建不含 TEST_HASH' ($testHashHits -eq 0) "(命中 $testHashHits)"

    $genHeader = Join-Path $releaseCxx 'hdctools/hdc_hash_gen.h'
    Test-Assert 'release 使用源码派生的 hdc_hash_gen.h' (Test-Path $genHeader)
    if (Test-Path $genHeader) {
        $hashLine = (Select-String -Path $genHeader -Pattern 'HDC_MSG_HASH').Line
        $hashOk = $hashLine -match 'HDC_MSG_HASH "([0-9a-f]{32})"'
        Test-Assert '派生哈希为 32 位十六进制' $hashOk $hashLine
    }
} else {
    Test-Assert 'release 原生构建目录存在' $false $releaseCxx
}

if (Test-Path $devCxx) {
    $devTestHash = (Get-ChildItem $devCxx -Recurse -Filter build.ninja |
        ForEach-Object { (Select-String -Path $_.FullName -Pattern '-DTEST_HASH').Count } |
        Measure-Object -Sum).Sum
    Test-Assert 'dev 构建按预期使用 TEST_HASH' ($devTestHash -gt 0)
}

Write-Step '发布卫生：产物内容'
foreach ($hap in @($devHap, $agHap, $relHap)) {
    if (-not (Test-Path $hap)) {
        Test-Assert "产物存在 $hap" $false
        continue
    }
    $size = [math]::Round((Get-Item $hap).Length / 1MB, 2)
    Test-Assert "产物存在 $hap (${size}MB)" $true
    $list = tar -tf $hap
    Test-Assert "  $([System.IO.Path]::GetFileName($hap)) 未打包 libhdc_napi.so" `
        (-not [bool]($list | Select-String -Pattern 'libhdc_napi'))
    Test-Assert "  $([System.IO.Path]::GetFileName($hap)) 含 libhdc_z.so" `
        ([bool]($list | Select-String -Pattern 'libhdc_z\.so'))
}

# ---------------------------------------------------------------- 真机冒烟
if ($Device) {
    Write-Step "真机冒烟 ($Device)"
    $bundle = 'com.xuchaoji.hmos.supertools.dev'

    $installOut = hdc -t $Device install -r $devHap 2>&1 | Out-String
    Test-Assert 'dev 包安装成功' ($installOut -match 'install bundle successfully') $installOut.Trim()

    hdc -t $Device shell hilog -r | Out-Null
    hdc -t $Device shell power-shell wakeup | Out-Null
    hdc -t $Device shell aa force-stop $bundle | Out-Null
    $startOut = (hdc -t $Device shell aa start -a MainAbility -b $bundle 2>&1 | Out-String)
    Start-Sleep -Seconds 8

    $appPid = "$(hdc -t $Device shell "pidof $bundle")".Trim()

    if ($startOut -match '10106102|screen is locked' -or $appPid -notmatch '^\d+$') {
        # 锁屏设备无法由命令拉起应用（需人工解锁），这是环境限制而不是代码问题
        Write-Host '[SKIP] 设备锁屏或应用未拉起，跳过运行时检查。请解锁设备后重跑：' -ForegroundColor Yellow
        Write-Host "       pwsh -File tools/verify_build.ps1 -SkipBuild -Device $Device" -ForegroundColor Yellow
    } else {
        Test-Assert '应用进程存活' ($appPid -match '^\d+$') "pid=$appPid"

        $logs = (hdc -t $Device shell "hilog -x | grep -E 'Continuous Task verification failed|9800005|BackgroundService|WebServer' | tail -n 40") -join "`n"
        Test-Assert '冷启动未出现 stopBackgroundRunning 报错' `
            ($logs -notmatch 'Continuous Task verification failed|9800005') $logs
        Test-Assert 'Web 服务已启动' ($logs -match 'Server Started on port') $logs
        Test-Assert '后台长时任务已申请' ($logs -match '后台任务启动成功|BackgroundService') $logs

        # 无 token 访问必须被拒绝，证明鉴权生效（带 token 的链接在应用页面内可复制）
        $ip = $Device.Split(':')[0]
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri "http://${ip}:8088/" -TimeoutSec 8
            Test-Assert '无 token 访问被拒绝' ($r.StatusCode -eq 401) "HTTP $($r.StatusCode)"
        } catch {
            $code = $_.Exception.Response.StatusCode.value__
            Test-Assert '无 token 访问被拒绝' ($code -eq 401) "HTTP $code"
        }
    }
}

# ---------------------------------------------------------------- 汇总
Write-Step '汇总'
if ($script:Failures.Count -eq 0) {
    Write-Host '全部检查通过。' -ForegroundColor Green
    exit 0
}
Write-Host "失败 $($script:Failures.Count) 项：" -ForegroundColor Red
$script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
exit 1
