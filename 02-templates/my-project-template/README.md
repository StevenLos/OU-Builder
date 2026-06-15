# Project Template

Copy this folder into `03-projects` and rename it for the engagement, domain, or change window.

Recommended copy command from the package root:

```powershell
Copy-Item .\02-templates\my-project-template .\03-projects\my-ou-project -Recurse
```

Place the real OUTree source CSV in the copied project `input` folder. You can replace or rename the included `input/outree-layout-template.csv`.

Suggested workflow:

```powershell
.\Convert-OUTreeToOUCsv.ps1 `
  -InputCsv .\03-projects\my-ou-project\input\OUTree_ad-example-com-v1.csv `
  -OutputCsv .\03-projects\my-ou-project\output\ad-example-com-v1.csv

.\Create-ADOrganizationalUnits.ps1 `
  -CsvPath .\03-projects\my-ou-project\output\ad-example-com-v1.csv `
  -BaseDN "DC=ad,DC=example,DC=com" `
  -LogPath .\03-projects\my-ou-project\output\whatif-log.csv `
  -WhatIf
```

After review, rerun the PowerShell command without `-WhatIf`.
