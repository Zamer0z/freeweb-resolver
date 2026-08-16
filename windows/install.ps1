# Установка freeweb-resolver на Windows.
#
# ВНИМАНИЕ: этот скрипт написан по документации Microsoft и НИ РАЗУ не
# запускался на настоящей Windows-машине — у автора её физически не было
# под рукой. Возможны ошибки в именах командлетов, правах доступа или
# деталях NRPT/Планировщика заданий. Полностью отдельный путь от
# macOS/Linux-версий — ничего общего в исполнении.
#
# Запускать из PowerShell "от имени администратора" — нужно для NRPT
# (подмена DNS только для .eth/.test) и для доверенного корневого
# сертификата в системном хранилище.

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Запусти этот скрипт от имени администратора (правый клик на PowerShell -> 'Запуск от имени администратора')." -ForegroundColor Yellow
    exit 1
}

$RepoDir = Split-Path -Parent $PSScriptRoot
$SdkDir = "$env:USERPROFILE\sdk"
$GoBin = "$SdkDir\go\bin\go.exe"
$IpfsBin = "$SdkDir\kubo\kubo\ipfs.exe"
$env:IPFS_PATH = "$env:USERPROFILE\.ipfs-freeweb"
$LogDir = "$env:LOCALAPPDATA\freeweb-resolver\logs"

Write-Host "==> Проверяю Go"
if (-not (Test-Path $GoBin)) {
    Write-Host "    ставлю Go..."
    New-Item -ItemType Directory -Force -Path $SdkDir | Out-Null
    Invoke-WebRequest -Uri "https://go.dev/dl/go1.23.4.windows-amd64.zip" -OutFile "$env:TEMP\freeweb-go.zip"
    Expand-Archive -Path "$env:TEMP\freeweb-go.zip" -DestinationPath $SdkDir -Force
    Remove-Item "$env:TEMP\freeweb-go.zip"
}
& $GoBin version

Write-Host "==> Проверяю kubo (IPFS-нода)"
if (-not (Test-Path $IpfsBin)) {
    Write-Host "    ставлю kubo..."
    New-Item -ItemType Directory -Force -Path "$SdkDir\kubo" | Out-Null
    $versions = (Invoke-WebRequest -Uri "https://dist.ipfs.tech/kubo/versions").Content.Trim() -split "`n"
    $latest = $versions[-1]
    Invoke-WebRequest -Uri "https://dist.ipfs.tech/kubo/$latest/kubo_${latest}_windows-amd64.zip" -OutFile "$env:TEMP\freeweb-kubo.zip"
    Expand-Archive -Path "$env:TEMP\freeweb-kubo.zip" -DestinationPath "$SdkDir\kubo" -Force
    Remove-Item "$env:TEMP\freeweb-kubo.zip"
}
& $IpfsBin version

Write-Host "==> Собираю resolver"
Push-Location $RepoDir
& $GoBin build -o resolver.exe .
Pop-Location

Write-Host "==> Инициализирую IPFS-репозиторий (если ещё нет)"
if (-not (Test-Path "$env:IPFS_PATH\config")) {
    & $IpfsBin init
}

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Write-Host "==> Настраиваю автозапуск через Планировщик заданий"
Write-Host "    (resolver.exe — обычная консольная программа, не реализует протокол"
Write-Host "    Windows Service Control Manager, поэтому это не sc.exe-служба, а"
Write-Host "    задание с триггером 'при входе' и перезапуском при падении)"

$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -DontStopOnIdleEnd

$resolverAction = New-ScheduledTaskAction -Execute "$RepoDir\resolver.exe" -WorkingDirectory $RepoDir
Register-ScheduledTask -TaskName "freeweb-resolver" -Action $resolverAction -Trigger $trigger -Settings $settings -Force | Out-Null

$ipfsAction = New-ScheduledTaskAction -Execute $IpfsBin -Argument "daemon" -WorkingDirectory $RepoDir
Register-ScheduledTask -TaskName "freeweb-resolver-ipfs" -Action $ipfsAction -Trigger $trigger -Settings $settings -Force | Out-Null

Start-ScheduledTask -TaskName "freeweb-resolver-ipfs"
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName "freeweb-resolver"

Write-Host "==> Жду, пока resolver создаст локальный CA..."
$caPath = "$RepoDir\ca\ca.crt"
$found = $false
for ($i = 0; $i -lt 20; $i++) {
    if (Test-Path $caPath) { $found = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $found) {
    Write-Error "CA не появился за 20 секунд — проверь логи в $LogDir"
    exit 1
}

Write-Host "==> Добавляю CA в доверенные корневые сертификаты"
Import-Certificate -FilePath $caPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null

Write-Host "==> Настраиваю split-DNS (NRPT) для .eth и .test"
Add-DnsClientNrptRule -Namespace ".eth" -NameServers "127.0.0.1" -ErrorAction SilentlyContinue | Out-Null
Add-DnsClientNrptRule -Namespace ".test" -NameServers "127.0.0.1" -ErrorAction SilentlyContinue | Out-Null

Write-Host ""
Write-Host "Готово! Открой в браузере: https://vitalik.eth:15443/"
Write-Host ""
Write-Host "НАПОМИНАНИЕ: этот скрипт не проверен на реальной Windows. Если что-то" -ForegroundColor Yellow
Write-Host "не сработало — заведи issue в репозитории с текстом ошибки." -ForegroundColor Yellow
