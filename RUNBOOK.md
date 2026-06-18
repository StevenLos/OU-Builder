# OUBuilder Runbook

## Purpose

Use this runbook to document the current Active Directory OU state, convert an OUTree CSV into a reviewed OU creation CSV, create approved OUs, and compare pre-change and post-change AD state.

The project has two toolsets:

- `Invoke-ADOUSnapshot.ps1` captures and compares AD OU structure. It is read-only.
- `Convert-OUTreeToOUCsv.ps1` and `Create-ADOrganizationalUnits.ps1` convert source data and create OUs.

## Prerequisites

Run from PowerShell on a Windows admin workstation, management server, or domain controller.

Required for AD operations:

- Microsoft `ActiveDirectory` PowerShell module, usually from RSAT.
- Read access to capture OU snapshots.
- Delegated permission to create OUs when running the creation script.

Optional:

- Pester for running tests.

From the package root:

```powershell
cd C:\Path\To\OUBuilder
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Recommended Project Layout

Create a project folder from the template:

```powershell
Copy-Item .\02-templates\my-project-template .\03-projects\my-ou-project -Recurse
```

Place the source OUTree CSV in the project `input` folder:

```text
03-projects/
  my-ou-project/
    input/
      OUTree_ad-example-com-v1.csv
    output/
```

Use clear labels for audit captures:

```text
pre-change
post-change
ou-comparison
```

## Full Change Workflow

### 1. Capture Pre-Change OU State

Use the same `SearchBase` you want to verify after the change.

```powershell
.\Invoke-ADOUSnapshot.ps1 `
  -Mode Snapshot `
  -SearchBase "DC=ad,DC=example,DC=com" `
  -OutputRoot ".\03-projects\my-ou-project\output\AD-OU-Captures" `
  -Label "pre-change"
```

To pin the capture to a domain controller:

```powershell
.\Invoke-ADOUSnapshot.ps1 `
  -Mode Snapshot `
  -SearchBase "DC=ad,DC=example,DC=com" `
  -Server "dc01.ad.example.com" `
  -OutputRoot ".\03-projects\my-ou-project\output\AD-OU-Captures" `
  -Label "pre-change"
```

Review or save these files:

```text
ou-snapshot.html
ou-snapshot.csv
ou-tree.txt
```

### 2. Convert OUTree CSV

Convert the source CSV into the schema used by the AD creation script.

```powershell
.\Convert-OUTreeToOUCsv.ps1 `
  -InputCsv .\03-projects\my-ou-project\input\OUTree_ad-example-com-v1.csv `
  -OutputCsv .\03-projects\my-ou-project\output\ad-example-com-v1.csv
```

Successful output ends with:

```text
Validation: OK
```

Review the generated CSV before using it against AD.

## OUTree Source Rules

- `Depth0` must contain exactly one AD DNS domain value across the file.
- `Depth1` through `Depth9` represent nested OU levels.
- Missing `Depth2` through `Depth9` columns are treated as blank.
- A domain-only row is allowed and is skipped.
- Do not place a child OU after a blank parent depth column.

Example:

```text
Depth0          Depth1                       Depth2                   Depth3
ad.example.com  Administration and Security  Administration Accounts  ExampleCorp Administration Accounts
```

## Generated OU CSV

The converter writes:

```csv
Create,Depth0,Depth1,Depth2,Depth3,Depth4,Depth5,Depth6,Depth7,Depth8,Depth9,FullPath,Depth,OUName,ParentPath,Description,ProtectedFromAccidentalDeletion,Notes
```

`Create-ADOrganizationalUnits.ps1` uses `FullPath` as the source of truth. Parent rows are added automatically so parent OUs are processed before children.

### 3. Run AD Creation Dry Run

Always run `-WhatIf` first:

```powershell
.\Create-ADOrganizationalUnits.ps1 `
  -CsvPath .\03-projects\my-ou-project\output\ad-example-com-v1.csv `
  -BaseDN "DC=ad,DC=example,DC=com" `
  -LogPath .\03-projects\my-ou-project\output\whatif-log.csv `
  -WhatIf
```

Review `whatif-log.csv` and confirm:

