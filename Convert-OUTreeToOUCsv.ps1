<#
.SYNOPSIS
Converts an OUTree source CSV into the OU CSV schema used by Create-ADOrganizationalUnits.ps1.

.DESCRIPTION
Reads a CSV with Depth0 through Depth9 columns, expands missing parent OUs,
validates the generated rows, and writes a CSV compatible with Create-ADOrganizationalUnits.ps1.

.EXAMPLE
.\Convert-OUTreeToOUCsv.ps1 `
  -InputCsv .\01-examples\input\OUTree_ad-example-com-v1.csv `
  -OutputCsv .\01-examples\output\ad-example-com-v1.csv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$InputCsv,

    [Parameter(Mandatory = $false)]
    [string]$OutputCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MaxOuDepth = 9
$DepthColumns = @(0..$MaxOuDepth | ForEach-Object { "Depth$_" })

$CsvColumns = @('Create') + $DepthColumns + @(
    'FullPath',
    'Depth',
    'OUName',
    'ParentPath',
    'Description',
    'ProtectedFromAccidentalDeletion',
    'Notes'
)

$SpellingCorrections = [ordered]@{
    'Non Syncying' = 'Non Syncing'
}
$ScriptSafeParentNote = 'Added explicit parent row for script-safe creation order'

function Get-CleanText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return '' }
    return $Value.ToString().Trim()
}

function Get-DefaultOutputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceCsvPath
    )

    $resolvedInput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourceCsvPath)
    $directory = Split-Path -Path $resolvedInput -Parent
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($resolvedInput)

    if ($stem.StartsWith('OUTree_', [System.StringComparison]::OrdinalIgnoreCase)) {
        $stem = $stem.Substring(7)
    }

    return (Join-Path -Path $directory -ChildPath "$stem.csv")
}

function Get-PropertyText {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    $property = $Row.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return '' }
    return (Get-CleanText -Value $property.Value)
}

function Test-NoInteriorBlankDepths {
    param(
        [Parameter(Mandatory = $true)]
        [int]$RowNumber,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Parts
    )

    $seenBlank = $false
    foreach ($part in $Parts) {
        if ([string]::IsNullOrWhiteSpace($part)) {
            $seenBlank = $true
            continue
        }

        if ($seenBlank) {
            throw "Row $RowNumber has an OU value after a blank depth column. Fill parent depth columns before child depth columns."
        }
    }
}

function Invoke-SpellingCorrections {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $corrected = $Text
    $notes = [System.Collections.Generic.List[string]]::new()

    foreach ($oldValue in $SpellingCorrections.Keys) {
        $newValue = $SpellingCorrections[$oldValue]
        if ($corrected.Contains($oldValue)) {
            $corrected = $corrected.Replace($oldValue, $newValue)
            $notes.Add("Corrected spelling from $oldValue to $newValue")
        }
    }

    [pscustomobject]@{
        Text  = $corrected
        Notes = @($notes)
    }
}

function Join-UniqueNotes {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [AllowNull()]
        [object[]]$NoteGroups
    )

    $notes = [System.Collections.Generic.List[string]]::new()
    foreach ($group in $NoteGroups) {
        if ($null -eq $group) { continue }
        foreach ($note in @($group)) {
            $text = Get-CleanText -Value $note
            if (-not [string]::IsNullOrWhiteSpace($text) -and -not $notes.Contains($text)) {
                $notes.Add($text)
            }
        }
    }

    return ($notes -join '; ')
}

function Join-PathParts {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Parts
    )

    return (($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join '/')
}

