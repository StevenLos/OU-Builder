Set-StrictMode -Version Latest

$script:SnapshotColumns = @(
    'ObjectGuid',
    'Name',
    'RdnValue',
    'DistinguishedName',
    'ParentDistinguishedName',
    'CanonicalName',
    'Depth',
    'Description',
    'ManagedBy',
    'ProtectedFromAccidentalDeletion',
    'gPLink',
    'gPOptions',
    'whenCreated',
    'whenChanged'
)

$script:MovedOrRenamedColumns = @(
    'ObjectGuid',
    'ChangeType',
    'OldName',
    'NewName',
    'OldRdnValue',
    'NewRdnValue',
    'OldParentDistinguishedName',
    'NewParentDistinguishedName',
    'OldDistinguishedName',
    'NewDistinguishedName',
    'OldCanonicalName',
    'NewCanonicalName'
)

$script:AttributeChangeColumns = @(
    'ObjectGuid',
    'ChangeScope',
    'AttributeName',
    'OldValue',
    'NewValue',
    'OldName',
    'NewName',
    'OldDistinguishedName',
    'NewDistinguishedName'
)

$script:AttributeCompareFields = @(
    'Description',
    'ManagedBy',
    'ProtectedFromAccidentalDeletion',
    'gPLink',
    'gPOptions',
    'whenCreated',
    'whenChanged'
)

$script:SideBySideColumns = @(
    'ChangeType',
    'HasAttributeChanges',
    'ChangedAttributes',
    'ObjectGuid',
    'PrePath',
    'PostPath',
    'PreDepth',
    'PostDepth',
    'PreName',
    'PostName',
    'PreRdnValue',
    'PostRdnValue',
    'PreParentDistinguishedName',
    'PostParentDistinguishedName',
    'PreDistinguishedName',
    'PostDistinguishedName',
    'PreCanonicalName',
    'PostCanonicalName',
    'DescriptionChanged',
    'PreDescription',
    'PostDescription',
    'ManagedByChanged',
    'PreManagedBy',
    'PostManagedBy',
    'ProtectedFromAccidentalDeletionChanged',
    'PreProtectedFromAccidentalDeletion',
    'PostProtectedFromAccidentalDeletion',
    'GPLinkChanged',
    'PreGPLink',
    'PostGPLink',
    'GPOptionsChanged',
    'PreGPOptions',
    'PostGPOptions',
    'WhenCreatedChanged',
    'PreWhenCreated',
    'PostWhenCreated',
    'WhenChangedChanged',
    'PreWhenChanged',
    'PostWhenChanged'
)

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function ConvertTo-AuditString {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    if ($Value -is [array]) {
        return ((@($Value) | ForEach-Object { ConvertTo-AuditString -Value $_ }) -join '; ')
    }

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('o')
    }

    return $Value.ToString()
}

function ConvertTo-ComparableValue {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    return (ConvertTo-AuditString -Value $Value)
}

function Test-AuditValueChanged {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$OldValue,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$NewValue
    )

    return (-not [string]::Equals(
        (ConvertTo-ComparableValue -Value $OldValue),
        (ConvertTo-ComparableValue -Value $NewValue),
        [System.StringComparison]::Ordinal
    ))
}

function Get-ReviewPath {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Record
    )

    $canonicalName = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $Record -Name 'CanonicalName')
    if (-not [string]::IsNullOrWhiteSpace($canonicalName)) {
        return $canonicalName
    }

    return (ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $Record -Name 'DistinguishedName'))
}

function Get-ChangeCssClass {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$ChangeType
    )

    switch (ConvertTo-ComparableValue -Value $ChangeType) {
        'Added' { return 'change-added' }
        'Removed' { return 'change-removed' }
        'Moved' { return 'change-moved' }
        'Renamed' { return 'change-renamed' }
        'MovedAndRenamed' { return 'change-movedandrenamed' }
        'AttributeOnly' { return 'change-attributeonly' }
        default { return '' }
    }
}

function ConvertTo-HtmlEscaped {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    return [System.Net.WebUtility]::HtmlEncode((ConvertTo-AuditString -Value $Value))
}

function ConvertTo-XmlEscaped {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    return [System.Security.SecurityElement]::Escape((ConvertTo-AuditString -Value $Value))
}

function Set-Utf8NoBomTextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Value
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($resolvedPath, (ConvertTo-AuditString -Value $Value), $encoding)
}

function Assert-ValidOutputLabel {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Label
    )

    if ($Label -match '[<>:"/\\|?*]') {
        throw "Label '$Label' contains a character that is not valid for a Windows folder name."
    }
}

function Resolve-OutputDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Label
    )

    Assert-ValidOutputLabel -Label $Label
    $resolvedRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)
    $outputDirectory = Join-Path -Path $resolvedRoot -ChildPath $Label
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    return (Get-Item -LiteralPath $outputDirectory).FullName
}

function Import-RequiredActiveDirectoryModule {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
    catch {
        throw "The ActiveDirectory PowerShell module is required for Snapshot mode. Install RSAT Active Directory tools or run from a domain management host. Details: $($_.Exception.Message)"
    }
}

function Split-ADDistinguishedName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DistinguishedName
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $current = [System.Text.StringBuilder]::new()
    $isEscaped = $false

    for ($index = 0; $index -lt $DistinguishedName.Length; $index++) {
        $character = $DistinguishedName[$index]

        if ($isEscaped) {
            [void]$current.Append($character)
            $isEscaped = $false
            continue
        }

        if ($character -eq [char]'\') {
            [void]$current.Append($character)
            $isEscaped = $true
            continue
        }

        if ($character -eq [char]',') {
            $parts.Add($current.ToString()) | Out-Null
            [void]$current.Clear()
            continue
        }

        [void]$current.Append($character)
    }

    $parts.Add($current.ToString()) | Out-Null
    return @($parts)
}

function Get-FirstUnescapedCharacterIndex {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [char]$Character
    )

    $isEscaped = $false
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $current = $Value[$index]

        if ($isEscaped) {
            $isEscaped = $false
            continue
        }

        if ($current -eq [char]'\') {
            $isEscaped = $true
            continue
        }

        if ($current -eq $Character) {
            return $index
        }
    }

    return -1
}

function ConvertFrom-LdapEscapedValue {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]

        if ($character -ne [char]'\') {
            [void]$builder.Append($character)
            continue
        }

        if ($index -ge ($Value.Length - 1)) {
            [void]$builder.Append($character)
            continue
        }

        $next = $Value[$index + 1]
        if (($index + 2) -lt $Value.Length) {
            $hexPair = $Value.Substring($index + 1, 2)
            if ($hexPair -match '^[0-9A-Fa-f]{2}$') {
                [void]$builder.Append([char]([Convert]::ToInt32($hexPair, 16)))
                $index += 2
                continue
            }
        }

        [void]$builder.Append($next)
        $index++
    }

    return $builder.ToString()
}

function Get-ADParentDistinguishedName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DistinguishedName
    )

    $parts = @(Split-ADDistinguishedName -DistinguishedName $DistinguishedName)
    if ($parts.Count -le 1) {
        return ''
    }

    return (($parts[1..($parts.Count - 1)]) -join ',')
}

