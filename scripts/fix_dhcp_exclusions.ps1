<#
.SYNOPSIS
    Applies range exclusions to Windows DHCP server for unmanaged static addresses.
.DESCRIPTION
    Ensures addresses reserved in hardware devices or router ARP tables are 
    omitted from DHCP dynamic allocation pool.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ScopeId,

    [Parameter(Mandatory = $true)]
    [string[]]$ConflictingIPs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

foreach ($TargetIp in $ConflictingIPs) {
    try {
        Write-Output "[+] Adding Exclusion Range for IP: $TargetIp on Scope: $ScopeId"
        Add-DhcpServerv4ExclusionRange -ScopeId $ScopeId -StartRange $TargetIp -EndRange $TargetIp
        Write-Output "    Successfully excluded $TargetIp from dynamic lease pool."
    } catch {
        Write-Warning "[-] Failed to add exclusion for $TargetIp. Reason: $($_.Exception.Message)"
    }
}