- Expected OU paths are present.
- Unexpected OUs are not present.
- Parent OUs appear before child OUs.
- No validation failures are logged.
- `BaseDN` matches the target AD domain.

### 4. Create Approved OUs

After the dry run is approved, rerun without `-WhatIf`:

```powershell
.\Create-ADOrganizationalUnits.ps1 `
  -CsvPath .\03-projects\my-ou-project\output\ad-example-com-v1.csv `
  -BaseDN "DC=ad,DC=example,DC=com" `
  -LogPath .\03-projects\my-ou-project\output\create-log.csv
```

Optional parameters:

- `-Server` targets a specific domain controller.
- `-StopOnError` stops immediately on the first validation or creation error.

### 5. Capture Post-Change OU State

Use the same `SearchBase` as the pre-change snapshot. If you used `-Server` before, use the same server again.

```powershell
.\Invoke-ADOUSnapshot.ps1 `
  -Mode Snapshot `
  -SearchBase "DC=ad,DC=example,DC=com" `
  -OutputRoot ".\03-projects\my-ou-project\output\AD-OU-Captures" `
  -Label "post-change"
```

### 6. Compare Pre-Change and Post-Change Snapshots

```powershell
.\Invoke-ADOUSnapshot.ps1 `
  -Mode Compare `
  -PreSnapshot ".\03-projects\my-ou-project\output\AD-OU-Captures\pre-change\ou-snapshot.json" `
  -PostSnapshot ".\03-projects\my-ou-project\output\AD-OU-Captures\post-change\ou-snapshot.json" `
  -OutputRoot ".\03-projects\my-ou-project\output\AD-OU-Captures" `
  -Label "ou-comparison"
```

Review:

```text
comparison-report.html
comparison-review.xlsx
comparison-side-by-side.csv
comparison-summary.csv
added-ous.csv
removed-ous.csv
moved-or-renamed-ous.csv
attribute-changes.csv
```

## Comparison Meaning

Compare mode uses `ObjectGuid` as the stable identity key. `DistinguishedName` is treated as mutable state.

- Added OUs exist only in the post-change snapshot.
- Removed OUs exist only in the pre-change snapshot.
- Moved OUs have the same `ObjectGuid` and name but a different parent DN.
- Renamed OUs have the same `ObjectGuid` and parent DN but a different RDN or name.
- Moved-and-renamed OUs changed both parent DN and RDN or name.
- Attribute changes show old and new values for captured attributes.

Review table colors:

- Green: added OUs.
- Red: removed OUs.
- Yellow: moved or renamed OUs.
- Blue: attribute-only changes.

Snapshot and comparison files are ordered hierarchy-first, with sibling OUs sorted alphanumerically using natural numeric ordering, so `OU2` appears before `OU10`.

## Expected Output Folder

```text
03-projects/
  my-ou-project/
    input/
      OUTree_ad-example-com-v1.csv
    output/
      ad-example-com-v1.csv
      whatif-log.csv
      create-log.csv
      AD-OU-Captures/
        pre-change/
          ou-snapshot.json
          ou-snapshot.csv
          ou-tree.txt
          ou-snapshot.html
        post-change/
          ou-snapshot.json
          ou-snapshot.csv
          ou-tree.txt
          ou-snapshot.html
        ou-comparison/
          comparison-report.html
          comparison-review.xlsx
          comparison-side-by-side.csv
          comparison-summary.csv
          added-ous.csv
          removed-ous.csv
          moved-or-renamed-ous.csv
          attribute-changes.csv
```

## Tests

Run converter tests:

```powershell
Invoke-Pester .\04-tests
```

Run snapshot and comparison pure-function tests:

```powershell
Invoke-Pester .\tests
```

## Limitations

- Snapshot mode captures only OUs returned under the selected `SearchBase`.
- Removed OUs are shown in the side-by-side review and listed separately in `removed-ous.csv`.
- `whenChanged` can change for normal AD operational reasons. Review it with concrete fields like `Description`, `ManagedBy`, and `gPLink`.
- Snapshot consistency depends on replication. Use `-Server` for both snapshots when you need to capture from the same domain controller.
