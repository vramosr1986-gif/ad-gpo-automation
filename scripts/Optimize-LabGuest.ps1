# Aligera las VMs del lab: sin Windows Update ni analisis en tiempo real de Defender.
# Solo para el laboratorio; no usar en equipos reales.
$ErrorActionPreference = 'Stop'

# Windows Update: servicios parados y deshabilitados, y politica de no actualizar
foreach ($svc in 'wuauserv', 'UsoSvc', 'WaaSMedicSvc') {
    try {
        Stop-Service -Name $svc -Force -ErrorAction Stop
        Set-Service -Name $svc -StartupType Disabled -ErrorAction Stop
    } catch {
        # WaaSMedicSvc no permite Set-Service; se deshabilita por registro
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name Start -Value 4
    }
}
$au = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
New-Item -Path $au -Force | Out-Null
Set-ItemProperty -Path $au -Name NoAutoUpdate -Value 1 -Type DWord

# Defender: sin analisis en tiempo real ni muestras a la nube
Set-MpPreference -DisableRealtimeMonitoring $true -MAPSReporting Disabled -SubmitSamplesConsent NeverSend

Write-Output "Optimize-LabGuest: Windows Update y Defender en tiempo real desactivados en $env:COMPUTERNAME"
