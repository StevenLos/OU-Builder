<#
.SYNOPSIS
Creates Active Directory Organizational Units from a CSV OU map.

.DESCRIPTION
Reads a CSV containing OU paths such as:
  Administration and Security/Administration Accounts/Example Administration Accounts

The script:
  - Uses FullPath as the source of truth
  - Sorts by Depth so parent OUs are processed before children
  - Skips rows where Create is not TRUE
  - Checks whether each OU already exists before creating it
  - Supports -WhatIf and -Confirm through ShouldProcess
  - Logs Created, Exists, Skipped, and Failed outcomes to CSV
  - Sets ProtectedFromAccidentalDeletion from the CSV when supplied

REQUIRED CSV COLUMNS
  Create
  FullPath
  Depth
  OUName
  ParentPath
  Description
  ProtectedFromAccidentalDeletion

EXAMPLE
  .\Create-ADOrganizationalUnits.ps1 `
    -CsvPath .\example-ou-map.csv `
    -BaseDN "DC=example,DC=com" `
    -WhatIf

EXAMPLE
  .\Create-ADOrganizationalUnits.ps1 `
    -CsvPath .\example-ou-map.csv `
    -BaseDN "DC=example,DC=com" `
    -LogPath .\Create-ADOrganizationalUnits.log.csv

.NOTES
Run from a machine with the ActiveDirectory PowerShell module installed and with an account delegated to create OUs in the target domain path.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ })]
    [string]$CsvPath,

    [Parameter(Mandatory = $false)]
    [string]$BaseDN = 'DC=example,DC=com',

    [Parameter(Mandatory = $false)]
    [string]$Server,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = (Join-Path -Path (Get-Location) -ChildPath ('Create-ADOrganizationalUnits_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))),

    [Parameter(Mandatory = $false)]
    [switch]$StopOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-Bool {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [bool]$Default = $false
    )

    if ($null -eq $Value) { return $Default }

    $text = $Value.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }

    switch -Regex ($text) {
        '^(?i:true|t|yes|y|1)$'  { return $true }
        '^(?i:false|f|no|n|0)$'  { return $false }
        default { throw "Invalid Boolean value '$text'. Expected TRUE or FALSE." }
    }
}

function Escape-LdapFilterValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    # RFC 4515 escaping for LDAP filter assertion values.
    return $Value.Replace('\', '\5c').Replace('*', '\2a').Replace('(', '\28').Replace(')', '\29').Replace([string][char]0, '\00')
}

function Escape-DistinguishedNameComponent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    # Escape a single DN component value for use in OU=<value>,<parentDN>.
    # This covers common RFC 4514-sensitive characters and edge cases.
    $escaped = $Value.Replace('\', '\\')
    $escaped = $escaped.Replace(',', '\,')
    $escaped = $escaped.Replace('+', '\+')
    $escaped = $escaped.Replace('"', '\"')
    $escaped = $escaped.Replace('<', '\<')
    $escaped = $escaped.Replace('>', '\>')
    $escaped = $escaped.Replace(';', '\;')
    $escaped = $escaped.Replace('=', '\=')

    if ($escaped.StartsWith(' ')) {
        $escaped = '\' + $escaped
    }

    if ($escaped.EndsWith(' ')) {
        $escaped = $escaped.Substring(0, $escaped.Length - 1) + '\ '
    }

    if ($escaped.StartsWith('#')) {
        $escaped = '\' + $escaped
    }

    return $escaped
}

function Convert-PathToDN {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullPath,

        [Parameter(Mandatory = $true)]
        [string]$BaseDN
    )

    $parts = @($FullPath -split '/' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -eq 0) {
        return $BaseDN
    }

    $ouComponents = for ($i = $parts.Count - 1; $i -ge 0; $i--) {
        'OU={0}' -f (Escape-DistinguishedNameComponent -Value $parts[$i])
    }

    return (($ouComponents -join ',') + ',' + $BaseDN)
}

function Get-ADOUOneLevelByName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ParentDN,

        [Parameter(Mandatory = $false)]
        [string]$Server
    )

    $ldapName = Escape-LdapFilterValue -Value $Name
    $params = @{
        LDAPFilter  = "(&(objectClass=organizationalUnit)(ou=$ldapName))"
        SearchBase  = $ParentDN
        SearchScope = 'OneLevel'
        Properties  = @('distinguishedName', 'protectedFromAccidentalDeletion', 'description')
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $params.Server = $Server
    }

    return Get-ADOrganizationalUnit @params
}

