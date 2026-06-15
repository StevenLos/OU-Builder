# Examples

This folder contains a completed OUTree source CSV example and generated OU creation CSV output.

Input:

- `input/OUTree_ad-example-com-v1.csv`

Output:

- `output/ad-example-com-v1.csv`

Convert the included example from the package root:

```powershell
.\Convert-OUTreeToOUCsv.ps1 `
  -InputCsv .\01-examples\input\OUTree_ad-example-com-v1.csv `
  -OutputCsv .\01-examples\output\ad-example-com-v1.csv
```

Then run a WhatIf pass:

```powershell
.\Create-ADOrganizationalUnits.ps1 `
  -CsvPath .\01-examples\output\ad-example-com-v1.csv `
  -BaseDN "DC=ad,DC=example,DC=com" `
  -LogPath .\01-examples\output\example-whatif-log.csv `
  -WhatIf
```

Copy this example into `03-projects`, replace the source CSV with the real project source CSV, then convert and run from the project folder paths.
