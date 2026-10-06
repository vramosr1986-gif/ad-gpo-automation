<#
.SYNOPSIS
  Muestra las versiones de las herramientas del lab (VirtualBox, Vagrant, Docker, Git, WSL).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\Test-LabTools.ps1
#>

function Get-ToolVersion {
    param([scriptblock] $Command, [string] $Strip = '')
    try   { ((& $Command) | Select-Object -First 1) -replace $Strip, '' }
    catch { 'NO INSTALADO' }
}

$vbox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'

$tools = @(
    [pscustomobject]@{ Herramienta = 'VirtualBox'; Version = Get-ToolVersion { & $vbox --version } }
    [pscustomobject]@{ Herramienta = 'Vagrant';    Version = Get-ToolVersion { vagrant --version } 'Vagrant ' }
    [pscustomobject]@{ Herramienta = 'Docker';     Version = Get-ToolVersion { docker --version } 'Docker version ' }
    [pscustomobject]@{ Herramienta = 'Git';        Version = Get-ToolVersion { git --version } 'git version ' }
)

Write-Host "`n=== Herramientas del lab ===" -ForegroundColor Cyan
$tools | Format-Table -AutoSize | Out-Host

Write-Host "=== WSL ===" -ForegroundColor Cyan
wsl -l -v
