# OUBuilder Package

This Windows PowerShell package converts an OUTree source CSV into a script-compatible OU creation CSV, then uses that CSV to create Active Directory Organizational Units.

## Scope

The package supports:

- OUTree source CSV input with optional OU nesting columns through `Depth9`.
- CSV generation for `Create-ADOrganizationalUnits.ps1`.
- Parent-row expansion so parent OUs are created before child OUs.
- CSV validation before output is written.
- Safe AD execution with `-WhatIf` and audit logging.
- Read-only Active Directory OU structure snapshots and before/after comparisons.

The converter builds the CSV. The PowerShell script creates the OUs. Keep those two steps separate so generated input can be reviewed before any AD change is attempted.

This package is intended for Windows PowerShell or PowerShell 7 on Windows. The conversion step uses built-in PowerShell CSV commands. OU creation uses the Microsoft `ActiveDirectory` module.

## Files

- `Convert-OUTreeToOUCsv.ps1` - converts `OUTree_*.csv` source files into OU creation CSV files.
- `Create-ADOrganizationalUnits.ps1` - creates OUs from the generated CSV.
- `Invoke-ADOUSnapshot.ps1` - captures and compares AD OU structure without making changes.
- `src/ADOUStructureAudit.psm1` - reusable functions used by the snapshot and comparison script.
- `RUNBOOK.md` - end-user operating instructions.
- `01-examples/` - finished sample input and output files.
- `02-templates/` - starter project folder and CSV templates.
- `03-projects/` - suggested location for real user projects.
- `04-tests/` - lightweight converter tests.
- `tests/` - non-AD-dependent tests for the OU snapshot and comparison tool.

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

Run the AD OU structure audit pure-function tests:

```powershell
Invoke-Pester .\tests
```

Pester is required only if you want to run the tests.

## AD OU Structure Audit Tool

`Invoke-ADOUSnapshot.ps1` documents Active Directory OU structure before and after a planned change. It is read-only: it uses `Get-ADOrganizationalUnit` in Snapshot mode and never calls AD write cmdlets.

Use this tool when you need a static pre-change capture, a static post-change capture, and reviewer-friendly comparison reports showing added, removed, moved, renamed, moved-and-renamed, and modified OUs.

### Prerequisites

- Windows PowerShell or PowerShell 7 on Windows.
- Microsoft `ActiveDirectory` PowerShell module for Snapshot mode. This is normally available through RSAT Active Directory tools or on domain management hosts.
- Read permission to the target OU hierarchy.
- Pester is required only for tests.

Compare mode reads snapshot JSON files and does not require Active Directory connectivity.

### Snapshot

Capture all OUs under a domain naming context:

```powershell
.\Invoke-ADOUSnapshot.ps1 `
  -Mode Snapshot `
  -SearchBase "DC=corp,DC=contoso,DC=com" `
  -OutputRoot ".\AD-OU-Captures" `
  -Label "pre-change"
```

Capture with a specific domain controller:

```powershell
.\Invoke-ADOUSnapshot.ps1 `
  -Mode Snapshot `
  -SearchBase "OU=Corporate,DC=corp,DC=contoso,DC=com" `
  -Server "dc01.corp.contoso.com" `
  -OutputRoot ".\AD-OU-Captures" `
  -Label "post-change"
```

Snapshot output folder:

```text
AD-OU-Captures/
  pre-change/
    ou-snapshot.json
    ou-snapshot.csv
    ou-tree.txt
    ou-snapshot.html
```

Captured OU fields:

```text
ObjectGuid
Name
RdnValue
DistinguishedName
ParentDistinguishedName
CanonicalName
Depth
Description
ManagedBy
ProtectedFromAccidentalDeletion
gPLink
gPOptions
whenCreated
whenChanged
```

### Compare

Compare pre-change and post-change snapshots:

```powershell
.\Invoke-ADOUSnapshot.ps1 `
  -Mode Compare `
  -PreSnapshot ".\AD-OU-Captures\pre-change\ou-snapshot.json" `
  -PostSnapshot ".\AD-OU-Captures\post-change\ou-snapshot.json" `
  -OutputRoot ".\AD-OU-Captures" `
  -Label "ou-comparison"
```

Compare output folder:

```text
AD-OU-Captures/
  ou-comparison/
    comparison-summary.csv
    added-ous.csv
    removed-ous.csv
    moved-or-renamed-ous.csv
    attribute-changes.csv
    comparison-side-by-side.csv
    comparison-report.html
    comparison-review.xlsx
```

Comparison behavior:

- `ObjectGuid` is the stable identity key.
- `DistinguishedName`, parent DN, RDN, name, and canonical name are treated as mutable state.
- Added OUs exist only in the post-change snapshot.
- Removed OUs exist only in the pre-change snapshot.
- Moved OUs keep the same `ObjectGuid` and RDN/name but have a different parent DN.
- Renamed OUs keep the same `ObjectGuid` and parent DN but have a different RDN/name.
- Moved-and-renamed OUs changed both parent DN and RDN/name.
- Attribute changes compare `Description`, `ManagedBy`, `ProtectedFromAccidentalDeletion`, `gPLink`, `gPOptions`, `whenCreated`, and `whenChanged`.

The side-by-side review and Excel-openable report use these colors:

- Added OUs: green.
- Removed OUs: red.
- Moved or renamed OUs: yellow.
- Attribute-only changes: blue.

Snapshot and comparison files are ordered hierarchy-first, with sibling OUs sorted alphanumerically using natural numeric ordering, so `OU2` appears before `OU10`.

### Sample Change Workflow

1. Run a pre-change snapshot and store the generated folder with the change record.
2. Make OU changes manually or with your approved external process.
3. Run a post-change snapshot against the same `SearchBase`.
4. Run Compare mode using the two `ou-snapshot.json` files.
5. Review `comparison-review.xlsx`, `comparison-side-by-side.csv`, `comparison-report.html`, `comparison-summary.csv`, and the detailed CSV files before closing the change.

### Limitations

- The tool only captures OU objects returned by `Get-ADOrganizationalUnit` under the selected `SearchBase`.
- Objects outside the captured scope are shown as external/root parent entries in text tree outputs.
- Removed OUs are shown in the side-by-side review and listed separately in `removed-ous.csv`.
- `whenChanged` is useful for verification but can change for AD operational reasons. Review it alongside concrete attribute rows such as `Description`, `ManagedBy`, and `gPLink`.
- Snapshot consistency depends on replication and the selected domain controller. Use `-Server` for both snapshots when you need to pin captures to the same DC.

## Operating Instructions

Use `RUNBOOK.md` for the full process.