function Get-ADRdnValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DistinguishedName
    )

    $parts = @(Split-ADDistinguishedName -DistinguishedName $DistinguishedName)
    $rdn = $parts[0]
    $separatorIndex = Get-FirstUnescapedCharacterIndex -Value $rdn -Character ([char]'=')

    if ($separatorIndex -lt 0 -or $separatorIndex -eq ($rdn.Length - 1)) {
        return (ConvertFrom-LdapEscapedValue -Value $rdn)
    }

    return (ConvertFrom-LdapEscapedValue -Value $rdn.Substring($separatorIndex + 1))
}

function Get-ADDistinguishedNameDepth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DistinguishedName,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$BaseDistinguishedName
    )

    $dnParts = @(Split-ADDistinguishedName -DistinguishedName $DistinguishedName)

    if (-not [string]::IsNullOrWhiteSpace($BaseDistinguishedName)) {
        $baseParts = @(Split-ADDistinguishedName -DistinguishedName $BaseDistinguishedName)

        if ($dnParts.Count -ge $baseParts.Count) {
            $matchesBase = $true
            for ($index = 0; $index -lt $baseParts.Count; $index++) {
                $dnPart = $dnParts[$dnParts.Count - $baseParts.Count + $index]
                if (-not [string]::Equals($dnPart, $baseParts[$index], [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchesBase = $false
                    break
                }
            }

            if ($matchesBase) {
                return ($dnParts.Count - $baseParts.Count)
            }
        }
    }

    return @($dnParts | Where-Object { $_.TrimStart().StartsWith('OU=', [System.StringComparison]::OrdinalIgnoreCase) }).Count
}

function ConvertTo-DistinguishedNameKey {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$DistinguishedName
    )

    $text = ConvertTo-ComparableValue -Value $DistinguishedName
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    return $text.Trim().ToUpperInvariant()
}

function ConvertTo-GuidKey {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    $text = ConvertTo-ComparableValue -Value $Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    try {
        return ([guid]$text).ToString('D').ToLowerInvariant()
    }
    catch {
        return $text.Trim().ToLowerInvariant()
    }
}

function ConvertTo-NaturalSortText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    $text = (ConvertTo-ComparableValue -Value $Value).ToLowerInvariant()
    return [regex]::Replace($text, '\d+', {
        param($Match)
        $Match.Value.PadLeft(20, '0')
    })
}

function Get-DistinguishedNameHierarchySortKey {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$DistinguishedName
    )

    $dn = ConvertTo-ComparableValue -Value $DistinguishedName
    if ([string]::IsNullOrWhiteSpace($dn)) {
        return ''
    }

    $parts = @(Split-ADDistinguishedName -DistinguishedName $dn)
    $ouParts = @(
        $parts |
            Where-Object { $_.TrimStart().StartsWith('OU=', [System.StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object {
                $separatorIndex = Get-FirstUnescapedCharacterIndex -Value $_ -Character ([char]'=')
                if ($separatorIndex -ge 0 -and $separatorIndex -lt ($_.Length - 1)) {
                    ConvertFrom-LdapEscapedValue -Value $_.Substring($separatorIndex + 1)
                }
                else {
                    ConvertFrom-LdapEscapedValue -Value $_
                }
            }
    )

    if ($ouParts.Count -eq 0) {
        return (ConvertTo-NaturalSortText -Value $dn)
    }

    [array]::Reverse($ouParts)
    $segments = @($ouParts | ForEach-Object { ConvertTo-NaturalSortText -Value $_ })
    return ($segments -join ([string][char]31))
}

function Get-ADOUHierarchySortKey {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Record
    )

    return (Get-DistinguishedNameHierarchySortKey -DistinguishedName (Get-ObjectPropertyValue -InputObject $Record -Name 'DistinguishedName'))
}

function New-ADOUSnapshotRecord {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ADObject,

        [Parameter(Mandatory = $true)]
        [string]$SearchBase
    )

    $distinguishedName = ConvertTo-AuditString -Value (Get-ObjectPropertyValue -InputObject $ADObject -Name 'DistinguishedName')
    $objectGuidValue = Get-ObjectPropertyValue -InputObject $ADObject -Name 'ObjectGuid'
    $objectGuid = ConvertTo-GuidKey -Value $objectGuidValue
    $protectedValue = Get-ObjectPropertyValue -InputObject $ADObject -Name 'ProtectedFromAccidentalDeletion'

    [pscustomobject][ordered]@{
        ObjectGuid                      = $objectGuid
        Name                            = ConvertTo-AuditString -Value (Get-ObjectPropertyValue -InputObject $ADObject -Name 'Name')
        RdnValue                        = Get-ADRdnValue -DistinguishedName $distinguishedName
        DistinguishedName               = $distinguishedName
        ParentDistinguishedName         = Get-ADParentDistinguishedName -DistinguishedName $distinguishedName
        CanonicalName                   = ConvertTo-AuditString -Value (Get-ObjectPropertyValue -InputObject $ADObject -Name 'CanonicalName')
        Depth                           = Get-ADDistinguishedNameDepth -DistinguishedName $distinguishedName -BaseDistinguishedName $SearchBase
        Description                     = ConvertTo-AuditString -Value (Get-ObjectPropertyValue -InputObject $ADObject -Name 'Description')
        ManagedBy                       = ConvertTo-AuditString -Value (Get-ObjectPropertyValue -InputObject $ADObject -Name 'ManagedBy')
        ProtectedFromAccidentalDeletion = if ($null -eq $protectedValue) { '' } else { [bool]$protectedValue }
        gPLink                          = ConvertTo-AuditString -Value (Get-ObjectPropertyValue -InputObject $ADObject -Name 'gPLink')
        gPOptions                       = ConvertTo-AuditString -Value (Get-ObjectPropertyValue -InputObject $ADObject -Name 'gPOptions')
        whenCreated                     = ConvertTo-AuditString -Value (Get-ObjectPropertyValue -InputObject $ADObject -Name 'whenCreated')
        whenChanged                     = ConvertTo-AuditString -Value (Get-ObjectPropertyValue -InputObject $ADObject -Name 'whenChanged')
    }
}

function Sort-ADOURecords {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object[]]$Records
    )

    return @($Records | Sort-Object -Property @{ Expression = { Get-ADOUHierarchySortKey -Record $_ }; Ascending = $true }, @{ Expression = 'ObjectGuid'; Ascending = $true })
}

function Export-CsvWithHeader {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object[]]$Records,

        [Parameter(Mandatory = $true)]
        [string[]]$Columns,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $items = @($Records)
    if ($items.Count -gt 0) {
        $items | Select-Object -Property $Columns | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
        return
    }

    Set-Content -LiteralPath $Path -Value ($Columns -join ',') -Encoding UTF8
}