function Read-SourcePaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceCsvPath
    )

    $rows = @(Import-Csv -LiteralPath $SourceCsvPath)
    if ($rows.Count -eq 0) {
        throw "Source CSV '$SourceCsvPath' has no data rows."
    }

    $propertyNames = @($rows[0].PSObject.Properties.Name)
    if ('Depth0' -notin $propertyNames) {
        throw "Source CSV header is missing required column 'Depth0'."
    }

    $unsupportedDepthColumns = @(
        $propertyNames |
            Where-Object { $_ -match '^Depth(\d+)$' -and [int]$Matches[1] -gt $MaxOuDepth }
    )
    if ($unsupportedDepthColumns.Count -gt 0) {
        throw "Source CSV has unsupported depth columns: $($unsupportedDepthColumns -join ', '). The converter supports Depth0 through Depth$MaxOuDepth."
    }

    $domains = [System.Collections.Generic.List[string]]::new()
    $sourcePaths = [System.Collections.Generic.List[object]]::new()
    $rowNumber = 1

    foreach ($row in $rows) {
        $rowNumber++
        $cells = @($DepthColumns | ForEach-Object { Get-PropertyText -Row $row -PropertyName $_ })

        if (@($cells | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) {
            continue
        }

        $domain = $cells[0]
        $ouParts = @($cells[1..$MaxOuDepth])
        Test-NoInteriorBlankDepths -RowNumber $rowNumber -Parts $ouParts

        if (-not [string]::IsNullOrWhiteSpace($domain)) {
            if (-not $domains.Contains($domain)) {
                $domains.Add($domain)
            }
        }
        elseif (@($ouParts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            throw "Row $rowNumber has OU depth values but a blank Depth0 domain."
        }

        $rawParts = @($ouParts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($rawParts.Count -eq 0) {
            continue
        }

        $rawPath = Join-PathParts -Parts $rawParts
        $correction = Invoke-SpellingCorrections -Text $rawPath
        $sourcePaths.Add([pscustomobject]@{
            RawPath       = $rawPath
            CorrectedPath = $correction.Text
            Notes         = @($correction.Notes)
        })
    }

    if ($domains.Count -eq 0) {
        throw 'No domain value found in Depth0.'
    }
    if ($domains.Count -gt 1) {
        throw "Expected one Depth0 domain, found: $($domains -join ', ')"
    }

    [pscustomobject]@{
        Domain      = $domains[0]
        SourcePaths = @($sourcePaths)
    }
}

function New-OuRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [string]$FullPath,

        [Parameter(Mandatory = $false)]
        [string]$Notes
    )

    $parts = @($FullPath -split '/' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -gt $MaxOuDepth) {
        throw "FullPath has more than $MaxOuDepth OU levels and cannot fit Depth1-Depth$($MaxOuDepth): $FullPath"
    }

    $paddedParts = @($parts)
    while ($paddedParts.Count -lt $MaxOuDepth) {
        $paddedParts += ''
    }

    $parentPath = ''
    if ($parts.Count -gt 1) {
        $parentPath = ($parts[0..($parts.Count - 2)] -join '/')
    }

    $record = [ordered]@{
        Create = 'TRUE'
        Depth0 = $Domain
    }

    foreach ($index in 1..$MaxOuDepth) {
        $record["Depth$index"] = $paddedParts[$index - 1]
    }

    $record['FullPath'] = $FullPath
    $record['Depth'] = $parts.Count.ToString()
    $record['OUName'] = $parts[-1]
    $record['ParentPath'] = $parentPath
    $record['Description'] = ''
    $record['ProtectedFromAccidentalDeletion'] = 'TRUE'
    $record['Notes'] = (Get-CleanText -Value $Notes)

    [pscustomobject]$record
}

