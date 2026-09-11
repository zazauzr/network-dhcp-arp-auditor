<#
.SYNOPSIS
    Audits discrepancies between Windows DHCP Scope Leases and Gateway Static ARP mappings.
.DESCRIPTION
    Identifies dynamic IP leases that collide with pre-configured static ARP entries
    on the network gateway, preventing asymmetric routing and traffic blackholing.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ScopeId = "192.168.10.0",

    [Parameter(Mandatory = $false)]
    [string]$GatewayIp = "192.168.10.1",

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LogPath')]
    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\dhcp_arp_audit.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-AuditLog {
    param ([string]$Message, [string]$Level = "INFO")
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $Formatted = "[$Timestamp] [$Level] $Message"
    Write-Output $Formatted
    Add-Content -Path $LogPath -Value $Formatted -ErrorAction SilentlyContinue
}

Write-AuditLog "Starting DHCP vs ARP reconciliation for Scope: $ScopeId via Gateway: $GatewayIp"

try {
    if (-not (Get-Command -Name Get-DhcpServerv4Lease -ErrorAction SilentlyContinue)) {
        throw "RSAT DHCP Server module is not installed or available."
    }

    Write-Log "Querying active DHCP leases..."
    $DhcpLeases = Get-DhcpServerv4Lease -ScopeId $ScopeId -AllLeases | 
        Select-Object IPAddress, ClientId, HostName, AddressState

    Write-Log "Reading local ARP resolution cache for gateway segment..."
    $ArpEntries = Get-NetNeighbor -AddressFamily IPv4 | 
        Where-Object { $_.IPAddress -like "$($ScopeId.TrimEnd('.0')).*" } | 
        Select-Object IPAddress, LinkLayerAddress, State

    $ConflictsFound = 0

    foreach ($Lease in $DhcpLeases) {
        $MatchingArp = $ArpEntries | Where-Object { $_.IPAddress -eq $Lease.IPAddress.IPAddressToString }

        if ($MatchingArp) {
            $DhcpMac = ($Lease.ClientId -replace '[:-]', '').ToUpper()
            $ArpMac  = ($MatchingArp.LinkLayerAddress -replace '[:-]', '').ToUpper()

            if ($DhcpMac -ne $ArpMac -and $ArpMac -ne "") {
                $ConflictsFound++
                Write-Log "CONFLICT DETECTED: IP [$($Lease.IPAddress)] leased to [$DhcpMac], but locked to [$ArpMac] on L2 (State: $($MatchingArp.State))" "ERROR"
            }
        }
    }

    if ($ConflictsFound -eq 0) {
        Write-Log "Audit completed. No lease-to-ARP collisions detected." "INFO"
    } else {
        Write-Log "Audit completed with $ConflictsFound collision(s). Action required." "WARN"
    }

} catch {
    Write-Log "Execution halted: $($_.Exception.Message)" "FATAL"
    exit 1
}
