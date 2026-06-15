# OUBuilder Runbook

## What This Does

This Windows PowerShell package takes an OUTree source CSV, converts it into an OU creation CSV, and then creates Active Directory Organizational Units from that CSV.

Use this workflow when a new OU tree is provided as tabular CSV data and needs to be converted into repeatable, reviewable AD changes.

## Folder Map

```text
Convert-OUTreeToOUCsv.ps1         Source CSV-to-OU CSV converter
Create-ADOrganizationalUnits.ps1  OU creation script
01-examples/                      Finished sample input and output
02-templates/                     Project and CSV templates
03-projects/                      Place real project files here
04-tests/                         Converter tests
```

## One-Time Setup

Open PowerShell from the package root:

```powershell
cd C:\Path\To\OUBuilder
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

The converter has no external module dependency. It uses built-in `Import-Csv` and `Export-Csv`.

Before creating OUs, run from a Windows machine that has the Microsoft `ActiveDirectory` PowerShell module available. That usually means a domain-joined management server, a domain controller, or a workstation with RSAT Active Directory tools installed.

## Input Source CSV Rules

Minimum required header:

```csv
Depth0
```

Rules:

- `Depth0` must contain exactly one domain value across the source CSV.
- `Depth1` through `Depth9` represent nested OUs and are optional when the source file does not need them.
- Missing `Depth2` through `Depth9` columns are treated as blank.
- A domain-only row is allowed and will be skipped.
- Do not place a child OU after a blank parent depth column.
- The converter supports up to nine OU levels below the domain.

Example:

```text
Depth0          Depth1                       Depth2                   Depth3                               Depth4 ... Depth9
ad.example.com  Administration and Security  Administration Accounts  ExampleCorp Administration Accounts
```

## Basic Workflow

Create a project folder:

```powershell
Copy-Item .\02-templates\my-project-template .\03-projects\my-ou-project -Recurse
```

Copy the OUTree source CSV into the project input folder:

```powershell
Copy-Item .\01-examples\input\OUTree_ad-example-com-v1.csv .\03-projects\my-ou-project\input\
```

Rename or replace the source CSV with the real project source CSV.

Recommended naming:

```text
OUTree_<domain-with-dashes>-v<number>.csv
```

Example:

```text
OUTree_ad-example-com-v1.csv
```

Convert the source CSV to a script-compatible OU creation CSV:

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

## What the Converter Creates

The converter writes these columns:

```csv
Create,Depth0,Depth1,Depth2,Depth3,Depth4,Depth5,Depth6,Depth7,Depth8,Depth9,FullPath,Depth,OUName,ParentPath,Description,ProtectedFromAccidentalDeletion,Notes
```

The converter:

- Skips the domain-only row.
- Joins `Depth1` through `Depth9` with `/` to create `FullPath`.
- Adds missing parent rows so parents can be created before children.
- Sets `Create=TRUE`.
- Sets `ProtectedFromAccidentalDeletion=TRUE`.
- Leaves `Description` blank unless the CSV is manually edited later.
- Fails if generated paths are duplicated or parent paths are missing.

## Dry Run Before AD Changes

Always run `-WhatIf` first:

```powershell
.\Create-ADOrganizationalUnits.ps1 `
  -CsvPath .\03-projects\my-ou-project\output\ad-example-com-v1.csv `
  -BaseDN "DC=ad,DC=example,DC=com" `
  -LogPath .\03-projects\my-ou-project\output\whatif-log.csv `
  -WhatIf
```

Review the `whatif-log.csv` file. Confirm:

- Expected OU paths are present.
- Unexpected OUs are not present.
- Parent OUs appear before dependent child OUs.
- No validation failures are logged.
- `BaseDN` matches the target AD domain.

## Create the OUs

After the dry run is approved, rerun without `-WhatIf`:

```powershell
.\Create-ADOrganizationalUnits.ps1 `
  -CsvPath .\03-projects\my-ou-project\output\ad-example-com-v1.csv `
  -BaseDN "DC=ad,DC=example,DC=com" `
  -LogPath .\03-projects\my-ou-project\output\create-log.csv
```

Optional parameters:

- `-Server` - target a specific domain controller.
- `-StopOnError` - stop immediately on the first validation or creation error.

## Output Files

Project output should stay in the project `output` folder:

```text
03-projects/
  my-ou-project/
    input/
      OUTree_ad-example-com-v1.csv
    output/
      ad-example-com-v1.csv
      whatif-log.csv
      create-log.csv
```

The generated OU CSV is the reviewed input to the AD script. The log CSV is the audit file for dry runs and creation runs.

## Example

See `01-examples/input/OUTree_ad-example-com-v1.csv` and `01-examples/output/ad-example-com-v1.csv` for a complete source-to-output CSV example.
