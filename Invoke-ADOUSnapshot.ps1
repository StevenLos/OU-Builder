<#
.SYNOPSIS
Captures and compares Active Directory Organizational Unit structure.

.DESCRIPTION
Invoke-ADOUSnapshot.ps1 is a read-only Active Directory documentation tool.
It supports two modes:

- Snapshot: reads OUs under a SearchBase and writes JSON, CSV, text tree, and HTML.
- Compare: compares a pre-change and post-change snapshot by ObjectGuid, treating
  DistinguishedName as mutable state, and writes detailed CSV, HTML, and XLSX
  side-by-side review reports.

The tool does not create, delete, move, rename, or modify Active Directory objects.
Snapshot mode requires the ActiveDirectory PowerShell module. Compare mode does not
connect to Active Directory.

.PARAMETER Mode
Use Snapshot to capture current AD OU state, or Compare to compare two snapshot JSON files.

.PARAMETER SearchBase
Distinguished name where Snapshot mode starts querying OUs, such as
DC=corp,DC=contoso,DC=com or OU=Corporate,DC=corp,DC=contoso,DC=com.

.PARAMETER Server
Optional domain controller or AD LDS instance used by Get-ADOrganizationalUnit.

.PARAMETER OutputRoot
Root folder where the tool creates a child folder named by Label.

.PARAMETER Label
Folder-safe label for this run, such as pre-change, post-change, or ou-comparison.

.PARAMETER PreSnapshot
Path to the pre-change ou-snapshot.json file for Compare mode.

.PARAMETER PostSnapshot
Path to the post-change ou-snapshot.json file for Compare mode.

.EXAMPLE
.\Invoke-ADOUSnapshot.ps1 `
  -Mode Snapshot `
  -SearchBase "DC=corp,DC=contoso,DC=com" `
  -OutputRoot ".\AD-OU-Captures" `
  -Label "pre-change"

.EXAMPLE
.\Invoke-ADOUSnapshot.ps1 `
  -Mode Snapshot `
  -SearchBase "OU=Corporate,DC=corp,DC=contoso,DC=com" `
  -Server "dc01.corp.contoso.com" `
  -OutputRoot ".\AD-OU-Captures" `
  -Label "post-change"

.EXAMPLE
.\Invoke-ADOUSnapshot.ps1 `
  -Mode Compare `
  -PreSnapshot ".\AD-OU-Captures\pre-change\ou-snapshot.json" `
  -PostSnapshot ".\AD-OU-Captures\post-change\ou-snapshot.json" `
  -OutputRoot ".\AD-OU-Captures" `
  -Label "ou-comparison"

.NOTES
Run Snapshot mode from a Windows infrastructure workstation or management server with
RSAT Active Directory tools installed and an account that can read the target OU tree.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Snapshot', 'Compare')]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [string]$SearchBase,

    [Parameter(Mandatory = $false)]
    [string]$Server,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ($_ -match '[<>:"/\\|?*]') {
            throw 'Label cannot contain Windows path separator or reserved filename characters.'
        }
        return $true
    })]
    [string]$Label,

    [Parameter(Mandatory = $false)]
    [string]$PreSnapshot,

    [Parameter(Mandatory = $false)]
    [string]$PostSnapshot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'src\ADOUStructureAudit.psm1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Required module was not found at '$modulePath'."
}

Import-Module -Name $modulePath -Force
Invoke-ADOUStructureAudit @PSBoundParameters
