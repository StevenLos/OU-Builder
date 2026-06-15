# OUBuilder Package

This Windows PowerShell package converts an OUTree source CSV into a script-compatible OU creation CSV, then uses that CSV to create Active Directory Organizational Units.

## Scope

The package supports:

- OUTree source CSV input with optional OU nesting columns through `Depth9`.
- CSV generation for `Create-ADOrganizationalUnits.ps1`.
- Parent-row expansion so parent OUs are created before child OUs.
- CSV validation before output is written.
- Safe AD execution with `-WhatIf` and audit logging.

The converter builds the CSV. The PowerShell script creates the OUs. Keep those two steps separate so generated input can be reviewed before any AD change is attempted.

This package is intended for Windows PowerShell or PowerShell 7 on Windows. The conversion step uses built-in PowerShell CSV commands. OU creation uses the Microsoft `ActiveDirectory` module.

## Files

- `Convert-OUTreeToOUCsv.ps1` - converts `OUTree_*.csv` source files into OU creation CSV files.
- `Create-ADOrganizationalUnits.ps1` - creates OUs from the generated CSV.
- `RUNBOOK.md` - end-user operating instructions.
- `01-examples/` - finished sample input and output files.
- `02-templates/` - starter project folder and CSV templates.
- `03-projects/` - suggested location for real user projects.
- `04-tests/` - lightweight converter tests.

## OUTree Source CSV Columns

Minimum source CSV columns:

```csv
Depth0
```

`Depth0` is the AD DNS domain. `Depth1` through `Depth9` are supported OU levels. Add only the OU depth columns the source file needs; missing `Depth2` through `Depth9` columns are treated as blank.

Do not leave a blank parent depth before a child depth value. For example, do not provide `Depth3` values without populated `Depth1` and `Depth2` values on that row.

## Output CSV Columns

Generated CSV columns:

```csv
Create,Depth0,Depth1,Depth2,Depth3,Depth4,Depth5,Depth6,Depth7,Depth8,Depth9,FullPath,Depth,OUName,ParentPath,Description,ProtectedFromAccidentalDeletion,Notes
```

`Create-ADOrganizationalUnits.ps1` uses `FullPath` as the source of truth, with `OUName`, `ParentPath`, `Description`, and `ProtectedFromAccidentalDeletion` used during creation.

## Examples

Convert the included example source CSV:

```powershell
.\Convert-OUTreeToOUCsv.ps1 `
  -InputCsv .\01-examples\input\OUTree_ad-example-com-v1.csv `
  -OutputCsv .\01-examples\output\ad-example-com-v1.csv
```

Dry-run OU creation from the generated CSV:

```powershell
.\Create-ADOrganizationalUnits.ps1 `
  -CsvPath .\01-examples\output\ad-example-com-v1.csv `
  -BaseDN "DC=ad,DC=example,DC=com" `
  -WhatIf
```

## Tests

Run the converter tests from the package root:

```powershell
Invoke-Pester .\04-tests
```

Pester is required only if you want to run the tests.

## Operating Instructions

Use `RUNBOOK.md` for the full process.
