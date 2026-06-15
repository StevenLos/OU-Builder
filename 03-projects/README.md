# Projects

Place real user project files under this folder.

Recommended structure:

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

Start by copying `02-templates/my-project-template` into this folder, then place the real OUTree source CSV in the project `input` folder.

Keep generated CSVs and AD script logs in the project `output` folder so each project stays self-contained.

Real project folders are intentionally ignored by `.gitignore` because they can contain customer or environment-specific data. Commit this README, but do not commit project subfolders.
