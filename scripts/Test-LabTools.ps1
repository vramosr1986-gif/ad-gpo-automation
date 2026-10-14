<#
.SYNOPSIS
  Muestra las versiones de las herramientas del lab (VMware Workstation, Vagrant, Docker, Git, WSL).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\Test-LabTools.ps1
#>

function Get-ToolVersion {
    param([scriptblock] $Command, [string] $Strip = '')
    try   { ((& $Command) | Select-Object -First 1) -replace $Strip, '' }
    catch { 'NO INSTALADO' }
}

$vmware = Join-Path $env:ProgramFiles 'VMware\VMware Workstation\vmware.exe'

$tools = @(
    [pscustomobject]@{ Herramienta = 'VMware Workstation'; Version = Get-ToolVersion { (Get-Item $vmware -ErrorAction Stop).VersionInfo.ProductVersion } }
    [pscustomobject]@{ Herramienta = 'Vagrant';            Version = Get-ToolVersion { vagrant --version } 'Vagrant ' }
    [pscustomobject]@{ Herramienta = 'Plugin VMware';      Version = Get-ToolVersion { vagrant plugin list | Select-String 'vagrant-vmware-desktop' } '^vagrant-vmware-desktop ' }
    [pscustomobject]@{ Herramienta = 'Servicio VagrantVMware'; Version = Get-ToolVersion { (Get-Service VagrantVMware -ErrorAction Stop).Status } }
    [pscustomobject]@{ Herramienta = 'Docker';             Version = Get-ToolVersion { docker --version } 'Docker version ' }
    [pscustomobject]@{ Herramienta = 'Git';                Version = Get-ToolVersion { git --version } 'git version ' }
)

Write-Host "`n=== Herramientas del lab ===" -ForegroundColor Cyan
$tools | Format-Table -AutoSize | Out-Host

Write-Host "=== WSL ===" -ForegroundColor Cyan
wsl -l -v
