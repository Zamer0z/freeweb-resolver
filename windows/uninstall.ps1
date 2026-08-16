# Удаление freeweb-resolver на Windows. Не проверено на реальной машине —
# см. предупреждение в install.ps1. Запускать от имени администратора.

$ErrorActionPreference = "Continue"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Запусти этот скрипт от имени администратора." -ForegroundColor Yellow
    exit 1
}

$RepoDir = Split-Path -Parent $PSScriptRoot

Write-Host "==> Останавливаю и убираю задания автозапуска"
Unregister-ScheduledTask -TaskName "freeweb-resolver" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "freeweb-resolver-ipfs" -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "==> Убираю CA из доверенных"
$caPath = "$RepoDir\ca\ca.crt"
if (Test-Path $caPath) {
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $caPath
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $store.Open("ReadWrite")
    $store.Remove($cert)
    $store.Close()
}

Write-Host "==> Убираю правила NRPT"
Get-DnsClientNrptRule | Where-Object { $_.Namespace -eq ".eth" -or $_.Namespace -eq ".test" } | Remove-DnsClientNrptRule -Force -ErrorAction SilentlyContinue

Write-Host "==> Удаляю сам CA (приватный ключ)"
Remove-Item -Recurse -Force "$RepoDir\ca" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Готово. IPFS-репозиторий и сам код не тронуты."
