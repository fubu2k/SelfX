<#
.SYNOPSIS
    Reads network adapters and default routes through CIM and restarts an adapter (no NetAdapter module).

.DESCRIPTION
    Dot-sourced by SystemInfo.ps1 users (SelfX window, status icon, health checks) and by SelfX_Device_AirePlaneMode.ps1 (System).
    The NetAdapter and NetTCPIP modules (Get-NetAdapter, Get-NetRoute, Restart-NetAdapter) run in PowerShell 7 only through the
    Windows PowerShell 5.1 compatibility layer. These functions use the CIM classes of namespace root\StandardCimv2 directly
    (MSFT_NetAdapter, MSFT_NetRoute), which the cmdlets wrap, so no second PowerShell is started.

    The raw CIM class has no Status, ifIndex or media texts. Get-SelfXNetAdapters converts it to objects with the properties that
    the rest of SelfX uses (checked against the output of Get-NetAdapter on Windows 11 build 26300):
      - ifIndex             = InterfaceIndex
      - Status              = Disabled (InterfaceAdminStatus 2), Up (InterfaceOperationalStatus 1),
                              Disconnected (OperationalStatusDownMediaDisconnected), otherwise Down
      - PhysicalMediaType   = text of NdisPhysicalMedium (0 Unspecified, 1 Wireless LAN, 8 Wireless WAN, 9 Native 802.11,
                              10 BlueTooth, 14 802.3)
      - MediaType           = text of NdisMedium (0 802.3, 16 Native 802.11, 19 IP)
    Hidden adapters (removed hardware) are left out, as Get-NetAdapter does by default.
    Reading needs no administrator rights. Restart-SelfXNetAdapter needs them (the service runs it as SYSTEM).

.NOTES
    Name    : SelfXNetwork.ps1
    Package : SelfX Service
    Context : User (read) and System (restart), dot-sourced
    Version : 2.6.10

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.6.10   2026-11-22  fubu2k               Initial version: CIM instead of Get-NetAdapter / Get-NetRoute / Restart-NetAdapter
#>

$Script:SelfXNetworkNamespace = 'root\StandardCimv2'

# Converts one MSFT_NetAdapter instance to the object that SelfX uses. The CIM instance stays in the property CimInstance.
function ConvertTo-SelfXNetAdapter {
	param([Parameter(Mandatory = $true)]$CimAdapter)
	$status = 'Down'
	if ([int]$CimAdapter.InterfaceAdminStatus -eq 2) { $status = 'Disabled' }
	elseif ([int]$CimAdapter.InterfaceOperationalStatus -eq 1) { $status = 'Up' }
	elseif ($CimAdapter.OperationalStatusDownMediaDisconnected -eq $true) { $status = 'Disconnected' }
	$physical = [int]$CimAdapter.NdisPhysicalMedium
	$physicalText = switch ($physical) { 0 { 'Unspecified' } 1 { 'Wireless LAN' } 8 { 'Wireless WAN' } 9 { 'Native 802.11' } 10 { 'BlueTooth' } 14 { '802.3' } default { "Ndis$physical" } }
	$medium = [int]$CimAdapter.NdisMedium
	$mediaText = switch ($medium) { 0 { '802.3' } 16 { 'Native 802.11' } 19 { 'IP' } default { "Ndis$medium" } }
	[pscustomobject]@{
		Name               = "$($CimAdapter.Name)"
		InterfaceDescription = "$($CimAdapter.InterfaceDescription)"
		ifIndex            = [int]$CimAdapter.InterfaceIndex
		Status             = $status
		PhysicalMediaType  = $physicalText
		NdisPhysicalMedium = $physical
		MediaType          = $mediaText
		HardwareInterface  = ($CimAdapter.HardwareInterface -eq $true)
		ConnectorPresent   = ($CimAdapter.ConnectorPresent -eq $true)
		Virtual            = ($CimAdapter.Virtual -eq $true)
		CimInstance        = $CimAdapter
	}
}

# All visible network adapters. Throws when the CIM class cannot be read (callers decide: SelfX status shows "unknown").
function Get-SelfXNetAdapters {
	$adapters = @(Get-CimInstance -Namespace $Script:SelfXNetworkNamespace -ClassName MSFT_NetAdapter -ErrorAction Stop)
	@($adapters | Where-Object { $_ -and $_.Hidden -ne $true } | ForEach-Object { ConvertTo-SelfXNetAdapter $_ })
}

# Interface indexes with a default route (IPv4 or IPv6) and a real next hop, i.e. adapters that connect to other networks.
function Get-SelfXDefaultRouteInterfaceIndexes {
	$routes = @(Get-CimInstance -Namespace $Script:SelfXNetworkNamespace -ClassName MSFT_NetRoute -ErrorAction Stop |
		Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0', '::/0') })
	@($routes | Where-Object { "$($_.NextHop)" -notin @('0.0.0.0', '::', '') } | ForEach-Object { [int]$_.InterfaceIndex } | Sort-Object -Unique)
}

# Restarts an adapter that Get-SelfXNetAdapters returned (CIM method Restart of MSFT_NetAdapter, what Restart-NetAdapter calls).
# Only the CIM instance of such an object is used: no name or other text is passed on.
function Restart-SelfXNetAdapter {
	param([Parameter(Mandatory = $true)]$Adapter)
	if (-not $Adapter.CimInstance) { throw 'The adapter has no CIM instance.' }
	[void](Invoke-CimMethod -InputObject $Adapter.CimInstance -MethodName Restart -ErrorAction Stop)
}
