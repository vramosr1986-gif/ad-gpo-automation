#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Prepara este equipo para entrar por PowerShell remoto (Enter-PSSession) en las VMs del lab.

.DESCRIPTION
  Ansible no lo necesita (se conecta desde WSL con pywinrm). Es para trabajar a mano:
    Enter-PSSession 192.168.56.10 -Credential LAB\vagrant
  Por IP, Windows solo se conecta a equipos que estén en TrustedHosts. Este script añade
  las IP del lab (y 127.0.0.1, que usa vagrant powershell con los puertos reenviados) sin
  borrar las que ya hubiera. Idempotente: si ya están, no cambia nada.

.EXAMPLE
  # PowerShell como administrador, una sola vez
  .\scripts\Enable-LabRemoting.ps1
#>
$ErrorActionPreference = 'Stop'
$lab = '127.0.0.1', '192.168.56.10', '192.168.56.11', '192.168.56.20'   # vagrant powershell, DC01, DC02, SRV01

# La configuración de WSMan solo se puede leer y cambiar con el servicio WinRM arrancado
if ((Get-Service WinRM).Status -ne 'Running') { Start-Service WinRM }

$actual = @((Get-Item WSMan:\localhost\Client\TrustedHosts).Value -split ',' |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })
$faltan = @($lab | Where-Object { $_ -notin $actual })

if ('*' -in $actual) {
    Write-Host 'TrustedHosts ya es * (todos los equipos): no hace falta añadir nada.'
} elseif ($faltan) {
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value (($actual + $faltan) -join ',') -Force
    Write-Host "Añadidas a TrustedHosts: $($faltan -join ', ')" -ForegroundColor Green
} else {
    Write-Host 'Las IP del lab ya estaban en TrustedHosts: no se ha cambiado nada.' -ForegroundColor Green
}
Write-Host "TrustedHosts: $((Get-Item WSMan:\localhost\Client\TrustedHosts).Value)"
