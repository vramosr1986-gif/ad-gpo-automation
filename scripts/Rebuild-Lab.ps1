<#
.SYNOPSIS
  Recrea el lab desde cero con un solo comando.

.DESCRIPTION
  1. Borra y vuelve a crear DC01, DC02 y SRV01 (vagrant destroy + vagrant up).
  2. Espera a que cada VM responda por WinRM en su IP del lab.
  3. Aplica playbooks/site.yml en WSL (el despliegue).
  4. Aplica playbooks/site.yml otra vez: tiene que terminar con changed=0 (idempotencia).

  La salida de cada ejecución de site.yml se guarda en docs/evidencias/. No contiene
  contraseñas: salen del vault y las tareas con secretos llevan no_log.

.PARAMETER SinDestruir
  No toca las VMs: solo aplica site.yml dos veces. Sirve para relanzar si falla un playbook.

.EXAMPLE
  .\scripts\Rebuild-Lab.ps1
  .\scripts\Rebuild-Lab.ps1 -SinDestruir
#>
[CmdletBinding()]
param([switch] $SinDestruir)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo
$ips = '192.168.56.10', '192.168.56.11', '192.168.56.20'   # DC01, DC02, SRV01 (inventories/lab/hosts.yml)
$inicio = Get-Date

function Write-Paso([string] $texto) { Write-Host "`n=== $texto ===" -ForegroundColor Cyan }

# Ejecuta site.yml en WSL y guarda la salida en docs/evidencias/<nombre>.txt.
# ANSIBLE_CONFIG explícito: en /mnt/c Ansible ignora el ansible.cfg del directorio.
function Invoke-Site([string] $nombre) {
    $wslRepo = (wsl.exe -e wslpath -a ($repo -replace '\\', '/')).Trim()
    $log = "docs/evidencias/$nombre.txt"
    $bash = "source ~/.venvs/ansible/bin/activate && cd '$wslRepo' && " +
            "ANSIBLE_CONFIG=`$PWD/ansible.cfg ANSIBLE_NOCOLOR=1 ansible-playbook playbooks/site.yml 2>&1 | tee $log; " +
            "exit `${PIPESTATUS[0]}"
    wsl.exe -e bash -lc $bash
    if ($LASTEXITCODE) { throw "site.yml ha fallado: revisa $log" }
    return (Join-Path $repo $log)
}

if (-not $SinDestruir) {
    Write-Paso '1/4 Borrar y recrear las VMs'
    $respuesta = Read-Host 'Se borran DC01, DC02 y SRV01 con todo lo que tienen. Escribe SI para seguir'
    if ($respuesta -cne 'SI') { Write-Host 'Cancelado: no se ha tocado nada.'; return }

    vagrant destroy -f
    if ($LASTEXITCODE) { throw 'vagrant destroy ha fallado' }
    vagrant up --provider vmware_desktop
    if ($LASTEXITCODE) { throw 'vagrant up ha fallado' }
}

Write-Paso '2/4 Esperar a WinRM en la IP del lab'
foreach ($ip in $ips) {
    $ok = $false
    for ($i = 1; $i -le 30 -and -not $ok; $i++) {
        $ok = Test-NetConnection $ip -Port 5985 -InformationLevel Quiet -WarningAction SilentlyContinue
        if (-not $ok) { Start-Sleep -Seconds 10 }
    }
    if (-not $ok) { throw "$ip no responde por WinRM (puerto 5985) después de 5 minutos" }
    Write-Host "$ip responde por WinRM"
}

Write-Paso '3/4 Desplegar el AD (playbooks/site.yml)'
Invoke-Site 'paso11-site-1-despliegue' | Out-Null

Write-Paso '4/4 Comprobar la idempotencia (site.yml otra vez)'
$log2 = Invoke-Site 'paso11-site-2-idempotencia'
$conCambios = Select-String -Path $log2 -Pattern 'changed=[1-9]' -Encoding UTF8
if ($conCambios) {
    Write-Host "`nNo es idempotente: la segunda ejecución ha cambiado algo:" -ForegroundColor Yellow
    $conCambios | ForEach-Object { Write-Host "  $($_.Line)" }
} else {
    Write-Host "`nIdempotente: la segunda ejecución termina con changed=0 en todas las VMs" -ForegroundColor Green
}

$duracion = (Get-Date) - $inicio
Write-Host ("Tiempo total: {0:hh\:mm\:ss}. Salidas en docs\evidencias\paso11-site-*.txt" -f $duracion)
