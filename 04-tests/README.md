# Tests

This folder contains lightweight Pester tests for the OUTree converter.

Run from the package root:

```powershell
Invoke-Pester .\04-tests
```

Pester is required to run the tests.

The tests create temporary source CSVs and verify parent-row expansion, spelling correction, optional missing depth columns, depth-9 support, depth-10 rejection, and generated CSV validation.
