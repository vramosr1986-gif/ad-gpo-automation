<#
.SYNOPSIS
  Monta el lab completo con un solo comando, desde un equipo con las herramientas instaladas.

.DESCRIPTION
  1. Comprueba que el host tiene todo lo necesario (VMware, Vagrant y su plugin, la
     red VMnet1, WSL). Si falta algo, para y dice en qué paso del README se instala.
  2. Prepara WSL como nodo de control (scripts/setup-wsl.sh): Ansible, colecciones y
     vault. Lo que ya está, no lo toca.
  3. Crea las VMs (vagrant up). Si ya existen y están encendidas, no hace nada.
  4. Espera a que cada VM responda por WinRM en su IP del lab.
  5. Configura todo el AD con playbooks/site.yml: bosque, dominio hijo, DNS, OU,
     SRV01 unido al dominio, grupos y usuarios de prueba.

  Todo es idempotente: sobre un lab ya montado se puede lanzar otra vez y no cambia nada.
  La salida de Ansible se guarda en logs/ (fuera de git).

.PARAMETER ComprobarIdempotencia
  Aplica site.yml una segunda vez y avisa si algún host termina con changed distinto de 0.

.EXAMPLE
  .\scripts\Deploy-Lab.ps1
  .\scripts\Deploy-Lab.ps1 -ComprobarIdempotencia
#>
[CmdletBinding()]
param([switch] $ComprobarIdempotencia)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo
$vms = [ordered]@{ DC01 = '192.168.56.10'; DC02 = '192.168.56.11'; SRV01 = '192.168.56.20' }   # inventories/lab/hosts.yml
$inicio = Get-Date
# WSL escribe en UTF-8: sin esto, PowerShell 5.1 muestra mal las tildes de la salida de Ansible
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Write-Paso([string] $texto) { Write-Host "`n=== $texto ===" -ForegroundColor Cyan }

# Aplica site.yml y guarda la salida en logs/ ($script:log). ANSIBLE_CONFIG explícito: en
# /mnt/c Ansible no lee el ansible.cfg del directorio si la carpeta permite escribir a todos.
# Dentro del comando de bash, solo comillas simples: PowerShell 5.1 rompe las dobles al
# pasarlas a un ejecutable. La salida de wsl.exe no se captura: va directa a la pantalla.
function Invoke-Site([string] $nombre) {
    $relativo = "logs/$nombre-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
    New-Item -ItemType Directory -Force (Join-Path $repo 'logs') | Out-Null
    wsl.exe -e bash -lc ("source ~/.venvs/ansible/bin/activate && cd '$wslRepo' && " +
                         "ANSIBLE_CONFIG=`$PWD/ansible.cfg ANSIBLE_NOCOLOR=1 ansible-playbook playbooks/site.yml 2>&1 | tee $relativo; " +
                         "exit `${PIPESTATUS[0]}") | Out-Host
    if ($LASTEXITCODE) { throw "site.yml ha fallado: revisa $relativo. Corrige y vuelve a lanzar este script." }
    $script:log = Join-Path $repo $relativo
}

# --- 1. Requisitos del host --------------------------------------------------
Write-Paso '1/5 Comprobar los requisitos del host'
$vmrun = Join-Path ${env:ProgramFiles(x86)} 'VMware\VMware Workstation\vmrun.exe'
if (-not (Test-Path $vmrun)) { $vmrun = Join-Path $env:ProgramFiles 'VMware\VMware Workstation\vmrun.exe' }

$requisitos = @(
    @{ Que = 'VMware Workstation';               Ok = { Test-Path $vmrun };                                                          Paso = 'Paso 1' }
    @{ Que = 'Vagrant';                          Ok = { [bool](Get-Command vagrant -ErrorAction SilentlyContinue) };                 Paso = 'Paso 1' }
    @{ Que = 'Plugin vagrant-vmware-desktop';    Ok = { (vagrant plugin list) -match 'vagrant-vmware-desktop' };                     Paso = 'Paso 1' }
    @{ Que = 'Servicio VagrantVMware arrancado'; Ok = { (Get-Service VagrantVMware -ErrorAction SilentlyContinue).Status -eq 'Running' }; Paso = 'Paso 1' }
    @{ Que = 'Red VMnet1 con 192.168.56.1';      Ok = { [bool](Get-NetIPAddress -IPAddress 192.168.56.1 -ErrorAction SilentlyContinue) }; Paso = 'Paso 3' }
    @{ Que = 'WSL con una distribución Linux';   Ok = { (wsl.exe -e true) 2>$null; $LASTEXITCODE -eq 0 };                            Paso = 'Paso 4' }
)
$faltan = @()
foreach ($r in $requisitos) {
    $ok = try { [bool](& $r.Ok) } catch { $false }
    $color = if ($ok) { 'Green' } else { 'Red' }
    Write-Host ('  {0,-34} {1}' -f $r.Que, $(if ($ok) { 'OK' } else { "FALTA (README, $($r.Paso))" })) -ForegroundColor $color
    if (-not $ok) { $faltan += $r.Que }
}
if ($faltan) { throw "Faltan requisitos del host: $($faltan -join ', '). Instálalos y vuelve a lanzar el script." }

