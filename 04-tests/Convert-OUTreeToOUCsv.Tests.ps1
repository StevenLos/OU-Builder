Describe 'Convert-OUTreeToOUCsv.ps1' {
    BeforeAll {
        $repoRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:ConverterPath = (Get-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'Convert-OUTreeToOUCsv.ps1')).FullName

        function New-TestSourceRow {
            param(
                [Parameter(Mandatory = $false)]
                [string]$Domain = 'ad.example.com',

                [Parameter(Mandatory = $false)]
                [string[]]$OuParts = @()
            )

            $row = [ordered]@{
                Depth0 = $Domain
            }

            foreach ($index in 1..9) {
                $row["Depth$index"] = if ($index -le $OuParts.Count) { $OuParts[$index - 1] } else { $null }
            }

            [pscustomobject]$row
        }
    }

    It 'expands missing parent rows and validates generated output' {
        $workDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
        New-Item -Path $workDir -ItemType Directory -Force | Out-Null

        try {
            $sourceCsvPath = Join-Path -Path $workDir -ChildPath 'OUTree_ad-example-com-v1.csv'
            $outputCsvPath = Join-Path -Path $workDir -ChildPath 'ad-example-com-v1.csv'

            @(
                New-TestSourceRow
                New-TestSourceRow -OuParts @('Parent', 'Child', 'Leaf')
                New-TestSourceRow -OuParts @('Workstations')
            ) | Export-Csv -LiteralPath $sourceCsvPath -NoTypeInformation

            & $script:ConverterPath -InputCsv $sourceCsvPath -OutputCsv $outputCsvPath
            $records = @(Import-Csv -LiteralPath $outputCsvPath)

            $records.FullPath | Should -Be @('Parent', 'Parent/Child', 'Parent/Child/Leaf', 'Workstations')
            $records[0].PSObject.Properties.Name | Should -Contain 'Depth9'
            $records[0].Notes | Should -Be 'Added explicit parent row for script-safe creation order'
            $records[1].Notes | Should -Be 'Added explicit parent row for script-safe creation order'
            $records[2].OUName | Should -Be 'Leaf'
            $records[2].ParentPath | Should -Be 'Parent/Child'
        }
        finally {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'applies known spelling corrections' {
        $workDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
        New-Item -Path $workDir -ItemType Directory -Force | Out-Null

        try {
            $sourceCsvPath = Join-Path -Path $workDir -ChildPath 'OUTree_ad-example-com-v1.csv'
            $outputCsvPath = Join-Path -Path $workDir -ChildPath 'ad-example-com-v1.csv'

            @(
                New-TestSourceRow -OuParts @('Landing Zone (Non Syncying)', 'Example')
            ) | Export-Csv -LiteralPath $sourceCsvPath -NoTypeInformation

            & $script:ConverterPath -InputCsv $sourceCsvPath -OutputCsv $outputCsvPath
            $records = @(Import-Csv -LiteralPath $outputCsvPath)

            $records[0].FullPath | Should -Be 'Landing Zone (Non Syncing)'
            $records[1].FullPath | Should -Be 'Landing Zone (Non Syncing)/Example'
            $records[0].Notes | Should -Match 'Corrected spelling from Non Syncying to Non Syncing'
        }
        finally {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'supports nine OU levels below the domain' {
        $workDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
        New-Item -Path $workDir -ItemType Directory -Force | Out-Null

        try {
            $sourceCsvPath = Join-Path -Path $workDir -ChildPath 'OUTree_ad-example-com-v1.csv'
            $outputCsvPath = Join-Path -Path $workDir -ChildPath 'ad-example-com-v1.csv'
            $parts = @(1..9 | ForEach-Object { "Level$_" })

            @(
                New-TestSourceRow -OuParts $parts
            ) | Export-Csv -LiteralPath $sourceCsvPath -NoTypeInformation

            & $script:ConverterPath -InputCsv $sourceCsvPath -OutputCsv $outputCsvPath
            $records = @(Import-Csv -LiteralPath $outputCsvPath)
            $expectedPaths = @(1..9 | ForEach-Object { ($parts[0..($_ - 1)] -join '/') })

            $records.FullPath | Should -Be $expectedPaths
            $records[-1].Depth | Should -Be '9'
            $records[-1].Depth9 | Should -Be 'Level9'
            $records[-1].OUName | Should -Be 'Level9'
            $records[-1].ParentPath | Should -Be ($parts[0..7] -join '/')
        }
        finally {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'treats missing Depth2 through Depth9 columns as optional blanks' {
        $workDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
        New-Item -Path $workDir -ItemType Directory -Force | Out-Null

        try {
            $sourceCsvPath = Join-Path -Path $workDir -ChildPath 'OUTree_ad-example-com-v1.csv'
            $outputCsvPath = Join-Path -Path $workDir -ChildPath 'ad-example-com-v1.csv'

            @(
                [pscustomobject]@{ Depth0 = 'ad.example.com'; Depth1 = $null }
                [pscustomobject]@{ Depth0 = 'ad.example.com'; Depth1 = 'Workstations' }
                [pscustomobject]@{ Depth0 = 'ad.example.com'; Depth1 = 'Servers' }
            ) | Export-Csv -LiteralPath $sourceCsvPath -NoTypeInformation

            & $script:ConverterPath -InputCsv $sourceCsvPath -OutputCsv $outputCsvPath
            $records = @(Import-Csv -LiteralPath $outputCsvPath)

            $records.FullPath | Should -Be @('Workstations', 'Servers')
            $records[0].PSObject.Properties.Name | Should -Contain 'Depth9'
            $records[0].Depth2 | Should -Be ''
            $records[1].Depth9 | Should -Be ''
        }
        finally {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects source columns deeper than Depth9' {
        $workDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.Guid]::NewGuid().ToString())
        New-Item -Path $workDir -ItemType Directory -Force | Out-Null

        try {
            $sourceCsvPath = Join-Path -Path $workDir -ChildPath 'OUTree_ad-example-com-v1.csv'
            $outputCsvPath = Join-Path -Path $workDir -ChildPath 'ad-example-com-v1.csv'
            $header = @(0..10 | ForEach-Object { "Depth$_" }) -join ','
            $values = @('ad.example.com') + @(1..10 | ForEach-Object { "Level$_" })

            Set-Content -LiteralPath $sourceCsvPath -Value @($header, ($values -join ',')) -Encoding UTF8

            { & $script:ConverterPath -InputCsv $sourceCsvPath -OutputCsv $outputCsvPath } |
                Should -Throw '*Depth10*'
        }
        finally {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
