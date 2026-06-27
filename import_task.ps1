[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = $PSScriptRoot
$targetDir = $scriptDir
$xmlFile = Join-Path $scriptDir "cron.xml"
$configFile = Join-Path $scriptDir "config.json"
$taskName = "\步数修改"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "正在请求管理员权限..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "任务计划程序自动导入工具" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] 检测脚本路径" -ForegroundColor Green
Write-Host "  当前脚本目录: $scriptDir" -ForegroundColor White

$defaultTime = "22:30"
if (Test-Path $configFile) {
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($config.RUN_TIME) {
            $defaultTime = $config.RUN_TIME
        }
    } catch {}
}

Write-Host ""
Write-Host "[2/3] 设置运行时间" -ForegroundColor Green
Write-Host "  提示：输入格式为 HH:mm，例如 22:30 表示晚上10点半" -ForegroundColor Gray
$timeInput = Read-Host "  请输入每天运行时间 (默认 $defaultTime)"

if ([string]::IsNullOrWhiteSpace($timeInput)) {
    $timeInput = $defaultTime
}

$runTime = $null
try {
    $runTime = [DateTime]::ParseExact($timeInput, "HH:mm", $null)
} catch {
    Write-Host "  ✗ 时间格式不正确，请使用 HH:mm 格式（如 22:30）" -ForegroundColor Red
    Read-Host "按任意键退出..."
    exit 1
}

$timeString = $runTime.ToString("HH:mm")
Write-Host "  ✓ 运行时间已设置为: $timeString" -ForegroundColor Green

Write-Host ""
Write-Host "[3/3] 更新任务XML并导入" -ForegroundColor Green
$runBatPath = (Join-Path $targetDir "run.bat") -replace "\\", "\"
Write-Host "  更新任务运行路径为: $runBatPath" -ForegroundColor White

if (-not (Test-Path $runBatPath)) {
    Write-Host "  ✗ 未找到 run.bat 文件" -ForegroundColor Red
    Read-Host "按任意键退出..."
    exit 1
}

[xml]$xmlContent = Get-Content $xmlFile
$xmlContent.Task.Actions.Exec.Command = $runBatPath

$startBoundary = Get-Date -Format "yyyy-MM-dd"
$startBoundary += "T" + $timeString + ":00+08:00"
$xmlContent.Task.Triggers.CalendarTrigger.StartBoundary = $startBoundary

$tempXmlFile = [System.IO.Path]::GetTempFileName() + ".xml"
$xmlContent.Save($tempXmlFile)
Write-Host "  ✓ XML文件更新成功" -ForegroundColor Green

schtasks /create /tn "$taskName" /xml "$tempXmlFile" /f
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ 任务导入成功" -ForegroundColor Green
    Remove-Item $tempXmlFile -ErrorAction SilentlyContinue
} else {
    Write-Host "  ✗ 任务导入失败" -ForegroundColor Red
    Remove-Item $tempXmlFile -ErrorAction SilentlyContinue
    Read-Host "按任意键退出..."
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "所有操作完成！" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "任务名称: $taskName" -ForegroundColor White
Write-Host "运行时间: 每天 $timeString" -ForegroundColor White
Write-Host "脚本目录: $targetDir" -ForegroundColor White
Write-Host ""
Read-Host "按任意键退出..."