# Opcional: solo para entrar a mano con Enter-PSSession (Ansible no lo necesita). Se lee
# del registro porque WSMan:\ exige administrador y el servicio WinRM arrancado.
$trusted = try { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Client' -Name trusted_hosts).trusted_hosts } catch { '' }
$sinTrusted = @($vms.Values | Where-Object { $trusted -ne '*' -and $_ -notin ($trusted -split ',' | ForEach-Object { $_.Trim() }) })
if ($sinTrusted) {
    Write-Host ('  {0,-34} {1}' -f 'TrustedHosts (opcional)', "faltan $($sinTrusted -join ', '): .\scripts\Enable-LabRemoting.ps1 como administrador") -ForegroundColor Yellow
} else {
    Write-Host ('  {0,-34} {1}' -f 'TrustedHosts (opcional)', 'OK') -ForegroundColor Green
}

$wslRepo = (wsl.exe -e wslpath -a ($repo -replace '\\', '/')).Trim()

# --- 2. Nodo de control en WSL -----------------------------------------------
Write-Paso '2/5 Preparar Ansible en WSL (scripts/setup-wsl.sh)'
wsl.exe -e bash -lc "bash '$wslRepo/scripts/setup-wsl.sh'"
if ($LASTEXITCODE) { throw 'scripts/setup-wsl.sh ha fallado (mira el mensaje de arriba)' }

# --- 3. VMs -----------------------------------------------------------------
Write-Paso '3/5 Crear y arrancar las VMs (vagrant up)'
vagrant up --provider vmware_desktop
if ($LASTEXITCODE) { throw 'vagrant up ha fallado' }

# --- 4. WinRM ---------------------------------------------------------------
Write-Paso '4/5 Esperar a WinRM en la IP del lab'
foreach ($vm in $vms.GetEnumerator()) {
    $ok = $false
    for ($i = 1; $i -le 30 -and -not $ok; $i++) {
        $ok = Test-NetConnection $vm.Value -Port 5985 -InformationLevel Quiet -WarningAction SilentlyContinue
        if (-not $ok) { Start-Sleep -Seconds 10 }
    }
    if (-not $ok) { throw "$($vm.Key) ($($vm.Value)) no responde por WinRM (puerto 5985) después de 5 minutos" }
    Write-Host "  $($vm.Key) ($($vm.Value)) responde por WinRM" -ForegroundColor Green
}

# --- 5. Active Directory -----------------------------------------------------
Write-Paso '5/5 Configurar el AD (playbooks/site.yml)'
Invoke-Site 'site'

if ($ComprobarIdempotencia) {
    Write-Paso 'Comprobar la idempotencia (site.yml otra vez)'
    Invoke-Site 'site-idempotencia'
    $conCambios = Select-String -Path $log -Pattern 'changed=[1-9]' -Encoding UTF8
    if ($conCambios) {
        Write-Host 'No es idempotente: la segunda ejecución ha cambiado algo:' -ForegroundColor Yellow
        $conCambios | ForEach-Object { Write-Host "  $($_.Line)" }
    } else {
        Write-Host 'Idempotente: la segunda ejecución termina con changed=0 en todas las VMs' -ForegroundColor Green
    }
}

$duracion = (Get-Date) - $inicio
Write-Host ("`nLab montado en {0:hh\:mm\:ss}. Salida de Ansible: {1}" -f $duracion, $log) -ForegroundColor Green
Write-Host '  DC01  192.168.56.10  lab.local (raíz del bosque)'
Write-Host '  DC02  192.168.56.11  emea.lab.local (dominio hijo)'
Write-Host '  SRV01 192.168.56.20  servidor miembro de lab.local'
