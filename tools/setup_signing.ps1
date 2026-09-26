<#
.SYNOPSIS
  准备本机签名配置（build-profile.json5）。

.DESCRIPTION
  build-profile.json5 不在版本控制内：它含本机签名物料的绝对路径与
  DevEco 生成的机器绑定加密口令，提交它对别人没用、对本机是泄露。

  hvigor 不支持在 build-profile.json5 里 include 外部文件，签名物料必须内联在
  signingConfigs[].material 中，所以「本机配置」就是这一整个文件——把它放到
  仓库根目录即可编译，本脚本负责把模板安装成它。

  两种来源：
    1. -From <路径>：从已有的本机 profile 复制（换机迁移、从备份恢复）
    2. 不带参数    ：从 build-profile.template.json5 复制，之后手工填占位符，
                    或用 DevEco Studio 的 Signing Configs 自动生成

.EXAMPLE
  pwsh -File tools/setup_signing.ps1
  pwsh -File tools/setup_signing.ps1 -From D:\backup\build-profile.json5
  pwsh -File tools/setup_signing.ps1 -Force      # 覆盖已存在的本机配置
#>
param(
    [string]$From = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$target = Join-Path $repoRoot 'build-profile.json5'
$template = Join-Path $repoRoot 'build-profile.template.json5'

if ((Test-Path $target) -and -not $Force) {
    $text = Get-Content $target -Raw
    if ($text -match '<HOME>|<project>|DevEco 生成的加密口令') {
        Write-Host '[WARN] build-profile.json5 已存在，但仍含模板占位符，无法签名。' -ForegroundColor Yellow
        Write-Host '       请填写真实路径与口令，或用 DevEco Studio 的 Signing Configs 生成后重试。'
        Write-Host '       （如需用其他文件覆盖：加 -Force，或 -From <路径> -Force）'
        exit 1
    }
    Write-Host '[ OK ] build-profile.json5 已存在且不像是模板，无需处理。' -ForegroundColor Green
    exit 0
}

if ($From) {
    if (-not (Test-Path $From)) { throw "找不到来源文件: $From" }
    Copy-Item $From $target -Force
    Write-Host "[ OK ] 已从 $From 安装本机签名配置" -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $template)) { throw "找不到模板: $template" }
Copy-Item $template $target -Force
Write-Host '[ OK ] 已从模板生成 build-profile.json5' -ForegroundColor Green
Write-Host ''
Write-Host '接下来二选一：' -ForegroundColor Cyan
Write-Host '  A) DevEco Studio：打开工程 → Project Structure → Signing Configs → 勾选自动签名（推荐，口令由 IDE 生成）'
Write-Host '  B) 手工编辑 build-profile.json5，把 <HOME> / <project> / <口令> 替换为本机实际值'
Write-Host ''
Write-Host '说明：default/dev 的调试签名物料在 ~/.ohos/config/ 下，由 DevEco 管理；'
Write-Host '      release 物料在仓库内被忽略的 sign/ 目录；口令串与机器绑定，不能跨机拷贝。'
exit 0
