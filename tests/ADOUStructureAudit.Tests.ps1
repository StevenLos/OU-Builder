Describe 'ADOUStructureAudit pure functions' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/ADOUStructureAudit.psm1'
        Import-Module -Name $modulePath -Force

        function New-TestOu {
            param(
                [Parameter(Mandatory = $true)]
                [string]$ObjectGuid,

                [Parameter(Mandatory = $true)]
                [string]$DistinguishedName,

                [Parameter(Mandatory = $false)]
                [string]$Description = '',

                [Parameter(Mandatory = $false)]
                [string]$ManagedBy = '',

                [Parameter(Mandatory = $false)]
                [bool]$ProtectedFromAccidentalDeletion = $true,

                [Parameter(Mandatory = $false)]
                [string]$gPLink = '',

                [Parameter(Mandatory = $false)]
                [string]$gPOptions = '',

                [Parameter(Mandatory = $false)]
                [string]$whenCreated = '2026-01-01T00:00:00.0000000Z',

                [Parameter(Mandatory = $false)]
                [string]$whenChanged = '2026-01-01T00:00:00.0000000Z'
            )

            $rdnValue = Get-ADRdnValue -DistinguishedName $DistinguishedName
            $ouParts = @(
                Split-ADDistinguishedName -DistinguishedName $DistinguishedName |
                    Where-Object { $_.TrimStart().StartsWith('OU=', [System.StringComparison]::OrdinalIgnoreCase) } |
                    ForEach-Object {
                        $separatorIndex = $_.IndexOf('=')
                        if ($separatorIndex -ge 0 -and $separatorIndex -lt ($_.Length - 1)) {
                            $_.Substring($separatorIndex + 1).Replace('\,', ',')
                        }
                        else {
                            $_
                        }
                    }
            )
            [array]::Reverse($ouParts)
            $canonicalPath = if ($ouParts.Count -gt 0) { 'corp.contoso.com/' + ($ouParts -join '/') } else { 'corp.contoso.com' }

            [pscustomobject][ordered]@{
                ObjectGuid                      = ([guid]$ObjectGuid).ToString('D').ToLowerInvariant()
                Name                            = $rdnValue
                RdnValue                        = $rdnValue
                DistinguishedName               = $DistinguishedName
                ParentDistinguishedName         = Get-ADParentDistinguishedName -DistinguishedName $DistinguishedName
                CanonicalName                   = $canonicalPath
                Depth                           = Get-ADDistinguishedNameDepth -DistinguishedName $DistinguishedName -BaseDistinguishedName 'DC=corp,DC=contoso,DC=com'
                Description                     = $Description
                ManagedBy                       = $ManagedBy
                ProtectedFromAccidentalDeletion = $ProtectedFromAccidentalDeletion
                gPLink                          = $gPLink
                gPOptions                       = $gPOptions
                whenCreated                     = $whenCreated
                whenChanged                     = $whenChanged
            }
        }
    }

    It 'splits distinguished names without breaking on escaped commas' {
        $dn = 'OU=Child\, East,OU=Parent,DC=corp,DC=contoso,DC=com'

        $parts = @(Split-ADDistinguishedName -DistinguishedName $dn)

        $parts.Count | Should -Be 5
        $parts[0] | Should -Be 'OU=Child\, East'
        $parts[1] | Should -Be 'OU=Parent'
    }

    It 'parses parent DN and RDN values with escaped characters' {
        $dn = 'OU=Child\, East,OU=Parent,DC=corp,DC=contoso,DC=com'

        Get-ADParentDistinguishedName -DistinguishedName $dn |
            Should -Be 'OU=Parent,DC=corp,DC=contoso,DC=com'

        Get-ADRdnValue -DistinguishedName $dn |
            Should -Be 'Child, East'
    }

    It 'calculates absolute OU depth and relative SearchBase depth' {
        $dn = 'OU=Child,OU=Parent,DC=corp,DC=contoso,DC=com'

        Get-ADDistinguishedNameDepth -DistinguishedName $dn |
            Should -Be 2

        Get-ADDistinguishedNameDepth -DistinguishedName $dn -BaseDistinguishedName 'OU=Parent,DC=corp,DC=contoso,DC=com' |
            Should -Be 1

        Get-ADDistinguishedNameDepth -DistinguishedName 'OU=Parent,DC=corp,DC=contoso,DC=com' -BaseDistinguishedName 'OU=Parent,DC=corp,DC=contoso,DC=com' |
            Should -Be 0
    }

    It 'classifies added, removed, moved, renamed, moved-and-renamed, and attribute-only changes' {
        $pre = @(
            New-TestOu -ObjectGuid 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -DistinguishedName 'OU=Unchanged,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -DistinguishedName 'OU=Removed,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid 'cccccccc-cccc-cccc-cccc-cccccccccccc' -DistinguishedName 'OU=Moved,OU=OldParent,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid 'dddddddd-dddd-dddd-dddd-dddddddddddd' -DistinguishedName 'OU=OldName,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' -DistinguishedName 'OU=OldBoth,OU=OldParent,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid 'ffffffff-ffff-ffff-ffff-ffffffffffff' -DistinguishedName 'OU=AttributeOnly,DC=corp,DC=contoso,DC=com' -Description 'before'
        )

        $post = @(
            New-TestOu -ObjectGuid 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -DistinguishedName 'OU=Unchanged,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid 'cccccccc-cccc-cccc-cccc-cccccccccccc' -DistinguishedName 'OU=Moved,OU=NewParent,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid 'dddddddd-dddd-dddd-dddd-dddddddddddd' -DistinguishedName 'OU=NewName,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee' -DistinguishedName 'OU=NewBoth,OU=NewParent,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid 'ffffffff-ffff-ffff-ffff-ffffffffffff' -DistinguishedName 'OU=AttributeOnly,DC=corp,DC=contoso,DC=com' -Description 'after'
            New-TestOu -ObjectGuid '99999999-9999-9999-9999-999999999999' -DistinguishedName 'OU=Added,DC=corp,DC=contoso,DC=com'
        )

        $comparison = Compare-ADOUSnapshotObjects -PreOUs $pre -PostOUs $post -Label 'test'
        $summary = @{}
        foreach ($row in $comparison.Summary) {
            $summary[$row.Metric] = [int]$row.Count
        }

        $summary['AddedOUs'] | Should -Be 1
        $summary['RemovedOUs'] | Should -Be 1
        $summary['MovedOUs'] | Should -Be 1
        $summary['RenamedOUs'] | Should -Be 1
        $summary['MovedAndRenamedOUs'] | Should -Be 1
        $summary['AttributeChangedOUs'] | Should -Be 1
        $summary['AttributeOnlyChangedOUs'] | Should -Be 1
        $summary['AttributeChangeRows'] | Should -Be 1

        $comparison.Added.ObjectGuid | Should -Be '99999999-9999-9999-9999-999999999999'
        $comparison.Removed.ObjectGuid | Should -Be 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        @($comparison.MovedOrRenamed | Where-Object { $_.ChangeType -eq 'Moved' }).Count | Should -Be 1
        @($comparison.MovedOrRenamed | Where-Object { $_.ChangeType -eq 'Renamed' }).Count | Should -Be 1
        @($comparison.MovedOrRenamed | Where-Object { $_.ChangeType -eq 'MovedAndRenamed' }).Count | Should -Be 1

        $comparison.AttributeChanges[0].AttributeName | Should -Be 'Description'
        $comparison.AttributeChanges[0].OldValue | Should -Be 'before'
        $comparison.AttributeChanges[0].NewValue | Should -Be 'after'

        $comparison.HighlightByGuid['99999999-9999-9999-9999-999999999999'] | Should -Be 'Added'
        $comparison.HighlightByGuid['cccccccc-cccc-cccc-cccc-cccccccccccc'] | Should -Be 'MovedOrRenamed'
        $comparison.HighlightByGuid['ffffffff-ffff-ffff-ffff-ffffffffffff'] | Should -Be 'AttributeOnly'
    }

    It 'writes side-by-side CSV and XLSX review outputs' {
        $workDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
        New-Item -Path $workDir -ItemType Directory -Force | Out-Null

        try {
            $preSnapshotPath = Join-Path -Path $workDir -ChildPath 'pre.json'
            $postSnapshotPath = Join-Path -Path $workDir -ChildPath 'post.json'

            $pre = [pscustomobject][ordered]@{
                SchemaVersion = 1
                OUs = @(
                    New-TestOu -ObjectGuid '11111111-1111-1111-1111-111111111111' -DistinguishedName 'OU=Existing,DC=corp,DC=contoso,DC=com'
                )
            }

            $post = [pscustomobject][ordered]@{
                SchemaVersion = 1
                OUs = @(
                    New-TestOu -ObjectGuid '11111111-1111-1111-1111-111111111111' -DistinguishedName 'OU=Existing,DC=corp,DC=contoso,DC=com'
                    New-TestOu -ObjectGuid '22222222-2222-2222-2222-222222222222' -DistinguishedName 'OU=Added,DC=corp,DC=contoso,DC=com'
                )
            }

            $pre | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $preSnapshotPath -Encoding UTF8
            $post | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $postSnapshotPath -Encoding UTF8

            $result = Compare-ADOUStructureSnapshots `
                -PreSnapshot $preSnapshotPath `
                -PostSnapshot $postSnapshotPath `
                -OutputRoot $workDir `
                -Label 'comparison'

            Test-Path -LiteralPath $result.SideBySidePath | Should -BeTrue
            Test-Path -LiteralPath $result.WorkbookPath | Should -BeTrue

            $sideBySide = @(Import-Csv -LiteralPath $result.SideBySidePath)
            $sideBySide.Count | Should -Be 2
            @($sideBySide | Where-Object { $_.ChangeType -eq 'Added' }).Count | Should -Be 1
            @($sideBySide | Where-Object { $_.ChangeType -eq 'Unchanged' }).Count | Should -Be 1

            [System.IO.Path]::GetExtension($result.WorkbookPath) | Should -Be '.xlsx'

            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $archive = [System.IO.Compression.ZipFile]::OpenRead($result.WorkbookPath)
            try {
                $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
                $entryNames | Should -Contain 'xl/workbook.xml'
                $entryNames | Should -Contain 'xl/worksheets/sheet1.xml'
                $entryNames | Should -Contain 'xl/worksheets/sheet2.xml'

                $workbookEntry = $archive.GetEntry('xl/workbook.xml')
                $reader = [System.IO.StreamReader]::new($workbookEntry.Open())
                try {
                    $workbookXml = $reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                }

                $workbookXml | Should -Match 'SideBySideReview'
                $workbookXml | Should -Match 'AttributeChanges'
            }
            finally {
                $archive.Dispose()
            }
        }
        finally {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'orders side-by-side review rows by AD-like natural hierarchy position' {
        $post = @(
            New-TestOu -ObjectGuid '00000000-0000-0000-0000-000000000005' -DistinguishedName 'OU=Zeta,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid '00000000-0000-0000-0000-000000000004' -DistinguishedName 'OU=Child10,OU=Parent,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid '00000000-0000-0000-0000-000000000003' -DistinguishedName 'OU=Child2,OU=Parent,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid '00000000-0000-0000-0000-000000000002' -DistinguishedName 'OU=Parent,DC=corp,DC=contoso,DC=com'
            New-TestOu -ObjectGuid '00000000-0000-0000-0000-000000000001' -DistinguishedName 'OU=Alpha,DC=corp,DC=contoso,DC=com'
        )

        $comparison = Compare-ADOUSnapshotObjects -PreOUs @() -PostOUs $post -Label 'ordering'

        $comparison.SideBySide.PostRdnValue | Should -Be @('Alpha', 'Parent', 'Child2', 'Child10', 'Zeta')
    }
}
