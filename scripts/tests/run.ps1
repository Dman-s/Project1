$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$testsPath = Join-Path $PSScriptRoot "ProjectEnvironment.Tests.ps1"

try {
    . $testsPath
    $summary = Invoke-ProjectEnvironmentTests
} catch {
    Write-Host "FAIL Suite initialization"
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "Passed: 0"
    Write-Host "Failed: 1"
    exit 1
}

foreach ($result in $summary.Results) {
    if ($result.Passed) {
        Write-Host "PASS $($result.Name)"
    } else {
        Write-Host "FAIL $($result.Name)"
        Write-Host "  $($result.Error)"
    }
}

Write-Host ""
Write-Host "Passed: $($summary.Passed)"
Write-Host "Failed: $($summary.Failed)"

if ($summary.Failed -gt 0) {
    exit 1
}

exit 0