function New-ADOUTreeText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object[]]$Records,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$SearchBase
    )

    $items = @(Sort-ADOURecords -Records $Records)
    $byDn = @{}
    foreach ($item in $items) {
        $byDn[(ConvertTo-DistinguishedNameKey -DistinguishedName $item.DistinguishedName)] = $item
    }

    $childrenByParent = @{}
    foreach ($item in $items) {
        $parentKey = ConvertTo-DistinguishedNameKey -DistinguishedName $item.ParentDistinguishedName
        if (-not $childrenByParent.ContainsKey($parentKey)) {
            $childrenByParent[$parentKey] = New-Object System.Collections.Generic.List[object]
        }
        $childrenByParent[$parentKey].Add($item) | Out-Null
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("SearchBase: $SearchBase") | Out-Null
    $lines.Add("OU count: $($items.Count)") | Out-Null
    $lines.Add('') | Out-Null

    if ($items.Count -eq 0) {
        $lines.Add('(no organizational units captured)') | Out-Null
        return ($lines -join [Environment]::NewLine)
    }

    $externalParentKeys = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $externalParentDisplayByKey = @{}
    foreach ($item in $items) {
        $parentKey = ConvertTo-DistinguishedNameKey -DistinguishedName $item.ParentDistinguishedName
        if (-not $byDn.ContainsKey($parentKey)) {
            $externalParentKeys.Add($parentKey) | Out-Null
            if (-not $externalParentDisplayByKey.ContainsKey($parentKey)) {
                $externalParentDisplayByKey[$parentKey] = ConvertTo-AuditString -Value $item.ParentDistinguishedName
            }
        }
    }

    function Add-TreeChildLines {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ParentKey,

            [Parameter(Mandatory = $true)]
            [int]$Indent
        )

        if (-not $childrenByParent.ContainsKey($ParentKey)) {
            return
        }

        $children = @($childrenByParent[$ParentKey] | Sort-Object -Property @{ Expression = { ConvertTo-NaturalSortText -Value $_.RdnValue }; Ascending = $true }, @{ Expression = 'DistinguishedName'; Ascending = $true })
        foreach ($child in $children) {
            $prefix = ' ' * $Indent
            $lines.Add(('{0}- {1} [{2}]' -f $prefix, $child.RdnValue, $child.ObjectGuid)) | Out-Null
            Add-TreeChildLines -ParentKey (ConvertTo-DistinguishedNameKey -DistinguishedName $child.DistinguishedName) -Indent ($Indent + 2)
        }
    }

    $sortedExternalKeys = @($externalParentKeys | Sort-Object)
    foreach ($parentKey in $sortedExternalKeys) {
        $parentDisplay = if ($externalParentDisplayByKey.ContainsKey($parentKey)) { $externalParentDisplayByKey[$parentKey] } else { $parentKey }
        $parentLabel = if ([string]::IsNullOrWhiteSpace($parentDisplay)) { '(no parent distinguished name)' } else { $parentDisplay }
        $lines.Add("[external/root parent] $parentLabel") | Out-Null
        Add-TreeChildLines -ParentKey $parentKey -Indent 2
    }

    return ($lines -join [Environment]::NewLine)
}

function ConvertTo-HtmlTable {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string[]]$Columns,

        [Parameter(Mandatory = $false)]
        [string]$EmptyMessage = 'No rows.',

        [Parameter(Mandatory = $false)]
        [string]$RowClassProperty
    )

    $items = @($Rows)
    if ($items.Count -eq 0) {
        return '<p class="empty">' + (ConvertTo-HtmlEscaped -Value $EmptyMessage) + '</p>'
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('<table>')
    [void]$builder.AppendLine('<thead><tr>')
    foreach ($column in $Columns) {
        [void]$builder.AppendLine('<th>' + (ConvertTo-HtmlEscaped -Value $column) + '</th>')
    }
    [void]$builder.AppendLine('</tr></thead>')
    [void]$builder.AppendLine('<tbody>')

    foreach ($row in $items) {
        $rowClassAttribute = ''
        if (-not [string]::IsNullOrWhiteSpace($RowClassProperty)) {
            $rowClass = Get-ChangeCssClass -ChangeType (Get-ObjectPropertyValue -InputObject $row -Name $RowClassProperty)
            if (-not [string]::IsNullOrWhiteSpace($rowClass)) {
                $rowClassAttribute = ' class="' + (ConvertTo-HtmlEscaped -Value $rowClass) + '"'
            }
        }

        [void]$builder.AppendLine("<tr$rowClassAttribute>")
        foreach ($column in $Columns) {
            [void]$builder.AppendLine('<td>' + (ConvertTo-HtmlEscaped -Value (Get-ObjectPropertyValue -InputObject $row -Name $column)) + '</td>')
        }
        [void]$builder.AppendLine('</tr>')
    }

    [void]$builder.AppendLine('</tbody>')
    [void]$builder.AppendLine('</table>')
    return $builder.ToString()
}