function New-OuRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,

        [Parameter(Mandatory = $true)]
        [object[]]$SourcePaths
    )

    $explicitPathNotes = @{}
    foreach ($sourcePath in $SourcePaths) {
        if (-not $explicitPathNotes.ContainsKey($sourcePath.CorrectedPath)) {
            $explicitPathNotes[$sourcePath.CorrectedPath] = @($sourcePath.Notes)
        }
    }

    $records = [System.Collections.Generic.List[object]]::new()
    $emittedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($sourcePath in $SourcePaths) {
        $rawParts = @($sourcePath.RawPath -split '/')
        $correctedParts = @($sourcePath.CorrectedPath -split '/')

        for ($depth = 1; $depth -le $correctedParts.Count; $depth++) {
            $fullPath = ($correctedParts[0..($depth - 1)] -join '/')
            if ($emittedPaths.Contains($fullPath)) {
                continue
            }

            $rawPrefix = ($rawParts[0..($depth - 1)] -join '/')
            $prefixCorrection = Invoke-SpellingCorrections -Text $rawPrefix

            if ($explicitPathNotes.ContainsKey($fullPath)) {
                $notes = Join-UniqueNotes $explicitPathNotes[$fullPath]
            }
            else {
                $correctionNotes = if ($prefixCorrection.Notes.Count -gt 0) { @($prefixCorrection.Notes) } else { @($sourcePath.Notes) }
                $notes = Join-UniqueNotes @($ScriptSafeParentNote) $correctionNotes
            }

            $records.Add((New-OuRecord -Domain $Domain -FullPath $fullPath -Notes $notes))
            [void]$emittedPaths.Add($fullPath)
        }
    }

    return @($records)
}

function Test-OuRecords {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Records
    )

    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $duplicatePaths = [System.Collections.Generic.List[string]]::new()
    $rowNumber = 1

    foreach ($record in $Records) {
        $rowNumber++
        $fullPath = Get-CleanText -Value $record.FullPath
        if ([string]::IsNullOrWhiteSpace($fullPath)) {
            throw "Generated row $rowNumber has a blank FullPath."
        }

        $parts = @($fullPath -split '/' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($parts.Count.ToString() -ne (Get-CleanText -Value $record.Depth)) {
            throw "Generated row $rowNumber has Depth '$($record.Depth)', expected $($parts.Count)."
        }

        if ($parts[-1] -ne (Get-CleanText -Value $record.OUName)) {
            throw "Generated row $rowNumber has OUName '$($record.OUName)', expected '$($parts[-1])'."
        }

        $expectedParent = ''
        if ($parts.Count -gt 1) {
            $expectedParent = ($parts[0..($parts.Count - 2)] -join '/')
        }

        if ($expectedParent -ne (Get-CleanText -Value $record.ParentPath)) {
            throw "Generated row $rowNumber has ParentPath '$($record.ParentPath)', expected '$expectedParent'."
        }

        if (-not $seenPaths.Add($fullPath)) {
            $duplicatePaths.Add($fullPath)
        }
    }

    if ($duplicatePaths.Count -gt 0) {
        $duplicates = ($duplicatePaths | Sort-Object -Unique) -join ', '
        throw "Generated duplicate FullPath values: $duplicates"
    }

    $missingParents = @(
        $Records |
            ForEach-Object { Get-CleanText -Value $_.ParentPath } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $seenPaths.Contains($_) } |
            Sort-Object -Unique
    )

    if ($missingParents.Count -gt 0) {
        throw "Generated records have missing ParentPath values: $($missingParents -join ', ')"
    }
}

function Write-OuCsv {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Records,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $Records |
        Select-Object -Property $CsvColumns |
        Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
}

$resolvedInputCsv = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InputCsv)
if ([string]::IsNullOrWhiteSpace($OutputCsv)) {
    $resolvedOutputCsv = Get-DefaultOutputPath -SourceCsvPath $resolvedInputCsv
}
else {
    $resolvedOutputCsv = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputCsv)
}

$readResult = Read-SourcePaths -SourceCsvPath $resolvedInputCsv
$records = New-OuRecords -Domain $readResult.Domain -SourcePaths $readResult.SourcePaths
Test-OuRecords -Records $records
Write-OuCsv -Records $records -Path $resolvedOutputCsv

$explicitPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($sourcePath in $readResult.SourcePaths) {
    [void]$explicitPaths.Add($sourcePath.CorrectedPath)
}

$addedParentCount = @($records | Where-Object { -not $explicitPaths.Contains($_.FullPath) }).Count

Write-Host "Wrote $($records.Count) rows to $resolvedOutputCsv"
Write-Host "Domain: $($readResult.Domain)"
Write-Host "Explicit source OU rows: $($explicitPaths.Count)"
Write-Host "Added parent rows: $addedParentCount"
Write-Host 'Validation: OK'
