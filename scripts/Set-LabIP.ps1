# Pone la IP fija del lab en la segunda NIC (host-only).
# Vagrant no configura private_network en invitados Windows con VMware.
param(
    [Parameter(Mandatory)] [string] $IPAddress,
    [int] $PrefixLength = 24
)
$ErrorActionPreference = 'Stop'

# La NIC NAT es la que tiene puerta de enlace; la del lab es la otra
$natIndex = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).InterfaceIndex
$lab = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.ifIndex -ne $natIndex } | Sort-Object ifIndex | Select-Object -First 1
if (-not $lab) { throw 'No se encuentra la segunda NIC del lab' }

$actual = Get-NetIPAddress -InterfaceIndex $lab.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
if ($actual.IPAddress -contains $IPAddress -and $actual.PrefixOrigin -contains 'Manual') {
    Write-Output "Set-LabIP: $($lab.Name) ya tiene $IPAddress/$PrefixLength"
    return
}

Set-NetIPInterface -InterfaceIndex $lab.ifIndex -Dhcp Disabled
$actual | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex $lab.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength | Out-Null
Write-Output "Set-LabIP: $($lab.Name) configurada con $IPAddress/$PrefixLength"