function Get-ReportCss {
    return @'
body { color: #111827; font-family: "Segoe UI", Arial, sans-serif; margin: 24px; }
h1 { font-size: 26px; margin: 0 0 8px; }
h2 { font-size: 18px; margin: 28px 0 8px; }
.meta { color: #4b5563; margin-bottom: 18px; }
.summary { display: flex; flex-wrap: wrap; gap: 10px; margin: 16px 0 20px; }
.metric { border: 1px solid #d1d5db; border-radius: 6px; padding: 10px 12px; min-width: 130px; }
.metric strong { display: block; font-size: 22px; }
table { border-collapse: collapse; width: 100%; margin: 10px 0 18px; table-layout: fixed; }
th, td { border: 1px solid #d1d5db; padding: 6px 8px; text-align: left; vertical-align: top; word-break: break-word; }
th { background: #f3f4f6; }
pre { background: #f9fafb; border: 1px solid #d1d5db; border-radius: 6px; overflow: auto; padding: 12px; }
.empty { color: #6b7280; font-style: italic; }
.legend span { border: 1px solid #9ca3af; border-radius: 4px; display: inline-block; margin-right: 10px; padding: 4px 8px; }
.added { background: #c6efce; }
.moved { background: #fff2cc; }
.attr { background: #cfe2ff; }
.removed { background: #f4cccc; }
tr.change-added td { background: #e2f0d9; }
tr.change-removed td { background: #f4cccc; }
tr.change-moved td, tr.change-renamed td, tr.change-movedandrenamed td { background: #fff2cc; }
tr.change-attributeonly td { background: #ddebf7; }
'@
}

function New-SnapshotHtml {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Snapshot,

        [Parameter(Mandatory = $true)]
        [object[]]$Records,

        [Parameter(Mandatory = $true)]
        [string]$TreeText
    )

    $summaryRows = @(
        [pscustomobject]@{ Field = 'Label'; Value = $Snapshot.Label },
        [pscustomobject]@{ Field = 'CapturedAtUtc'; Value = $Snapshot.CapturedAtUtc },
        [pscustomobject]@{ Field = 'SearchBase'; Value = $Snapshot.SearchBase },
        [pscustomobject]@{ Field = 'Server'; Value = $Snapshot.Server },
        [pscustomobject]@{ Field = 'OUCount'; Value = $Snapshot.OUCount }
    )

    return @"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>AD OU Snapshot - $(ConvertTo-HtmlEscaped -Value $Snapshot.Label)</title>
<style>
$(Get-ReportCss)
</style>
</head>
<body>
<h1>AD OU Snapshot</h1>
<div class="meta">Static read-only capture of Active Directory Organizational Units.</div>
$(ConvertTo-HtmlTable -Rows $summaryRows -Columns @('Field', 'Value'))
<h2>Tree</h2>
<pre>$(ConvertTo-HtmlEscaped -Value $TreeText)</pre>
<h2>Captured OUs</h2>
$(ConvertTo-HtmlTable -Rows $Records -Columns $script:SnapshotColumns)
</body>
</html>
"@
}

function New-ComparisonHtml {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Comparison
    )

    return @"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>AD OU Comparison - $(ConvertTo-HtmlEscaped -Value $Comparison.Label)</title>
<style>
$(Get-ReportCss)
</style>
</head>
<body>
<h1>AD OU Comparison</h1>
<div class="meta">Comparison uses ObjectGuid as the stable identity key and treats DistinguishedName as mutable state.</div>
<div class="legend">
  <span class="added">Added</span>
  <span class="removed">Removed</span>
  <span class="moved">Moved or renamed</span>
  <span class="attr">Attribute-only change</span>
</div>
<h2>Summary</h2>
$(ConvertTo-HtmlTable -Rows $Comparison.Summary -Columns @('Metric', 'Count'))
<h2>Side-by-Side Review</h2>
$(ConvertTo-HtmlTable -Rows $Comparison.SideBySide -Columns $script:SideBySideColumns -RowClassProperty 'ChangeType')
<h2>Added OUs</h2>
$(ConvertTo-HtmlTable -Rows $Comparison.Added -Columns $script:SnapshotColumns)
<h2>Removed OUs</h2>
$(ConvertTo-HtmlTable -Rows $Comparison.Removed -Columns $script:SnapshotColumns)
<h2>Moved or Renamed OUs</h2>
$(ConvertTo-HtmlTable -Rows $Comparison.MovedOrRenamed -Columns $script:MovedOrRenamedColumns)
<h2>Attribute Changes</h2>
$(ConvertTo-HtmlTable -Rows $Comparison.AttributeChanges -Columns $script:AttributeChangeColumns)
</body>
</html>
"@
}

function ConvertTo-ExcelColumnName {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 16384)]
        [int]$Index
    )

    $name = ''
    $current = $Index
    while ($current -gt 0) {
        $remainder = [int](($current - 1) % 26)
        $name = ([char](65 + $remainder)) + $name
        $current = [int][math]::Floor(($current - 1) / 26)
    }

    return $name
}

function Get-XlsxStyleIndex {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$ChangeType
    )

    switch (ConvertTo-ComparableValue -Value $ChangeType) {
        'Added' { return 2 }
        'Removed' { return 3 }
        'Moved' { return 4 }
        'Renamed' { return 4 }
        'MovedAndRenamed' { return 4 }
        'AttributeOnly' { return 5 }
        default { return 0 }
    }
}

function Get-XlsxColumnWidth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Column
    )

    if ($Column -match 'DistinguishedName|CanonicalName|GPLink|Path|ChangedAttributes') {
        return 42
    }

    if ($Column -match 'ObjectGuid') {
        return 38
    }

    if ($Column -match 'Description|ManagedBy') {
        return 30
    }

    if ($Column -match 'Changed|ChangeType|Depth|Count') {
        return 16
    }

    return [math]::Min(28, [math]::Max(12, $Column.Length + 2))
}

function New-XlsxWorksheetXml {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string[]]$Columns,

        [Parameter(Mandatory = $false)]
        [string]$RowClassProperty
    )

    $items = @($Rows)
    $lastColumnName = ConvertTo-ExcelColumnName -Index $Columns.Count
    $lastRowNumber = [math]::Max(1, $items.Count + 1)
    $range = "A1:$lastColumnName$lastRowNumber"
    $builder = [System.Text.StringBuilder]::new()

    [void]$builder.AppendLine('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$builder.AppendLine('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
    [void]$builder.AppendLine('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
    [void]$builder.AppendLine('<sheetFormatPr defaultRowHeight="15"/>')
    [void]$builder.AppendLine('<cols>')
    for ($columnIndex = 1; $columnIndex -le $Columns.Count; $columnIndex++) {
        $width = Get-XlsxColumnWidth -Column $Columns[$columnIndex - 1]
        [void]$builder.AppendLine(('<col min="{0}" max="{0}" width="{1}" customWidth="1"/>' -f $columnIndex, $width))
    }
    [void]$builder.AppendLine('</cols>')
    [void]$builder.AppendLine('<sheetData>')
    [void]$builder.AppendLine('<row r="1">')
    for ($columnIndex = 1; $columnIndex -le $Columns.Count; $columnIndex++) {
        $cellReference = (ConvertTo-ExcelColumnName -Index $columnIndex) + '1'
        [void]$builder.AppendLine(('<c r="{0}" t="inlineStr" s="1"><is><t xml:space="preserve">{1}</t></is></c>' -f $cellReference, (ConvertTo-XmlEscaped -Value $Columns[$columnIndex - 1])))
    }
    [void]$builder.AppendLine('</row>')

    $rowIndex = 2
    foreach ($row in $items) {
        $styleIndex = 0
        if (-not [string]::IsNullOrWhiteSpace($RowClassProperty)) {
            $styleIndex = Get-XlsxStyleIndex -ChangeType (Get-ObjectPropertyValue -InputObject $row -Name $RowClassProperty)
        }

        [void]$builder.AppendLine(('<row r="{0}">' -f $rowIndex))
        for ($columnIndex = 1; $columnIndex -le $Columns.Count; $columnIndex++) {
            $column = $Columns[$columnIndex - 1]
            $cellReference = (ConvertTo-ExcelColumnName -Index $columnIndex) + $rowIndex
            $styleAttribute = if ($styleIndex -gt 0) { ' s="' + $styleIndex + '"' } else { '' }
            $value = ConvertTo-XmlEscaped -Value (Get-ObjectPropertyValue -InputObject $row -Name $column)
            [void]$builder.AppendLine(('<c r="{0}" t="inlineStr"{1}><is><t xml:space="preserve">{2}</t></is></c>' -f $cellReference, $styleAttribute, $value))
        }
        [void]$builder.AppendLine('</row>')
        $rowIndex++
    }

    [void]$builder.AppendLine('</sheetData>')
    [void]$builder.AppendLine(('<autoFilter ref="{0}"/>' -f $range))
    [void]$builder.AppendLine('</worksheet>')
    return $builder.ToString()
}

function Get-SafeWorksheetName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]]$UsedNames
    )

    $safeName = [regex]::Replace($Name, '[:\\/?*\[\]]', ' ')
    $safeName = $safeName.Trim()
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = 'Sheet'
    }

    if ($safeName.Length -gt 31) {
        $safeName = $safeName.Substring(0, 31)
    }

    $candidate = $safeName
    $suffix = 2
    while ($UsedNames.Contains($candidate)) {
        $baseLength = [math]::Min(31 - (" $suffix").Length, $safeName.Length)
        $candidate = $safeName.Substring(0, $baseLength) + " $suffix"
        $suffix++
    }

    $UsedNames.Add($candidate) | Out-Null
    return $candidate
}

function Write-XlsxWorkbook {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object[]]$Sheets
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $outputDirectory = Split-Path -Path $resolvedPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    }

    $workDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().ToString('N'))
    $usedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    try {
        New-Item -Path $workDir -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $workDir -ChildPath '_rels') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $workDir -ChildPath 'docProps') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $workDir -ChildPath 'xl') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $workDir -ChildPath 'xl/_rels') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path -Path $workDir -ChildPath 'xl/worksheets') -ItemType Directory -Force | Out-Null

        $sheetDefinitions = New-Object System.Collections.Generic.List[object]
        for ($sheetIndex = 1; $sheetIndex -le $Sheets.Count; $sheetIndex++) {
            $sheet = $Sheets[$sheetIndex - 1]
            $sheetName = Get-SafeWorksheetName -Name $sheet.Name -UsedNames $usedNames
            $sheetDefinitions.Add([pscustomobject]@{
                Id               = $sheetIndex
                Name             = $sheetName
                Rows             = @($sheet.Rows)
                Columns          = [string[]]$sheet.Columns
                RowClassProperty = ConvertTo-ComparableValue -Value $sheet.RowClassProperty
            }) | Out-Null
        }

        $contentTypes = [System.Text.StringBuilder]::new()
        [void]$contentTypes.AppendLine('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        [void]$contentTypes.AppendLine('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
        [void]$contentTypes.AppendLine('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
        [void]$contentTypes.AppendLine('<Default Extension="xml" ContentType="application/xml"/>')
        [void]$contentTypes.AppendLine('<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>')
        [void]$contentTypes.AppendLine('<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>')
        [void]$contentTypes.AppendLine('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
        [void]$contentTypes.AppendLine('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
        foreach ($sheetDefinition in $sheetDefinitions) {
            [void]$contentTypes.AppendLine(('<Override PartName="/xl/worksheets/sheet{0}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' -f $sheetDefinition.Id))
        }
        [void]$contentTypes.AppendLine('</Types>')
        Set-Utf8NoBomTextFile -Path (Join-Path -Path $workDir -ChildPath '[Content_Types].xml') -Value $contentTypes.ToString()

        Set-Utf8NoBomTextFile -Path (Join-Path -Path $workDir -ChildPath '_rels/.rels') -Value @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
'@

        $createdAt = (Get-Date).ToUniversalTime().ToString('o')
        Set-Utf8NoBomTextFile -Path (Join-Path -Path $workDir -ChildPath 'docProps/core.xml') -Value @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<dc:creator>OUBuilder</dc:creator>
<cp:lastModifiedBy>OUBuilder</cp:lastModifiedBy>
<dcterms:created xsi:type="dcterms:W3CDTF">$createdAt</dcterms:created>
<dcterms:modified xsi:type="dcterms:W3CDTF">$createdAt</dcterms:modified>
</cp:coreProperties>
"@

        Set-Utf8NoBomTextFile -Path (Join-Path -Path $workDir -ChildPath 'docProps/app.xml') -Value @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
<Application>OUBuilder</Application>
</Properties>
'@

        $workbookXml = [System.Text.StringBuilder]::new()
        [void]$workbookXml.AppendLine('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        [void]$workbookXml.AppendLine('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')
        [void]$workbookXml.AppendLine('<sheets>')
        foreach ($sheetDefinition in $sheetDefinitions) {
            [void]$workbookXml.AppendLine(('<sheet name="{0}" sheetId="{1}" r:id="rId{1}"/>' -f (ConvertTo-XmlEscaped -Value $sheetDefinition.Name), $sheetDefinition.Id))
        }
        [void]$workbookXml.AppendLine('</sheets>')
        [void]$workbookXml.AppendLine('</workbook>')
        Set-Utf8NoBomTextFile -Path (Join-Path -Path $workDir -ChildPath 'xl/workbook.xml') -Value $workbookXml.ToString()

        $workbookRels = [System.Text.StringBuilder]::new()
        [void]$workbookRels.AppendLine('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        [void]$workbookRels.AppendLine('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')
        foreach ($sheetDefinition in $sheetDefinitions) {
            [void]$workbookRels.AppendLine(('<Relationship Id="rId{0}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{0}.xml"/>' -f $sheetDefinition.Id))
        }
        [void]$workbookRels.AppendLine(('<Relationship Id="rId{0}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>' -f ($sheetDefinitions.Count + 1)))
        [void]$workbookRels.AppendLine('</Relationships>')
        Set-Utf8NoBomTextFile -Path (Join-Path -Path $workDir -ChildPath 'xl/_rels/workbook.xml.rels') -Value $workbookRels.ToString()

        Set-Utf8NoBomTextFile -Path (Join-Path -Path $workDir -ChildPath 'xl/styles.xml') -Value @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="7">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFD9E1F2"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFE2F0D9"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFF4CCCC"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFFFF2CC"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFDDEBF7"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="6">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
<xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1"/>
<xf numFmtId="0" fontId="0" fillId="4" borderId="0" xfId="0" applyFill="1"/>
<xf numFmtId="0" fontId="0" fillId="5" borderId="0" xfId="0" applyFill="1"/>
<xf numFmtId="0" fontId="0" fillId="6" borderId="0" xfId="0" applyFill="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
'@

        foreach ($sheetDefinition in $sheetDefinitions) {
            $worksheetXml = New-XlsxWorksheetXml -Rows $sheetDefinition.Rows -Columns $sheetDefinition.Columns -RowClassProperty $sheetDefinition.RowClassProperty
            Set-Utf8NoBomTextFile -Path (Join-Path -Path $workDir -ChildPath ('xl/worksheets/sheet{0}.xml' -f $sheetDefinition.Id)) -Value $worksheetXml
        }

        if (Test-Path -LiteralPath $resolvedPath) {
            [System.IO.File]::Delete($resolvedPath)
        }

        [System.IO.Compression.ZipFile]::CreateFromDirectory($workDir, $resolvedPath)
    }
    finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Export-ComparisonWorkbook {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Comparison,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $sheets = @(
        [pscustomobject]@{ Name = 'Summary'; Rows = $Comparison.Summary; Columns = @('Metric', 'Count'); RowClassProperty = '' },
        [pscustomobject]@{ Name = 'SideBySideReview'; Rows = $Comparison.SideBySide; Columns = $script:SideBySideColumns; RowClassProperty = 'ChangeType' },
        [pscustomobject]@{ Name = 'Added'; Rows = $Comparison.Added; Columns = $script:SnapshotColumns; RowClassProperty = '' },
        [pscustomobject]@{ Name = 'Removed'; Rows = $Comparison.Removed; Columns = $script:SnapshotColumns; RowClassProperty = '' },
        [pscustomobject]@{ Name = 'MovedOrRenamed'; Rows = $Comparison.MovedOrRenamed; Columns = $script:MovedOrRenamedColumns; RowClassProperty = '' },
        [pscustomobject]@{ Name = 'AttributeChanges'; Rows = $Comparison.AttributeChanges; Columns = $script:AttributeChangeColumns; RowClassProperty = '' }
    )

    Write-XlsxWorkbook -Path $Path -Sheets $sheets
}

function Import-ADOUSnapshotFile {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path
    )

    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $json = $content | ConvertFrom-Json

    if ($null -ne $json.PSObject.Properties['OUs']) {
        return $json
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = 0
        OUs           = @($json)
    }
}

function New-GuidRecordMap {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object[]]$Records,

        [Parameter(Mandatory = $true)]
        [string]$SnapshotName
    )

    $map = @{}
    foreach ($record in @($Records)) {
        $guidKey = ConvertTo-GuidKey -Value (Get-ObjectPropertyValue -InputObject $record -Name 'ObjectGuid')
        if ([string]::IsNullOrWhiteSpace($guidKey)) {
            throw "$SnapshotName snapshot contains an OU row with a blank ObjectGuid."
        }

        if ($map.ContainsKey($guidKey)) {
            throw "$SnapshotName snapshot contains duplicate ObjectGuid '$guidKey'."
        }

        $map[$guidKey] = $record
    }

    return $map
}

function New-ComparisonSummary {
    param(
        [Parameter(Mandatory = $true)]
        [int]$PreCount,

        [Parameter(Mandatory = $true)]
        [int]$PostCount,

        [Parameter(Mandatory = $true)]
        [int]$AddedCount,

        [Parameter(Mandatory = $true)]
        [int]$RemovedCount,

        [Parameter(Mandatory = $true)]
        [int]$MovedCount,

        [Parameter(Mandatory = $true)]
        [int]$RenamedCount,

        [Parameter(Mandatory = $true)]
        [int]$MovedAndRenamedCount,

        [Parameter(Mandatory = $true)]
        [int]$AttributeChangedOuCount,

        [Parameter(Mandatory = $true)]
        [int]$AttributeOnlyOuCount,

        [Parameter(Mandatory = $true)]
        [int]$AttributeChangeRowCount
    )

    return @(
        [pscustomobject][ordered]@{ Metric = 'PreSnapshotOUCount'; Count = $PreCount },
        [pscustomobject][ordered]@{ Metric = 'PostSnapshotOUCount'; Count = $PostCount },
        [pscustomobject][ordered]@{ Metric = 'AddedOUs'; Count = $AddedCount },
        [pscustomobject][ordered]@{ Metric = 'RemovedOUs'; Count = $RemovedCount },
        [pscustomobject][ordered]@{ Metric = 'MovedOUs'; Count = $MovedCount },
        [pscustomobject][ordered]@{ Metric = 'RenamedOUs'; Count = $RenamedCount },
        [pscustomobject][ordered]@{ Metric = 'MovedAndRenamedOUs'; Count = $MovedAndRenamedCount },
        [pscustomobject][ordered]@{ Metric = 'AttributeChangedOUs'; Count = $AttributeChangedOuCount },
        [pscustomobject][ordered]@{ Metric = 'AttributeOnlyChangedOUs'; Count = $AttributeOnlyOuCount },
        [pscustomobject][ordered]@{ Metric = 'AttributeChangeRows'; Count = $AttributeChangeRowCount }
    )
}

function New-SideBySideReviewRows {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$PreByGuid,

        [Parameter(Mandatory = $true)]
        [hashtable]$PostByGuid,

        [Parameter(Mandatory = $true)]
        [hashtable]$HierarchyChangeByGuid
    )

    $allGuidKeys = @(@($PreByGuid.Keys) + @($PostByGuid.Keys) | Sort-Object -Unique)
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($guidKey in $allGuidKeys) {
        $old = if ($PreByGuid.ContainsKey($guidKey)) { $PreByGuid[$guidKey] } else { $null }
        $new = if ($PostByGuid.ContainsKey($guidKey)) { $PostByGuid[$guidKey] } else { $null }

        $changedAttributes = New-Object System.Collections.Generic.List[string]
        foreach ($field in $script:AttributeCompareFields) {
            if ($null -eq $old -or $null -eq $new) {
                continue
            }

            if (Test-AuditValueChanged `
                    -OldValue (Get-ObjectPropertyValue -InputObject $old -Name $field) `
                    -NewValue (Get-ObjectPropertyValue -InputObject $new -Name $field)) {
                $changedAttributes.Add($field) | Out-Null
            }
        }

        $hasAttributeChanges = ($changedAttributes.Count -gt 0)
        $changeType = if ($null -eq $old) {
            'Added'
        }
        elseif ($null -eq $new) {
            'Removed'
        }
        elseif ($HierarchyChangeByGuid.ContainsKey($guidKey)) {
            $HierarchyChangeByGuid[$guidKey]
        }
        elseif ($hasAttributeChanges) {
            'AttributeOnly'
        }
        else {
            'Unchanged'
        }

        $sortRecord = if ($null -ne $new) { $new } else { $old }

        $rows.Add([pscustomobject][ordered]@{
            SortKey                                 = Get-ADOUHierarchySortKey -Record $sortRecord
            ChangeType                              = $changeType
            HasAttributeChanges                     = $hasAttributeChanges
            ChangedAttributes                       = ($changedAttributes -join '; ')
            ObjectGuid                              = $guidKey
            PrePath                                 = Get-ReviewPath -Record $old
            PostPath                                = Get-ReviewPath -Record $new
            PreDepth                                = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'Depth')
            PostDepth                               = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'Depth')
            PreName                                 = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'Name')
            PostName                                = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'Name')
            PreRdnValue                             = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'RdnValue')
            PostRdnValue                            = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'RdnValue')
            PreParentDistinguishedName              = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'ParentDistinguishedName')
            PostParentDistinguishedName             = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'ParentDistinguishedName')
            PreDistinguishedName                    = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'DistinguishedName')
            PostDistinguishedName                   = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'DistinguishedName')
            PreCanonicalName                        = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'CanonicalName')
            PostCanonicalName                       = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'CanonicalName')
            DescriptionChanged                      = $changedAttributes.Contains('Description')
            PreDescription                          = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'Description')
            PostDescription                         = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'Description')
            ManagedByChanged                        = $changedAttributes.Contains('ManagedBy')
            PreManagedBy                            = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'ManagedBy')
            PostManagedBy                           = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'ManagedBy')
            ProtectedFromAccidentalDeletionChanged  = $changedAttributes.Contains('ProtectedFromAccidentalDeletion')
            PreProtectedFromAccidentalDeletion      = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'ProtectedFromAccidentalDeletion')
            PostProtectedFromAccidentalDeletion     = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'ProtectedFromAccidentalDeletion')
            GPLinkChanged                           = $changedAttributes.Contains('gPLink')
            PreGPLink                               = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'gPLink')
            PostGPLink                              = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'gPLink')
            GPOptionsChanged                        = $changedAttributes.Contains('gPOptions')
            PreGPOptions                            = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'gPOptions')
            PostGPOptions                           = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'gPOptions')
            WhenCreatedChanged                      = $changedAttributes.Contains('whenCreated')
            PreWhenCreated                          = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'whenCreated')
            PostWhenCreated                         = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'whenCreated')
            WhenChangedChanged                      = $changedAttributes.Contains('whenChanged')
            PreWhenChanged                          = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'whenChanged')
            PostWhenChanged                         = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'whenChanged')
        }) | Out-Null
    }

    return @($rows.ToArray() | Sort-Object -Property @{ Expression = 'SortKey'; Ascending = $true }, @{ Expression = 'ObjectGuid'; Ascending = $true })
}