function Write-LogRow {
    param(
        [Parameter(Mandatory = $true)] [string]$Action,
        [Parameter(Mandatory = $true)] [string]$Status,
        [Parameter(Mandatory = $false)] [string]$FullPath,
        [Parameter(Mandatory = $false)] [string]$OUName,
        [Parameter(Mandatory = $false)] [string]$ParentPath,
        [Parameter(Mandatory = $false)] [string]$TargetDN,
        [Parameter(Mandatory = $false)] [string]$Message
    )

    $script:LogRows.Add([pscustomobject]@{
        Timestamp  = (Get-Date).ToString('s')
        Action     = $Action
        Status     = $Status
        FullPath   = $FullPath
        OUName     = $OUName
        ParentPath = $ParentPath
        TargetDN   = $TargetDN
        Message    = $Message
    }) | Out-Null
}

Import-Module ActiveDirectory -ErrorAction Stop

$requiredColumns = @(
    'Create',
    'FullPath',
    'Depth',
    'OUName',
    'ParentPath',
    'Description',
    'ProtectedFromAccidentalDeletion'
)

$rows = @(Import-Csv -LiteralPath $CsvPath)
if ($null -eq $rows -or $rows.Count -eq 0) {
    throw "CSV '$CsvPath' contains no rows."
}

$actualColumns = @($rows[0].PSObject.Properties.Name)
foreach ($column in $requiredColumns) {
    if ($actualColumns -notcontains $column) {
        throw "CSV is missing required column '$column'."
    }
}

$script:LogRows = New-Object System.Collections.Generic.List[object]

