[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptDir = $PSScriptRoot
$targetDir = $scriptDir
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

Write-Host "[1/4] 检测脚本路径" -ForegroundColor Green
Write-Host "  当前脚本目录: $scriptDir" -ForegroundColor White

$runBatPath = (Join-Path $targetDir "run.bat") -replace "\\", "\"
if (-not (Test-Path $runBatPath)) {
    Write-Host "  ✗ 未找到 run.bat 文件" -ForegroundColor Red
    Read-Host "按任意键退出..."
    exit 1
}
Write-Host "  ✓ run.bat 路径检测正常" -ForegroundColor Green

Write-Host ""
Write-Host "[2/4] 设置起始时间" -ForegroundColor Green

# 从 config.json 读取默认值
$defaultStart = "07:00"
$defaultEnd = "22:30"
$defaultInterval = "3"

if (Test-Path $configFile) {
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($config.RUN_START_TIME) { $defaultStart = $config.RUN_START_TIME }
        if ($config.RUN_END_TIME) { $defaultEnd = $config.RUN_END_TIME }
        if ($config.RUN_INTERVAL) { $defaultInterval = $config.RUN_INTERVAL }
    } catch {}
}

Write-Host "  提示：输入格式为 HH:mm，例如 07:00 表示早上7点" -ForegroundColor Gray
Write-Host "  也可以在 config.json 中设置 RUN_START_TIME" -ForegroundColor DarkGray
$startInput = Read-Host "  请输入每天开始执行时间 (默认 $defaultStart)"

if ([string]::IsNullOrWhiteSpace($startInput)) {
    $startInput = $defaultStart
}

try {
    $startTime = [DateTime]::ParseExact($startInput, "HH:mm", $null)
} catch {
    Write-Host "  ✗ 时间格式不正确，请使用 HH:mm 格式（如 07:00）" -ForegroundColor Red
    Read-Host "按任意键退出..."
    exit 1
}

Write-Host "  ✓ 起始时间: " -NoNewline
Write-Host "$($startTime.ToString('HH:mm'))" -ForegroundColor Yellow

Write-Host ""
Write-Host "[3/4] 设置结束时间和间隔" -ForegroundColor Green
Write-Host "  提示：输入格式为 HH:mm，例如 22:30 表示晚上10点半" -ForegroundColor Gray
Write-Host "  也可以在 config.json 中设置 RUN_END_TIME" -ForegroundColor DarkGray
$endInput = Read-Host "  请输入每天最后执行时间 (默认 $defaultEnd)"

if ([string]::IsNullOrWhiteSpace($endInput)) {
    $endInput = $defaultEnd
}

try {
    $endTime = [DateTime]::ParseExact($endInput, "HH:mm", $null)
} catch {
    Write-Host "  ✗ 时间格式不正确，请使用 HH:mm 格式（如 22:30）" -ForegroundColor Red
    Read-Host "按任意键退出..."
    exit 1
}

Write-Host "  ✓ 结束时间: " -NoNewline
Write-Host "$($endTime.ToString('HH:mm'))" -ForegroundColor Yellow

Write-Host ""
Write-Host "  提示：输入数字，单位为小时，例如 3 表示每隔3小时执行一次" -ForegroundColor Gray
Write-Host "  也可以在 config.json 中设置 RUN_INTERVAL" -ForegroundColor DarkGray
$intervalInput = Read-Host "  请输入执行间隔小时数 (默认 $defaultInterval)"

if ([string]::IsNullOrWhiteSpace($intervalInput)) {
    $intervalInput = $defaultInterval
}

try {
    $intervalHours = [int]$intervalInput
    if ($intervalHours -le 0) {
        throw
    }
} catch {
    Write-Host "  ✗ 间隔必须是大于0的数字" -ForegroundColor Red
    Read-Host "按任意键退出..."
    exit 1
}

Write-Host "  ✓ 执行间隔: " -NoNewline
Write-Host "每 $intervalHours 小时" -ForegroundColor Yellow

Write-Host ""
Write-Host "[4/4] 生成执行时间列表" -ForegroundColor Green

$times = @()
$currentTime = $startTime
while ($currentTime -le $endTime) {
    $times += $currentTime.ToString("HH:mm")
    $currentTime = $currentTime.AddHours($intervalHours)
}

Write-Host "  执行时间点:" -ForegroundColor White
foreach ($t in $times) {
    Write-Host "    - $t" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "开始创建任务计划..." -ForegroundColor Green

# 删除旧任务
schtasks /delete /tn "$taskName" /f 2>$null

# 创建 XML
$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Date>$(Get-Date -Format "yyyy-MM-ddTHH:mm:ss")</Date>
    <Author>Administrator</Author>
    <Description>步数随机修改</Description>
    <URI>\步数修改</URI>
  </RegistrationInfo>
  <Triggers>
"@

$today = Get-Date -Format "yyyy-MM-dd"
foreach ($t in $times) {
    $taskXml += @"

    <CalendarTrigger>
      <StartBoundary>$today`T$t`:00+08:00</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
"@
}

$taskXml += @"
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>S4U</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>true</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>true</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$runBatPath</Command>
    </Exec>
  </Actions>
</Task>
"@

$tempXmlFile = [System.IO.Path]::GetTempFileName() + ".xml"
# UTF-16 BOM for schtasks
$utf16 = New-Object System.Text.UnicodeEncoding $false, $true
[System.IO.File]::WriteAllText($tempXmlFile, $taskXml, $utf16)

Write-Host "  创建任务计划中..." -ForegroundColor White
schtasks /create /tn "$taskName" /xml "$tempXmlFile" /f

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ 任务创建成功" -ForegroundColor Green
    Remove-Item $tempXmlFile -ErrorAction SilentlyContinue
} else {
    Write-Host "  ✗ 任务创建失败" -ForegroundColor Red
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
Write-Host "执行时间: " -NoNewline
Write-Host "$($times -join ', ')" -ForegroundColor Yellow
Write-Host "脚本路径: $runBatPath" -ForegroundColor White
Write-Host ""
Write-Host "提示：可以在 Windows 任务计划程序中查看和管理此任务" -ForegroundColor Gray
Write-Host ""
Read-Host "按任意键退出..."