function Compare-ADOUSnapshotObjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$PreOUs,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$PostOUs,

        [Parameter(Mandatory = $false)]
        [string]$Label = 'ou-comparison'
    )

    $preItems = @(Sort-ADOURecords -Records $PreOUs)
    $postItems = @(Sort-ADOURecords -Records $PostOUs)
    $preByGuid = New-GuidRecordMap -Records $preItems -SnapshotName 'Pre-change'
    $postByGuid = New-GuidRecordMap -Records $postItems -SnapshotName 'Post-change'

    $added = New-Object System.Collections.Generic.List[object]
    $removed = New-Object System.Collections.Generic.List[object]
    $movedOrRenamed = New-Object System.Collections.Generic.List[object]
    $attributeChanges = New-Object System.Collections.Generic.List[object]
    $hierarchyChangeByGuid = @{}

    foreach ($guidKey in @($postByGuid.Keys | Sort-Object)) {
        if (-not $preByGuid.ContainsKey($guidKey)) {
            $added.Add($postByGuid[$guidKey]) | Out-Null
        }
    }

    foreach ($guidKey in @($preByGuid.Keys | Sort-Object)) {
        if (-not $postByGuid.ContainsKey($guidKey)) {
            $removed.Add($preByGuid[$guidKey]) | Out-Null
        }
    }

    foreach ($guidKey in @($preByGuid.Keys | Where-Object { $postByGuid.ContainsKey($_) } | Sort-Object)) {
        $old = $preByGuid[$guidKey]
        $new = $postByGuid[$guidKey]

        $oldParentKey = ConvertTo-DistinguishedNameKey -DistinguishedName (Get-ObjectPropertyValue -InputObject $old -Name 'ParentDistinguishedName')
        $newParentKey = ConvertTo-DistinguishedNameKey -DistinguishedName (Get-ObjectPropertyValue -InputObject $new -Name 'ParentDistinguishedName')
        $oldRdn = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'RdnValue')
        $newRdn = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'RdnValue')
        $oldName = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'Name')
        $newName = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'Name')

        $moved = -not [string]::Equals($oldParentKey, $newParentKey, [System.StringComparison]::OrdinalIgnoreCase)
        $renamed = (-not [string]::Equals($oldRdn, $newRdn, [System.StringComparison]::Ordinal)) -or (-not [string]::Equals($oldName, $newName, [System.StringComparison]::Ordinal))

        if ($moved -or $renamed) {
            $changeType = if ($moved -and $renamed) {
                'MovedAndRenamed'
            }
            elseif ($moved) {
                'Moved'
            }
            else {
                'Renamed'
            }

            $hierarchyChangeByGuid[$guidKey] = $changeType
            $movedOrRenamed.Add([pscustomobject][ordered]@{
                ObjectGuid                     = $guidKey
                ChangeType                     = $changeType
                OldName                        = $oldName
                NewName                        = $newName
                OldRdnValue                    = $oldRdn
                NewRdnValue                    = $newRdn
                OldParentDistinguishedName     = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'ParentDistinguishedName')
                NewParentDistinguishedName     = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'ParentDistinguishedName')
                OldDistinguishedName           = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'DistinguishedName')
                NewDistinguishedName           = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'DistinguishedName')
                OldCanonicalName               = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'CanonicalName')
                NewCanonicalName               = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'CanonicalName')
            }) | Out-Null
        }

        foreach ($field in $script:AttributeCompareFields) {
            $oldValue = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name $field)
            $newValue = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name $field)

            if (-not [string]::Equals($oldValue, $newValue, [System.StringComparison]::Ordinal)) {
                $attributeChanges.Add([pscustomobject][ordered]@{
                    ObjectGuid           = $guidKey
                    ChangeScope          = if ($moved -or $renamed) { 'HierarchyAndAttribute' } else { 'AttributeOnly' }
                    AttributeName        = $field
                    OldValue             = $oldValue
                    NewValue             = $newValue
                    OldName              = $oldName
                    NewName              = $newName
                    OldDistinguishedName = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $old -Name 'DistinguishedName')
                    NewDistinguishedName = ConvertTo-ComparableValue -Value (Get-ObjectPropertyValue -InputObject $new -Name 'DistinguishedName')
                }) | Out-Null
            }
        }
    }

    $attributeChangedGuids = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $attributeOnlyGuids = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($change in $attributeChanges) {
        $guidKey = ConvertTo-GuidKey -Value $change.ObjectGuid
        $attributeChangedGuids.Add($guidKey) | Out-Null
        if (-not $hierarchyChangeByGuid.ContainsKey($guidKey)) {
            $attributeOnlyGuids.Add($guidKey) | Out-Null
        }
    }

    $movedCount = @($movedOrRenamed | Where-Object { $_.ChangeType -eq 'Moved' }).Count
    $renamedCount = @($movedOrRenamed | Where-Object { $_.ChangeType -eq 'Renamed' }).Count
    $movedAndRenamedCount = @($movedOrRenamed | Where-Object { $_.ChangeType -eq 'MovedAndRenamed' }).Count

    $summary = New-ComparisonSummary `
        -PreCount $preItems.Count `
        -PostCount $postItems.Count `
        -AddedCount $added.Count `
        -RemovedCount $removed.Count `
        -MovedCount $movedCount `
        -RenamedCount $renamedCount `
        -MovedAndRenamedCount $movedAndRenamedCount `
        -AttributeChangedOuCount $attributeChangedGuids.Count `
        -AttributeOnlyOuCount $attributeOnlyGuids.Count `
        -AttributeChangeRowCount $attributeChanges.Count

    $highlightByGuid = @{}
    foreach ($item in $added) {
        $highlightByGuid[(ConvertTo-GuidKey -Value $item.ObjectGuid)] = 'Added'
    }
    foreach ($item in $movedOrRenamed) {
        $highlightByGuid[(ConvertTo-GuidKey -Value $item.ObjectGuid)] = 'MovedOrRenamed'
    }
    foreach ($guidKey in $attributeOnlyGuids) {
        if (-not $highlightByGuid.ContainsKey($guidKey)) {
            $highlightByGuid[$guidKey] = 'AttributeOnly'
        }
    }

    $sideBySideRows = @(New-SideBySideReviewRows `
        -PreByGuid $preByGuid `
        -PostByGuid $postByGuid `
        -HierarchyChangeByGuid $hierarchyChangeByGuid)

    $addedItems = @($added.ToArray())
    $removedItems = @($removed.ToArray())
    $movedOrRenamedItems = @($movedOrRenamed.ToArray())
    $attributeChangeItems = @($attributeChanges.ToArray())

    $movedOrRenamedSorted = @(
        $movedOrRenamedItems |
            Sort-Object -Property @{ Expression = { Get-DistinguishedNameHierarchySortKey -DistinguishedName $_.NewDistinguishedName }; Ascending = $true }, @{ Expression = 'ObjectGuid'; Ascending = $true }
    )
    $attributeChangesSorted = @(
        $attributeChangeItems |
            Sort-Object -Property @{ Expression = { Get-DistinguishedNameHierarchySortKey -DistinguishedName $_.NewDistinguishedName }; Ascending = $true }, @{ Expression = 'AttributeName'; Ascending = $true }, @{ Expression = 'ObjectGuid'; Ascending = $true }
    )

    return [pscustomobject][ordered]@{
        Label               = $Label
        Summary             = @($summary)
        Added               = @(Sort-ADOURecords -Records $addedItems)
        Removed             = @(Sort-ADOURecords -Records $removedItems)
        MovedOrRenamed      = @($movedOrRenamedSorted)
        AttributeChanges    = @($attributeChangesSorted)
        SideBySide          = @($sideBySideRows)
        HighlightByGuid     = $highlightByGuid
        PostRecords         = @($postItems)
    }
}

function Invoke-ADOUStructureSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SearchBase,

        [Parameter(Mandatory = $false)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Label
    )

    Import-RequiredActiveDirectoryModule
    $outputDirectory = Resolve-OutputDirectory -OutputRoot $OutputRoot -Label $Label

    $queryParameters = @{
        LDAPFilter  = '(objectClass=organizationalUnit)'
        SearchBase  = $SearchBase
        SearchScope = 'Subtree'
        Properties  = @(
            'ObjectGuid',
            'CanonicalName',
            'Description',
            'ManagedBy',
            'ProtectedFromAccidentalDeletion',
            'gPLink',
            'gPOptions',
            'whenCreated',
            'whenChanged'
        )
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $queryParameters.Server = $Server
    }

    Write-Host "Reading Active Directory OUs under '$SearchBase'..."
    $adOus = @(Get-ADOrganizationalUnit @queryParameters)
    $records = @(Sort-ADOURecords -Records @($adOus | ForEach-Object { New-ADOUSnapshotRecord -ADObject $_ -SearchBase $SearchBase }))

    $snapshot = [pscustomobject][ordered]@{
        SchemaVersion = 1
        SnapshotType  = 'ADOUStructureAuditSnapshot'
        CapturedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        SearchBase    = $SearchBase
        Server        = if ([string]::IsNullOrWhiteSpace($Server)) { '' } else { $Server }
        Label         = $Label
        OUCount       = $records.Count
        OUs           = @($records)
    }

    $jsonPath = Join-Path -Path $outputDirectory -ChildPath 'ou-snapshot.json'
    $csvPath = Join-Path -Path $outputDirectory -ChildPath 'ou-snapshot.csv'
    $treePath = Join-Path -Path $outputDirectory -ChildPath 'ou-tree.txt'
    $htmlPath = Join-Path -Path $outputDirectory -ChildPath 'ou-snapshot.html'

    Set-Utf8NoBomTextFile -Path $jsonPath -Value ($snapshot | ConvertTo-Json -Depth 8)
    Export-CsvWithHeader -Records $records -Columns $script:SnapshotColumns -Path $csvPath

    $treeText = New-ADOUTreeText -Records $records -SearchBase $SearchBase
    Set-Utf8NoBomTextFile -Path $treePath -Value $treeText

    $htmlText = New-SnapshotHtml -Snapshot $snapshot -Records $records -TreeText $treeText
    Set-Utf8NoBomTextFile -Path $htmlPath -Value $htmlText

    Write-Host "Snapshot written to: $outputDirectory"
    return [pscustomobject][ordered]@{
        OutputDirectory = $outputDirectory
        JsonPath        = $jsonPath
        CsvPath         = $csvPath
        TreeTextPath    = $treePath
        HtmlPath        = $htmlPath
        OUCount         = $records.Count
    }
}

function Compare-ADOUStructureSnapshots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$PreSnapshot,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$PostSnapshot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputRoot,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Label
    )

    $outputDirectory = Resolve-OutputDirectory -OutputRoot $OutputRoot -Label $Label
    $pre = Import-ADOUSnapshotFile -Path $PreSnapshot
    $post = Import-ADOUSnapshotFile -Path $PostSnapshot
    $comparison = Compare-ADOUSnapshotObjects -PreOUs @($pre.OUs) -PostOUs @($post.OUs) -Label $Label

    $summaryPath = Join-Path -Path $outputDirectory -ChildPath 'comparison-summary.csv'
    $addedPath = Join-Path -Path $outputDirectory -ChildPath 'added-ous.csv'
    $removedPath = Join-Path -Path $outputDirectory -ChildPath 'removed-ous.csv'
    $movedPath = Join-Path -Path $outputDirectory -ChildPath 'moved-or-renamed-ous.csv'
    $attributePath = Join-Path -Path $outputDirectory -ChildPath 'attribute-changes.csv'
    $sideBySidePath = Join-Path -Path $outputDirectory -ChildPath 'comparison-side-by-side.csv'
    $htmlPath = Join-Path -Path $outputDirectory -ChildPath 'comparison-report.html'
    $workbookPath = Join-Path -Path $outputDirectory -ChildPath 'comparison-review.xlsx'

    Export-CsvWithHeader -Records $comparison.Summary -Columns @('Metric', 'Count') -Path $summaryPath
    Export-CsvWithHeader -Records $comparison.Added -Columns $script:SnapshotColumns -Path $addedPath
    Export-CsvWithHeader -Records $comparison.Removed -Columns $script:SnapshotColumns -Path $removedPath
    Export-CsvWithHeader -Records $comparison.MovedOrRenamed -Columns $script:MovedOrRenamedColumns -Path $movedPath
    Export-CsvWithHeader -Records $comparison.AttributeChanges -Columns $script:AttributeChangeColumns -Path $attributePath
    Export-CsvWithHeader -Records $comparison.SideBySide -Columns $script:SideBySideColumns -Path $sideBySidePath

    $htmlText = New-ComparisonHtml -Comparison $comparison
    Set-Utf8NoBomTextFile -Path $htmlPath -Value $htmlText
    Export-ComparisonWorkbook -Comparison $comparison -Path $workbookPath

    Write-Host "Comparison written to: $outputDirectory"
    return [pscustomobject][ordered]@{
        OutputDirectory = $outputDirectory
        SummaryPath     = $summaryPath
        AddedPath       = $addedPath
        RemovedPath     = $removedPath
        MovedPath       = $movedPath
        AttributePath   = $attributePath
        SideBySidePath  = $sideBySidePath
        HtmlPath        = $htmlPath
        WorkbookPath    = $workbookPath
        Summary         = $comparison.Summary
    }
}

function Invoke-ADOUStructureAudit {
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
        [string]$Label,

        [Parameter(Mandatory = $false)]
        [string]$PreSnapshot,

        [Parameter(Mandatory = $false)]
        [string]$PostSnapshot
    )

    switch ($Mode) {
        'Snapshot' {
            if ([string]::IsNullOrWhiteSpace($SearchBase)) {
                throw 'Snapshot mode requires -SearchBase.'
            }

            return Invoke-ADOUStructureSnapshot -SearchBase $SearchBase -Server $Server -OutputRoot $OutputRoot -Label $Label
        }
        'Compare' {
            if ([string]::IsNullOrWhiteSpace($PreSnapshot)) {
                throw 'Compare mode requires -PreSnapshot.'
            }
            if ([string]::IsNullOrWhiteSpace($PostSnapshot)) {
                throw 'Compare mode requires -PostSnapshot.'
            }

            return Compare-ADOUStructureSnapshots -PreSnapshot $PreSnapshot -PostSnapshot $PostSnapshot -OutputRoot $OutputRoot -Label $Label
        }
    }
}

Export-ModuleMember -Function @(
    'Invoke-ADOUStructureAudit',
    'Invoke-ADOUStructureSnapshot',
    'Compare-ADOUStructureSnapshots',
    'Compare-ADOUSnapshotObjects',
    'Split-ADDistinguishedName',
    'Get-ADParentDistinguishedName',
    'Get-ADRdnValue',
    'Get-ADDistinguishedNameDepth'
)