# Normalize and filter rows.
$ouRows = foreach ($row in $rows) {
    $create = ConvertTo-Bool -Value $row.Create -Default $true
    if (-not $create) {
        Write-LogRow -Action 'Skip' -Status 'Skipped' -FullPath $row.FullPath -OUName $row.OUName -ParentPath $row.ParentPath -TargetDN '' -Message 'Create is not TRUE.'
        continue
    }

    $fullPath = $row.FullPath.ToString().Trim()
    $ouName = $row.OUName.ToString().Trim()
    $parentPath = $row.ParentPath.ToString().Trim()

    if ([string]::IsNullOrWhiteSpace($fullPath)) {
        Write-LogRow -Action 'Validate' -Status 'Failed' -FullPath '' -OUName $ouName -ParentPath $parentPath -TargetDN '' -Message 'FullPath is blank.'
        if ($StopOnError) { throw 'CSV contains a row with blank FullPath.' }
        continue
    }

    if ([string]::IsNullOrWhiteSpace($ouName)) {
        Write-LogRow -Action 'Validate' -Status 'Failed' -FullPath $fullPath -OUName '' -ParentPath $parentPath -TargetDN '' -Message 'OUName is blank.'
        if ($StopOnError) { throw "CSV row '$fullPath' has blank OUName." }
        continue
    }

    $pathParts = @($fullPath -split '/' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $calculatedDepth = $pathParts.Count

    [pscustomobject]@{
        FullPath = $fullPath
        Depth = $calculatedDepth
        CsvDepth = $row.Depth
        OUName = $ouName
        ParentPath = $parentPath
        Description = $row.Description
        ProtectedFromAccidentalDeletion = ConvertTo-Bool -Value $row.ProtectedFromAccidentalDeletion -Default $true
        TargetDN = Convert-PathToDN -FullPath $fullPath -BaseDN $BaseDN
        ParentDN = if ([string]::IsNullOrWhiteSpace($parentPath)) { $BaseDN } else { Convert-PathToDN -FullPath $parentPath -BaseDN $BaseDN }
    }
}

# Validate duplicate FullPath values.
$duplicates = $ouRows | Group-Object -Property FullPath | Where-Object { $_.Count -gt 1 }
if ($duplicates) {
    foreach ($duplicate in $duplicates) {
        Write-LogRow -Action 'Validate' -Status 'Failed' -FullPath $duplicate.Name -OUName '' -ParentPath '' -TargetDN '' -Message "Duplicate FullPath appears $($duplicate.Count) times."
    }

    $message = 'CSV contains duplicate FullPath values. Fix duplicates before creating OUs.'
    if ($StopOnError) { throw $message }
    Write-Warning $message
}

# Validate that every non-root parent exists in the file or already exists in AD.
$fullPathSet = @{}
foreach ($row in $ouRows) {
    $fullPathSet[$row.FullPath] = $true
}

foreach ($row in $ouRows) {
    if ([string]::IsNullOrWhiteSpace($row.ParentPath)) { continue }
    if ($fullPathSet.ContainsKey($row.ParentPath)) { continue }

    try {
        $parentName = (($row.ParentPath -split '/') | Select-Object -Last 1).Trim()
        $grandParentPath = (($row.ParentPath -split '/') | Select-Object -SkipLast 1) -join '/'
        $grandParentDN = if ([string]::IsNullOrWhiteSpace($grandParentPath)) { $BaseDN } else { Convert-PathToDN -FullPath $grandParentPath -BaseDN $BaseDN }
        $existingParent = Get-ADOUOneLevelByName -Name $parentName -ParentDN $grandParentDN -Server $Server
        if (-not $existingParent) {
            throw "ParentPath '$($row.ParentPath)' was not found in CSV or AD."
        }
    }
    catch {
        Write-LogRow -Action 'Validate' -Status 'Failed' -FullPath $row.FullPath -OUName $row.OUName -ParentPath $row.ParentPath -TargetDN $row.TargetDN -Message $_.Exception.Message
        if ($StopOnError) { throw }
        Write-Warning $_.Exception.Message
    }
}

$sortedRows = $ouRows | Sort-Object -Property Depth, FullPath

foreach ($row in $sortedRows) {
    try {
        $existing = Get-ADOUOneLevelByName -Name $row.OUName -ParentDN $row.ParentDN -Server $Server

        if ($existing) {
            Write-Host "Exists: $($row.TargetDN)"
            Write-LogRow -Action 'CreateOU' -Status 'Exists' -FullPath $row.FullPath -OUName $row.OUName -ParentPath $row.ParentPath -TargetDN $existing.DistinguishedName -Message 'OU already exists.'
            continue
        }

        $params = @{
            Name                            = $row.OUName
            Path                            = $row.ParentDN
            ProtectedFromAccidentalDeletion = $row.ProtectedFromAccidentalDeletion
            ErrorAction                     = 'Stop'
        }

        if (-not [string]::IsNullOrWhiteSpace($row.Description)) {
            $params.Description = $row.Description
        }

        if (-not [string]::IsNullOrWhiteSpace($Server)) {
            $params.Server = $Server
        }

        if ($PSCmdlet.ShouldProcess($row.TargetDN, 'Create Active Directory OU')) {
            New-ADOrganizationalUnit @params
            Write-Host "Created: $($row.TargetDN)"
            Write-LogRow -Action 'CreateOU' -Status 'Created' -FullPath $row.FullPath -OUName $row.OUName -ParentPath $row.ParentPath -TargetDN $row.TargetDN -Message 'OU created.'
        }
        else {
            Write-LogRow -Action 'CreateOU' -Status 'WhatIf' -FullPath $row.FullPath -OUName $row.OUName -ParentPath $row.ParentPath -TargetDN $row.TargetDN -Message 'Creation skipped by ShouldProcess.'
        }
    }
    catch {
        $message = $_.Exception.Message
        Write-Warning "Failed: $($row.TargetDN). $message"
        Write-LogRow -Action 'CreateOU' -Status 'Failed' -FullPath $row.FullPath -OUName $row.OUName -ParentPath $row.ParentPath -TargetDN $row.TargetDN -Message $message
        if ($StopOnError) { throw }
    }
}

$logDirectory = Split-Path -Path $LogPath -Parent
if (-not [string]::IsNullOrWhiteSpace($logDirectory) -and -not (Test-Path -LiteralPath $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}

# Write the audit log even during -WhatIf so dry runs remain reviewable.
$script:LogRows | Export-Csv -LiteralPath $LogPath -NoTypeInformation -Encoding UTF8 -WhatIf:$false -Confirm:$false
Write-Host "Log written to: $LogPath"
