Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command Assert-True -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "ProjectEnvironment.Tests.ps1")
}

if (-not (Get-Command Invoke-CheckedCommand -ErrorAction SilentlyContinue)) {
    Import-Module (Join-Path $PSScriptRoot "..\lib\ProjectEnvironment.psm1") -Force
}

function Get-BootstrapScriptPath {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\bootstrap-windows.ps1"))
}

function Get-DoctorScriptPath {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\doctor.ps1"))
}

function Get-StartScriptPath {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\start.ps1"))
}

function Get-StopScriptPath {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\stop.ps1"))
}

function New-BootstrapFixture {
    $root = New-TempFixture

    foreach ($relativePath in @(
        "backend",
        "frontend",
        "scripts",
        "scripts\config"
    )) {
        New-Item -ItemType Directory -Path (Join-Path $root $relativePath) | Out-Null
    }

    foreach ($requirementsFile in @(
        "requirements.txt",
        "requirements-core.txt",
        "requirements-cpu.txt",
        "requirements-gpu.txt"
    )) {
        Set-Content -LiteralPath (Join-Path $root "backend\$requirementsFile") -Value "# test fixture" -Encoding ASCII
    }

    Set-Content -LiteralPath (Join-Path $root "frontend\package-lock.json") -Value "{}" -Encoding ASCII
    (New-ValidBootstrapManifestObject | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $root "scripts\config\bootstrap-manifest.json") -Encoding ASCII

    return $root
}

function Get-FixtureMutationTargets {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    return @(
        (Join-Path $ProjectRoot ".runtime"),
        (Join-Path $ProjectRoot "models"),
        (Join-Path $ProjectRoot "backend\.env"),
        (Join-Path $ProjectRoot "backend\.venv"),
        (Join-Path $ProjectRoot "backend\logs"),
        (Join-Path $ProjectRoot "frontend\node_modules")
    )
}

function Assert-NoPlanOnlyMutations {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    foreach ($path in (Get-FixtureMutationTargets -ProjectRoot $ProjectRoot)) {
        Assert-False -Condition (Test-Path -LiteralPath $path) -Message "PlanOnly mutated fixture path '$path'."
    }
}

function Assert-NoBootstrapMutations {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    foreach ($path in (Get-FixtureMutationTargets -ProjectRoot $ProjectRoot)) {
        Assert-False -Condition (Test-Path -LiteralPath $path) -Message "Bootstrap mutated fixture path '$path'."
    }
}

function ConvertTo-CanonicalJson {
    param([Parameter(Mandatory = $true)]$Object)

    return ($Object | ConvertTo-Json -Depth 10 -Compress)
}

function Invoke-BootstrapScriptProcess {
    param(
        [string[]]$ArgumentList = @(),
        [string]$ProjectRoot
    )

    $bootstrapScriptPath = Get-BootstrapScriptPath
    $powershellPath = Join-Path $PSHOME "powershell.exe"
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershellPath

    $allArguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $bootstrapScriptPath
    )

    if ($ProjectRoot) {
        $allArguments += @("-ProjectRoot", $ProjectRoot)
    }

    if ($ArgumentList) {
        $allArguments += $ArgumentList
    }

    $quotedArguments = foreach ($argument in $allArguments) {
        if ($argument -notmatch '[\s"]') {
            $argument
            continue
        }

        '"' + $argument.Replace('"', '\"') + '"'
    }

    $startInfo.Arguments = $quotedArguments -join " "
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $stdoutTask.GetAwaiter().GetResult()
            StdErr = $stderrTask.GetAwaiter().GetResult()
        }
    } finally {
        $process.Dispose()
    }
}

function Invoke-DoctorScriptProcess {
    param(
        [string[]]$ArgumentList = @(),
        [string]$ProjectRoot
    )

    $doctorScriptPath = Get-DoctorScriptPath
    $powershellPath = Join-Path $PSHOME "powershell.exe"
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershellPath

    $allArguments = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $doctorScriptPath
    )

    if ($ProjectRoot) {
        $allArguments += @("-ProjectRoot", $ProjectRoot)
    }

    if ($ArgumentList) {
        $allArguments += $ArgumentList
    }

    $quotedArguments = foreach ($argument in $allArguments) {
        if ($argument -notmatch '[\s"]') {
            $argument
            continue
        }

        '"' + $argument.Replace('"', '\"') + '"'
    }

    $startInfo.Arguments = $quotedArguments -join " "
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut = $stdoutTask.GetAwaiter().GetResult()
            StdErr = $stderrTask.GetAwaiter().GetResult()
        }
    } finally {
        $process.Dispose()
    }
}

function New-NodeRuntimeArchive {
    param(
        [Parameter(Mandatory = $true)][string]$FixtureRoot,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$NodeContent,
        [string]$ArchiveName = "node-runtime.zip"
    )

    $archiveRoot = Join-Path $FixtureRoot ([System.Guid]::NewGuid().ToString("N"))
    $versionRoot = Join-Path $archiveRoot "node-v$Version-win-x64"
    New-Item -ItemType Directory -Path $versionRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $versionRoot "node.exe") -Value $NodeContent -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $versionRoot "npm.cmd") -Value "@echo npm" -Encoding ASCII
    $archivePath = Join-Path $FixtureRoot $ArchiveName
    Compress-Archive -Path (Join-Path $archiveRoot "*") -DestinationPath $archivePath -Force
    Remove-TempFixture -Path $archiveRoot
    return $archivePath
}

function Assert-TestRequiresJunction {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Expected test junction path '$Path' to exist."
    }
}

function Invoke-BootstrapChildScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptContent,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $fixture = New-TempFixture
    $scriptPath = Join-Path $fixture "child.ps1"
    try {
        $modulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\lib\ProjectEnvironment.psm1")).Replace("'", "''")
        $prefixedContent = @"
Import-Module '$modulePath' -Force
$ScriptContent
"@
        $prefixedContent | Set-Content -LiteralPath $scriptPath -Encoding ASCII
        $powershellPath = Join-Path $PSHOME "powershell.exe"
        return Invoke-CheckedCommand -FilePath $powershellPath -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $scriptPath
        ) -WorkingDirectory $WorkingDirectory
    } finally {
        Remove-TempFixture -Path $fixture
    }
}

function Set-FixtureManifestModelContents {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][hashtable]$ModelContents
    )

    $manifestPath = Join-Path $ProjectRoot "scripts\config\bootstrap-manifest.json"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($model in @($manifest.release.models)) {
        if (-not $ModelContents.ContainsKey($model.filename)) {
            continue
        }

        $content = [string]$ModelContents[$model.filename]
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($content)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $model.bytes = $bytes.Length
            $model.sha256 = ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "")
        } finally {
            $sha256.Dispose()
        }
    }

    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding ASCII
}

function New-DoctorFixture {
    $root = New-BootstrapFixture

    foreach ($relativePath in @(
        "backend\data",
        "backend\.venv\Scripts",
        "frontend\node_modules",
        "models"
    )) {
        New-Item -ItemType Directory -Path (Join-Path $root $relativePath) -Force | Out-Null
    }

    $defaultModels = @{
        "tt100k-yolo11s-reference42.pt" = "detector-default"
        "tt100k-yolo11n-common45.pt" = "detector-optional"
        "gtsrb-yolo11n-cls.pt" = "classifier-default"
    }
    Set-FixtureManifestModelContents -ProjectRoot $root -ModelContents $defaultModels

    foreach ($entry in $defaultModels.GetEnumerator()) {
        [System.IO.File]::WriteAllText((Join-Path $root "models\$($entry.Key)"), [string]$entry.Value, [System.Text.Encoding]::ASCII)
    }

    [System.IO.File]::WriteAllText((Join-Path $root "backend\.venv\Scripts\python.exe"), "fixture-python", [System.Text.Encoding]::ASCII)

    $envContent = @(
        "APP_MODE=local",
        "DATABASE_URL=sqlite:///./data/local.db",
        "REDIS_ENABLED=false",
        "MINIO_ENABLED=false",
        "YOLO_MODEL_PATH=../models/tt100k-yolo11s-reference42.pt",
        "YOLO_DEVICE=cpu",
        "GTSRB_MODEL_PATH=../models/gtsrb-yolo11n-cls.pt",
        "GTSRB_DEVICE=cpu",
        "JWT_SECRET_KEY=super-secret-fixture-value"
    ) -join "`r`n"
    Set-Content -LiteralPath (Join-Path $root "backend\.env") -Value ($envContent + "`r`n") -Encoding ASCII

    return $root
}

function Start-TestTcpListener {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()

    return [pscustomobject]@{
        Listener = $listener
        Port = ([int]$listener.LocalEndpoint.Port)
    }
}

function Get-BootstrapScriptTests {
    return @(
        @{
            Name = "Bootstrap script AST parses cleanly and exposes the expected parameters"
            Body = {
                $bootstrapScriptPath = Get-BootstrapScriptPath
                $tokens = $null
                $parseErrors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($bootstrapScriptPath, [ref]$tokens, [ref]$parseErrors)

                Assert-Equal -Expected 0 -Actual $parseErrors.Count -Message "Bootstrap script parse errors were found."

                $attributeText = ($ast.ParamBlock.Attributes | ForEach-Object { $_.Extent.Text }) -join " "
                Assert-Contains -ExpectedSubstring "SupportsShouldProcess" -Actual $attributeText -Message "CmdletBinding must advertise SupportsShouldProcess."

                $parameterNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
                $requiredParameterNames = @(
                    "Device",
                    "SkipRuntimeDownload",
                    "SkipModels",
                    "ForceConfig",
                    "Start",
                    "PlanOnly",
                    "ProjectRoot"
                )

                foreach ($parameterName in $requiredParameterNames) {
                    Assert-True -Condition ($parameterNames -contains $parameterName) -Message "Missing required bootstrap parameter '$parameterName'."
                }
            }
        },
        @{
            Name = "PlanOnly auto gpu emits the stable plan contract and does not mutate the fixture"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $result = Invoke-BootstrapScriptProcess -ProjectRoot $fixture -ArgumentList @(
                        "-PlanOnly",
                        "-Device",
                        "auto",
                        "-NvidiaSmiAvailable",
                        "`$true",
                        "-OsArchitectureOverride",
                        "x64",
                        "-FreeSpaceGbOverride",
                        "24"
                    )

                    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "PlanOnly auto gpu should succeed."
                    $plan = $result.StdOut | ConvertFrom-Json
                    Assert-True -Condition $plan.planOnly -Message "PlanOnly should report planOnly=true."
                    Assert-Equal -Expected "auto" -Actual $plan.requestedDevice -Message "Requested device mismatch."
                    Assert-Equal -Expected "gpu" -Actual $plan.selectedDevice -Message "Selected device mismatch."
                    Assert-Equal -Expected "3.10.11" -Actual $plan.runtime.python.version -Message "Python version mismatch."
                    Assert-Equal -Expected "24.18.0" -Actual $plan.runtime.node.version -Message "Node version mismatch."
                    Assert-Equal -Expected "backend/requirements-gpu.txt" -Actual $plan.requirementsFile -Message "GPU requirements mismatch."
                    Assert-Equal -Expected "npm ci" -Actual $plan.frontend.installCommand -Message "npm plan mismatch."
                    Assert-Equal -Expected "create-if-missing" -Actual $plan.config.action -Message "Config plan mismatch."
                    Assert-Equal -Expected "scripts/doctor.ps1" -Actual $plan.doctor.script -Message "Doctor path mismatch."
                    Assert-False -Condition $plan.start.enabled -Message "Start should be disabled by default."
                    Assert-Equal -Expected @(
                        "tt100k-yolo11s-reference42.pt",
                        "gtsrb-yolo11n-cls.pt"
                    ) -Actual @($plan.models | ForEach-Object { $_.filename }) -Message "Default models mismatch."
                    Assert-NoPlanOnlyMutations -ProjectRoot $fixture
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "PlanOnly auto cpu emits the stable plan contract and does not mutate the fixture"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $result = Invoke-BootstrapScriptProcess -ProjectRoot $fixture -ArgumentList @(
                        "-PlanOnly",
                        "-Device",
                        "auto",
                        "-NvidiaSmiAvailable",
                        "`$false",
                        "-OsArchitectureOverride",
                        "x64",
                        "-FreeSpaceGbOverride",
                        "8",
                        "-SkipModels",
                        "-ForceConfig",
                        "-Start"
                    )

                    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "PlanOnly auto cpu should succeed."
                    $plan = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected "cpu" -Actual $plan.selectedDevice -Message "Selected device mismatch."
                    Assert-Equal -Expected "backend/requirements-cpu.txt" -Actual $plan.requirementsFile -Message "CPU requirements mismatch."
                    Assert-Equal -Expected 0 -Actual @($plan.models).Count -Message "SkipModels should remove model downloads from the plan."
                    Assert-Equal -Expected "replace" -Actual $plan.config.action -Message "ForceConfig should replace the config."
                    Assert-True -Condition $plan.start.enabled -Message "Start should be enabled when requested."
                    Assert-NoPlanOnlyMutations -ProjectRoot $fixture
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "PlanOnly forced cpu never selects GPU requirements"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $result = Invoke-BootstrapScriptProcess -ProjectRoot $fixture -ArgumentList @(
                        "-PlanOnly",
                        "-Device",
                        "cpu",
                        "-NvidiaSmiAvailable",
                        "`$true",
                        "-OsArchitectureOverride",
                        "x64",
                        "-FreeSpaceGbOverride",
                        "8"
                    )

                    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "PlanOnly cpu should succeed."
                    $plan = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected "cpu" -Actual $plan.selectedDevice -Message "Selected device mismatch."
                    Assert-Equal -Expected "backend/requirements-cpu.txt" -Actual $plan.requirementsFile -Message "Forced cpu should keep CPU requirements."
                    Assert-NoPlanOnlyMutations -ProjectRoot $fixture
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "WhatIf returns the same stable plan contract and does not mutate or run follow-up scripts"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    Set-Content -LiteralPath (Join-Path $fixture "scripts\doctor.ps1") -Value "Set-Content -LiteralPath '$fixture\doctor-ran.txt' -Value 'doctor'" -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $fixture "scripts\start.ps1") -Value "Set-Content -LiteralPath '$fixture\start-ran.txt' -Value 'start'" -Encoding ASCII

                    $planOnly = Invoke-BootstrapScriptProcess -ProjectRoot $fixture -ArgumentList @(
                        "-PlanOnly",
                        "-Device",
                        "cpu",
                        "-SkipRuntimeDownload",
                        "-DisablePathRuntimeProbe",
                        "-SkipModels",
                        "-ForceConfig",
                        "-Start",
                        "-OsArchitectureOverride",
                        "x64",
                        "-FreeSpaceGbOverride",
                        "8"
                    )
                    Assert-Equal -Expected 0 -Actual $planOnly.ExitCode -Message "PlanOnly baseline should succeed."

                    $whatIf = Invoke-BootstrapScriptProcess -ProjectRoot $fixture -ArgumentList @(
                        "-WhatIf",
                        "-Device",
                        "cpu",
                        "-SkipRuntimeDownload",
                        "-DisablePathRuntimeProbe",
                        "-SkipModels",
                        "-ForceConfig",
                        "-Start",
                        "-OsArchitectureOverride",
                        "x64",
                        "-FreeSpaceGbOverride",
                        "8"
                    )

                    Assert-Equal -Expected 0 -Actual $whatIf.ExitCode -Message "WhatIf should succeed."
                    $planOnlyPlan = $planOnly.StdOut | ConvertFrom-Json
                    $whatIfPlan = $whatIf.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected (ConvertTo-CanonicalJson -Object $planOnlyPlan) -Actual (ConvertTo-CanonicalJson -Object $whatIfPlan) -Message "WhatIf plan contract mismatch."
                    Assert-NoBootstrapMutations -ProjectRoot $fixture
                    Assert-False -Condition (Test-Path -LiteralPath (Join-Path $fixture "doctor-ran.txt")) -Message "WhatIf must not run doctor.ps1."
                    Assert-False -Condition (Test-Path -LiteralPath (Join-Path $fixture "start-ran.txt")) -Message "WhatIf must not run start.ps1."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "PlanOnly without ProjectRoot defaults to the repository root"
            Body = {
                $result = Invoke-BootstrapScriptProcess -ArgumentList @(
                    "-PlanOnly",
                    "-Device",
                    "cpu",
                    "-OsArchitectureOverride",
                    "x64",
                    "-FreeSpaceGbOverride",
                    "8",
                    "-SkipModels"
                )

                Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "PlanOnly without ProjectRoot should succeed."
                $plan = $result.StdOut | ConvertFrom-Json
                $expectedRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
                Assert-Equal -Expected $expectedRoot -Actual $plan.projectRoot -Message "Default ProjectRoot mismatch."
            }
        },
        @{
            Name = "Forced gpu fails when Nvidia support is unavailable"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $result = Invoke-BootstrapScriptProcess -ProjectRoot $fixture -ArgumentList @(
                        "-PlanOnly",
                        "-Device",
                        "gpu",
                        "-NvidiaSmiAvailable",
                        "`$false",
                        "-OsArchitectureOverride",
                        "x64",
                        "-FreeSpaceGbOverride",
                        "24"
                    )

                    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message "Forced gpu should fail without Nvidia."
                    Assert-Contains -ExpectedSubstring "GPU mode requires Nvidia support" -Actual ($result.StdOut + $result.StdErr) -Message "GPU failure message mismatch."
                    Assert-NoPlanOnlyMutations -ProjectRoot $fixture
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "PlanOnly fails when the bootstrap manifest is missing"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    Remove-Item -LiteralPath (Join-Path $fixture "scripts\config\bootstrap-manifest.json") -Force
                    $result = Invoke-BootstrapScriptProcess -ProjectRoot $fixture -ArgumentList @(
                        "-PlanOnly",
                        "-Device",
                        "cpu",
                        "-OsArchitectureOverride",
                        "x64",
                        "-FreeSpaceGbOverride",
                        "8"
                    )

                    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message "Missing manifest should fail."
                    Assert-Contains -ExpectedSubstring "bootstrap-manifest.json" -Actual ($result.StdOut + $result.StdErr) -Message "Missing manifest failure should mention the manifest path."
                    Assert-NoPlanOnlyMutations -ProjectRoot $fixture
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "PlanOnly rejects a non-x64 architecture override"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $result = Invoke-BootstrapScriptProcess -ProjectRoot $fixture -ArgumentList @(
                        "-PlanOnly",
                        "-Device",
                        "cpu",
                        "-OsArchitectureOverride",
                        "x86",
                        "-FreeSpaceGbOverride",
                        "8"
                    )

                    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message "Non-x64 architecture should fail."
                    Assert-Contains -ExpectedSubstring "Windows x64" -Actual ($result.StdOut + $result.StdErr) -Message "Architecture failure message mismatch."
                    Assert-NoPlanOnlyMutations -ProjectRoot $fixture
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "PlanOnly rejects manifest entries that escape the project root"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $manifestPath = Join-Path $fixture "scripts\config\bootstrap-manifest.json"
                    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                    $manifest.runtime.python.filename = "..\python-3.10.11-amd64.exe"
                    ($manifest | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $manifestPath -Encoding ASCII

                    $result = Invoke-BootstrapScriptProcess -ProjectRoot $fixture -ArgumentList @(
                        "-PlanOnly",
                        "-Device",
                        "cpu",
                        "-OsArchitectureOverride",
                        "x64",
                        "-FreeSpaceGbOverride",
                        "8"
                    )

                    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message "Escaping manifest filename should fail."
                    Assert-Contains -ExpectedSubstring "runtime.python.filename" -Actual ($result.StdOut + $result.StdErr) -Message "Manifest validation failure mismatch."
                    Assert-NoPlanOnlyMutations -ProjectRoot $fixture
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Atomic Node replacement validates staging first and restores the prior runtime on swap failure"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $runtimeRoot = Join-Path $fixture ".runtime"
                    $nodeRoot = Join-Path $runtimeRoot "node"
                    $nodeTempRoot = Join-Path $runtimeRoot "tmp"
                    New-Item -ItemType Directory -Path $nodeRoot -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $nodeRoot "node.exe") -Value "old-version" -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $nodeRoot "npm.cmd") -Value "old-npm" -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $nodeRoot "marker.txt") -Value "old-marker" -Encoding ASCII
                    $archivePath = New-NodeRuntimeArchive -FixtureRoot $fixture -Version "24.18.0" -NodeContent "24.18.0" -ArchiveName "node-good.zip"

                    $scriptPath = (Get-BootstrapScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $escapedArchive = $archivePath.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$scriptPath'
`$paths = [pscustomobject]@{
    Root = '$escapedFixture'
    RuntimeRoot = '$escapedFixture\.runtime'
    NodeRoot = '$escapedFixture\.runtime\node'
    NodeTempRoot = '$escapedFixture\.runtime\tmp'
}
`$versionResolver = {
    param(`$NodePath)
    [System.IO.File]::ReadAllText(`$NodePath).Trim()
}
`$null = Install-NodeRuntimeAtomically -Paths `$paths -ZipPath '$escapedArchive' -ExpectedVersion '24.18.0' -NodeVersionResolver `$versionResolver
`$afterSuccess = [ordered]@{
    NodeContent = [System.IO.File]::ReadAllText((Join-Path `$paths.NodeRoot 'node.exe')).Trim()
    MarkerExists = Test-Path -LiteralPath (Join-Path `$paths.NodeRoot 'marker.txt')
}
try {
    `$null = Install-NodeRuntimeAtomically -Paths `$paths -ZipPath '$escapedArchive' -ExpectedVersion '24.18.0' -NodeVersionResolver { param(`$NodePath) '0.0.0' }
    throw 'Expected atomic swap failure.'
} catch {
    [ordered]@{
        SuccessNodeContent = `$afterSuccess.NodeContent
        SuccessMarkerExists = `$afterSuccess.MarkerExists
        FailureMessage = `$_.Exception.Message
        RestoredNodeContent = [System.IO.File]::ReadAllText((Join-Path `$paths.NodeRoot 'node.exe')).Trim()
        RestoredMarkerExists = Test-Path -LiteralPath (Join-Path `$paths.NodeRoot 'marker.txt')
        BackupCount = @((Get-ChildItem -LiteralPath `$paths.RuntimeRoot -Directory -ErrorAction SilentlyContinue | Where-Object { `$_.Name -like 'node-backup-*' })).Count
        TempCount = if (Test-Path -LiteralPath `$paths.NodeTempRoot) { @((Get-ChildItem -LiteralPath `$paths.NodeTempRoot -Force -ErrorAction SilentlyContinue)).Count } else { 0 }
    } | ConvertTo-Json -Compress
}
"@

                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected "24.18.0" -Actual $state.SuccessNodeContent -Message "Successful swap should install the staged runtime."
                    Assert-False -Condition $state.SuccessMarkerExists -Message "Successful swap should replace the old runtime contents."
                    Assert-Contains -ExpectedSubstring "Node version mismatch" -Actual $state.FailureMessage -Message "Failed swap should surface version validation failure."
                    Assert-Equal -Expected "24.18.0" -Actual $state.RestoredNodeContent -Message "Failed swap should restore the last known-good runtime."
                    Assert-False -Condition $state.RestoredMarkerExists -Message "Failed swap should not restore the original pre-success marker after the new runtime became known-good."
                    Assert-Equal -Expected 0 -Actual $state.BackupCount -Message "Backups should be cleaned after restore."
                    Assert-Equal -Expected 0 -Actual $state.TempCount -Message "Staging directories should be cleaned."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Atomic Python replacement validates staging first and restores the prior runtime on swap failure"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $runtimeRoot = Join-Path $fixture ".runtime"
                    $pythonRoot = Join-Path $runtimeRoot "python"
                    $downloadsRoot = Join-Path $runtimeRoot "downloads"
                    New-Item -ItemType Directory -Path $pythonRoot -Force | Out-Null
                    New-Item -ItemType Directory -Path $downloadsRoot -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $pythonRoot "python.exe") -Value "3.10.10" -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $pythonRoot "marker.txt") -Value "old-python" -Encoding ASCII
                    $installerPath = Join-Path $downloadsRoot "python-installer.exe"
                    Set-Content -LiteralPath $installerPath -Value "fake-installer" -Encoding ASCII

                    $scriptPath = (Get-BootstrapScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $escapedInstaller = $installerPath.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$scriptPath'
`$paths = [pscustomobject]@{
    Root = '$escapedFixture'
    RuntimeRoot = '$escapedFixture\.runtime'
    DownloadsRoot = '$escapedFixture\.runtime\downloads'
    PythonRoot = '$escapedFixture\.runtime\python'
}
`$installer = {
    param(`$InstallerPath, `$TargetDir)
    New-Item -ItemType Directory -Path `$TargetDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path `$TargetDir 'python.exe') -Value '3.10.11' -Encoding ASCII
}
`$versionResolver = {
    param(`$PythonPath)
    [System.IO.File]::ReadAllText(`$PythonPath).Trim()
}
`$null = Install-PythonRuntimeAtomically -Paths `$paths -InstallerPath '$escapedInstaller' -ExpectedVersion '3.10.11' -InstallerInvoker `$installer -PythonVersionResolver `$versionResolver
`$afterSuccess = [ordered]@{
    PythonContent = [System.IO.File]::ReadAllText((Join-Path `$paths.PythonRoot 'python.exe')).Trim()
    MarkerExists = Test-Path -LiteralPath (Join-Path `$paths.PythonRoot 'marker.txt')
}
try {
    `$null = Install-PythonRuntimeAtomically -Paths `$paths -InstallerPath '$escapedInstaller' -ExpectedVersion '3.10.11' -InstallerInvoker {
        param(`$InstallerPath, `$TargetDir)
        New-Item -ItemType Directory -Path `$TargetDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path `$TargetDir 'python.exe') -Value '0.0.0' -Encoding ASCII
    } -PythonVersionResolver `$versionResolver
    throw 'Expected atomic python swap failure.'
} catch {
    [ordered]@{
        SuccessPythonContent = `$afterSuccess.PythonContent
        SuccessMarkerExists = `$afterSuccess.MarkerExists
        FailureMessage = `$_.Exception.Message
        RestoredPythonContent = [System.IO.File]::ReadAllText((Join-Path `$paths.PythonRoot 'python.exe')).Trim()
        RestoredMarkerExists = Test-Path -LiteralPath (Join-Path `$paths.PythonRoot 'marker.txt')
        BackupCount = @((Get-ChildItem -LiteralPath `$paths.RuntimeRoot -Directory -ErrorAction SilentlyContinue | Where-Object { `$_.Name -like 'python-backup-*' })).Count
        StageCount = @((Get-ChildItem -LiteralPath `$paths.RuntimeRoot -Directory -ErrorAction SilentlyContinue | Where-Object { `$_.Name -like 'python-stage-*' })).Count
    } | ConvertTo-Json -Compress
}
"@

                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected "3.10.11" -Actual $state.SuccessPythonContent -Message "Successful swap should install the staged Python runtime."
                    Assert-False -Condition $state.SuccessMarkerExists -Message "Successful swap should replace the old Python runtime contents."
                    Assert-Contains -ExpectedSubstring "Python version mismatch" -Actual $state.FailureMessage -Message "Failed swap should surface version validation failure."
                    Assert-Equal -Expected "3.10.11" -Actual $state.RestoredPythonContent -Message "Failed swap should restore the last known-good Python runtime."
                    Assert-False -Condition $state.RestoredMarkerExists -Message "Failed swap should not restore the original pre-success marker after the new runtime became known-good."
                    Assert-Equal -Expected 0 -Actual $state.BackupCount -Message "Python backups should be cleaned after restore."
                    Assert-Equal -Expected 0 -Actual $state.StageCount -Message "Python staging directories should be cleaned."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "SkipRuntimeDownload rejects node and npm resolved from different directories"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $nodeDir = Join-Path $fixture "path-node"
                    $npmDir = Join-Path $fixture "path-npm"
                    New-Item -ItemType Directory -Path $nodeDir -Force | Out-Null
                    New-Item -ItemType Directory -Path $npmDir -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $nodeDir "node.exe") -Value "fake-node" -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $nodeDir "node.cmd") -Value "@echo node" -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $npmDir "npm.cmd") -Value "@echo npm" -Encoding ASCII

                    $scriptPath = (Get-BootstrapScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $escapedNodeDir = $nodeDir.Replace("'", "''")
                    $escapedNpmDir = $npmDir.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$scriptPath'
function Get-NodeCommandFromPath {
    param([switch]`$DisableProbe)
    '$escapedNodeDir\node.exe'
}
function Get-ExactNodeVersion {
    param(`$NodePath)
    '24.18.0'
}
`$env:PATH = '$escapedNodeDir;$escapedNpmDir;' + `$env:PATH
`$paths = Resolve-ProjectPaths -RootPath '$escapedFixture'
`$manifest = Read-BootstrapManifest -Path (Join-Path '$escapedFixture' 'scripts\config\bootstrap-manifest.json')
try {
    `$null = Resolve-NodeRuntime -Paths `$paths -Manifest `$manifest -SkipDownload -DisablePathProbe:`$false
    throw 'Expected mismatched PATH runtime failure.'
} catch {
    `$_.Exception.Message
}
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    Assert-Contains -ExpectedSubstring "same directory" -Actual $result.StdOut.Trim() -Message "Node/npm pairing failure should mention the resolved node directory requirement."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Auto GPU fallback recreates the target venv and installs CPU cleanly"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $backendRoot = Join-Path $fixture "backend"
                    $venvRoot = Join-Path $backendRoot ".venv"
                    New-Item -ItemType Directory -Path $venvRoot -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $venvRoot "original.txt") -Value "old-env" -Encoding ASCII
                    $scriptPath = (Get-BootstrapScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$scriptPath'
`$paths = Resolve-ProjectPaths -RootPath '$escapedFixture'
`$log = New-Object System.Collections.Generic.List[string]
`$createAttempts = 0
`$null = Install-BackendPythonEnvironment -Paths `$paths -PythonPath 'fake-python.exe' -RequestedDevice 'auto' -InitialDevice 'gpu' -CpuRequirementsPath (Join-Path `$paths.BackendRoot 'requirements-cpu.txt') -GpuRequirementsPath (Join-Path `$paths.BackendRoot 'requirements-gpu.txt') -VenvCreator {
    param(`$PythonPath, `$TargetPath)
    `$script:createAttempts++
    `$attempt = `$script:createAttempts
    New-Item -ItemType Directory -Path (Join-Path `$TargetPath 'Scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path `$TargetPath 'Scripts\python.exe') -Value "venv-`$attempt" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path `$TargetPath "created-`$attempt.txt") -Value "attempt-`$attempt" -Encoding ASCII
    `$log.Add("create:`$attempt")
} -RequirementsInstaller {
    param(`$PythonPath, `$RequirementsPath, `$WorkingDirectory)
    `$log.Add("install:" + [System.IO.Path]::GetFileName(`$RequirementsPath))
} -CudaSelfTester {
    param(`$PythonPath)
    `$log.Add('cuda:false')
    `$false
}
[ordered]@{
    Log = @(`$log)
    SelectedDevice = 'cpu'
    OriginalRestored = Test-Path -LiteralPath (Join-Path `$paths.VenvRoot 'original.txt')
    Created1Exists = Test-Path -LiteralPath (Join-Path `$paths.VenvRoot 'created-1.txt')
    Created2Exists = Test-Path -LiteralPath (Join-Path `$paths.VenvRoot 'created-2.txt')
    BackupCount = @((Get-ChildItem -LiteralPath `$paths.BackendRoot -Directory -ErrorAction SilentlyContinue | Where-Object { `$_.Name -like '.venv-backup-*' })).Count
} | ConvertTo-Json -Compress
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected @("create:1","install:requirements-gpu.txt","cuda:false","create:2","install:requirements-cpu.txt") -Actual @($state.Log) -Message "Auto GPU fallback call order mismatch."
                    Assert-False -Condition $state.OriginalRestored -Message "Successful fallback should not restore the original venv."
                    Assert-False -Condition $state.Created1Exists -Message "Fallback should remove the first GPU venv before recreating CPU."
                    Assert-True -Condition $state.Created2Exists -Message "Fallback should create a second fresh CPU venv."
                    Assert-Equal -Expected 0 -Actual $state.BackupCount -Message "Successful fallback should clean the venv backup."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Forced GPU failure restores the original venv backup"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $backendRoot = Join-Path $fixture "backend"
                    $venvRoot = Join-Path $backendRoot ".venv"
                    New-Item -ItemType Directory -Path $venvRoot -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $venvRoot "original.txt") -Value "old-env" -Encoding ASCII
                    $scriptPath = (Get-BootstrapScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$scriptPath'
`$paths = Resolve-ProjectPaths -RootPath '$escapedFixture'
try {
    Install-BackendPythonEnvironment -Paths `$paths -PythonPath 'fake-python.exe' -RequestedDevice 'gpu' -InitialDevice 'gpu' -CpuRequirementsPath (Join-Path `$paths.BackendRoot 'requirements-cpu.txt') -GpuRequirementsPath (Join-Path `$paths.BackendRoot 'requirements-gpu.txt') -VenvCreator {
        param(`$PythonPath, `$TargetPath)
        New-Item -ItemType Directory -Path (Join-Path `$TargetPath 'Scripts') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path `$TargetPath 'Scripts\python.exe') -Value 'venv-gpu' -Encoding ASCII
    } -RequirementsInstaller {
        param(`$PythonPath, `$RequirementsPath, `$WorkingDirectory)
    } -CudaSelfTester {
        param(`$PythonPath)
        `$false
    } | Out-Null
    throw 'Expected forced GPU failure.'
} catch {
    [ordered]@{
        Message = `$_.Exception.Message
        OriginalRestored = Test-Path -LiteralPath (Join-Path `$paths.VenvRoot 'original.txt')
        BackupCount = @((Get-ChildItem -LiteralPath `$paths.BackendRoot -Directory -ErrorAction SilentlyContinue | Where-Object { `$_.Name -like '.venv-backup-*' })).Count
    } | ConvertTo-Json -Compress
}
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Contains -ExpectedSubstring "GPU mode requires torch CUDA self-test to succeed" -Actual $state.Message -Message "Forced GPU failure should surface the CUDA self-test failure."
                    Assert-True -Condition $state.OriginalRestored -Message "Forced GPU failure should restore the original venv."
                    Assert-Equal -Expected 0 -Actual $state.BackupCount -Message "Forced GPU failure should clean the venv backup after restore."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Assert-NoReparsePointTraversal rejects junction descendants"
            Body = {
                $fixture = New-BootstrapFixture
                $external = New-TempFixture
                try {
                    $junctionPath = Join-Path $fixture "backend\linked"
                    New-Item -ItemType Directory -Path $external -Force | Out-Null
                    New-Item -ItemType Junction -Path $junctionPath -Target $external | Out-Null
                    Assert-TestRequiresJunction -Path $junctionPath
                    $scriptPath = (Get-BootstrapScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $escapedJunctionChild = (Join-Path $junctionPath "payload.txt").Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$scriptPath'
try {
    Assert-NoReparsePointTraversal -RootPath '$escapedFixture' -Path '$escapedJunctionChild'
    throw 'Expected reparse traversal failure.'
} catch {
    `$_.Exception.Message
}
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    Assert-Contains -ExpectedSubstring "reparse point" -Actual $result.StdOut.Trim().ToLowerInvariant() -Message "Reparse traversal failure should mention reparse points."
                } finally {
                    Remove-TempFixture -Path $external
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Invoke-DownloadWithHashValidation rejects a junction download directory and existing partial-path junction"
            Body = {
                $fixture = New-BootstrapFixture
                $external = New-TempFixture
                try {
                    $downloadRoot = Join-Path $fixture ".runtime\downloads"
                    $junctionDirectory = Join-Path $fixture ".runtime\junction-downloads"
                    $partialJunction = Join-Path $downloadRoot "payload.zip.partial"
                    New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
                    New-Item -ItemType Directory -Path $external -Force | Out-Null
                    New-Item -ItemType Junction -Path $junctionDirectory -Target $external | Out-Null
                    New-Item -ItemType Junction -Path $partialJunction -Target $external | Out-Null

                    $scriptPath = (Get-BootstrapScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $escapedDownloadDir = $junctionDirectory.Replace("'", "''")
                    $escapedPartialDir = $downloadRoot.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$scriptPath'
function Invoke-WebRequest {
    param([string]`$Uri, [string]`$OutFile)
    throw 'invoke-webrequest-reached'
}
`$results = [ordered]@{}
try {
    `$downloadPaths = [pscustomobject]@{
        Directory = '$escapedDownloadDir'
        FinalPath = (Join-Path '$escapedDownloadDir' 'payload.zip')
        PartialPath = (Join-Path '$escapedDownloadDir' 'payload.zip.partial')
    }
    `$null = Invoke-DownloadWithHashValidation -RootPath '$escapedFixture' -Url 'https://example.invalid/payload.zip' -ExpectedSha256 ('A' * 64) -DownloadPaths `$downloadPaths
    `$results.Directory = 'unexpected-success'
} catch {
    `$results.Directory = `$_.Exception.Message
}
try {
    `$downloadPaths = [pscustomobject]@{
        Directory = '$escapedPartialDir'
        FinalPath = (Join-Path '$escapedPartialDir' 'payload.zip')
        PartialPath = (Join-Path '$escapedPartialDir' 'payload.zip.partial')
    }
    `$null = Invoke-DownloadWithHashValidation -RootPath '$escapedFixture' -Url 'https://example.invalid/payload.zip' -ExpectedSha256 ('A' * 64) -DownloadPaths `$downloadPaths
    `$results.Partial = 'unexpected-success'
} catch {
    `$results.Partial = `$_.Exception.Message
}
`$results | ConvertTo-Json -Compress
"@

                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Contains -ExpectedSubstring "reparse point" -Actual $state.Directory.ToLowerInvariant() -Message "Download directory reparse failure should mention reparse points."
                    Assert-Contains -ExpectedSubstring "reparse point" -Actual $state.Partial.ToLowerInvariant() -Message "Partial-path reparse failure should mention reparse points."
                    Assert-False -Condition ($state.Directory -eq "invoke-webrequest-reached") -Message "Reparse validation must reject before download execution."
                    Assert-False -Condition ($state.Partial -eq "invoke-webrequest-reached") -Message "Reparse validation must reject before download execution."
                } finally {
                    Remove-TempFixture -Path $external
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Controlled non-PlanOnly workflow runs the full success orchestration in order"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    Set-Content -LiteralPath (Join-Path $fixture "scripts\doctor.ps1") -Value "Set-Content -LiteralPath '$fixture\doctor-ran.txt' -Value 'doctor'" -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $fixture "scripts\start.ps1") -Value "Set-Content -LiteralPath '$fixture\start-ran.txt' -Value 'start'" -Encoding ASCII
                    $scriptPath = (Get-BootstrapScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$scriptPath'
`$log = New-Object System.Collections.Generic.List[string]
function Resolve-PythonRuntime {
    param(`$Paths, `$Manifest, [switch]`$SkipDownload, [switch]`$DisablePathProbe)
    `$log.Add('python')
    New-Item -ItemType Directory -Path `$Paths.PythonRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path `$Paths.PythonRoot 'python.exe') -Value '3.10.11' -Encoding ASCII
    return (Join-Path `$Paths.PythonRoot 'python.exe')
}
function Resolve-NodeRuntime {
    param(`$Paths, `$Manifest, [switch]`$SkipDownload, [switch]`$DisablePathProbe)
    `$log.Add('node')
    New-Item -ItemType Directory -Path `$Paths.NodeRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path `$Paths.NodeRoot 'node.exe') -Value '24.18.0' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path `$Paths.NodeRoot 'npm.cmd') -Value '@echo npm' -Encoding ASCII
    return [pscustomobject]@{ NodePath = (Join-Path `$Paths.NodeRoot 'node.exe'); NpmPath = (Join-Path `$Paths.NodeRoot 'npm.cmd') }
}
function Install-BackendPythonEnvironment {
    param(`$Paths, `$PythonPath, `$RequestedDevice, `$InitialDevice, `$CpuRequirementsPath, `$GpuRequirementsPath, `$VenvCreator, `$RequirementsInstaller, `$CudaSelfTester)
    `$log.Add('venv:' + `$InitialDevice)
    New-Item -ItemType Directory -Path (Join-Path `$Paths.VenvRoot 'Scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path `$Paths.VenvRoot 'Scripts\python.exe') -Value 'venv-python' -Encoding ASCII
    return [pscustomobject]@{ VenvPythonPath = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe'); SelectedDevice = `$InitialDevice; RequirementsPath = `$GpuRequirementsPath }
}
function Invoke-NpmInstall {
    param(`$NpmPath, `$FrontendRoot)
    `$log.Add('npm')
}
function Ensure-ModelFiles {
    param(`$Paths, `$Models)
    foreach (`$model in @(`$Models)) {
        `$log.Add('model:' + `$model.filename)
        New-Item -ItemType Directory -Path `$Paths.ModelsRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path `$Paths.ModelsRoot `$model.filename) -Value 'model' -Encoding ASCII
    }
}
`$null = Invoke-BootstrapWorkflow -ProjectRoot '$escapedFixture' -Device 'auto' -ForceConfig -Start -NvidiaSmiAvailable '$true' -OsArchitectureOverride 'x64' -FreeSpaceGbOverride 24
[ordered]@{
    Log = @(`$log)
    EnvExists = Test-Path -LiteralPath (Join-Path '$escapedFixture' 'backend\.env')
    VenvExists = Test-Path -LiteralPath (Join-Path '$escapedFixture' 'backend\.venv\Scripts\python.exe')
    ModelCount = @((Get-ChildItem -LiteralPath (Join-Path '$escapedFixture' 'models') -File -ErrorAction SilentlyContinue)).Count
    DoctorRan = Test-Path -LiteralPath (Join-Path '$escapedFixture' 'doctor-ran.txt')
    StartRan = Test-Path -LiteralPath (Join-Path '$escapedFixture' 'start-ran.txt')
    OutputSecretLeak = `$false
} | ConvertTo-Json -Compress
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected @("python","node","venv:gpu","npm","model:tt100k-yolo11s-reference42.pt","model:gtsrb-yolo11n-cls.pt") -Actual @($state.Log) -Message "Full success orchestration order mismatch."
                    Assert-True -Condition $state.EnvExists -Message "Full success orchestration should generate backend/.env."
                    Assert-True -Condition $state.VenvExists -Message "Full success orchestration should leave a venv."
                    Assert-Equal -Expected 2 -Actual $state.ModelCount -Message "Full success orchestration should materialize the two default models."
                    Assert-True -Condition $state.DoctorRan -Message "Full success orchestration should run doctor."
                    Assert-True -Condition $state.StartRan -Message "Full success orchestration should run start when requested."
                    Assert-False -Condition $state.OutputSecretLeak -Message "Full success orchestration must not leak secrets to output."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Invoke-BootstrapWorkflow propagates late model failure and does not run doctor or start"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    Set-Content -LiteralPath (Join-Path $fixture "scripts\doctor.ps1") -Value "Set-Content -LiteralPath '$fixture\doctor-ran.txt' -Value 'doctor'" -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $fixture "scripts\start.ps1") -Value "Set-Content -LiteralPath '$fixture\start-ran.txt' -Value 'start'" -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $fixture "backend\user-note.txt") -Value "keep-me" -Encoding ASCII
                    $scriptPath = (Get-BootstrapScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$scriptPath'
function Resolve-PythonRuntime {
    param(`$Paths, `$Manifest, [switch]`$SkipDownload, [switch]`$DisablePathProbe)
    New-Item -ItemType Directory -Path `$Paths.PythonRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path `$Paths.PythonRoot 'python.exe') -Value '3.10.11' -Encoding ASCII
    return (Join-Path `$Paths.PythonRoot 'python.exe')
}
function Resolve-NodeRuntime {
    param(`$Paths, `$Manifest, [switch]`$SkipDownload, [switch]`$DisablePathProbe)
    New-Item -ItemType Directory -Path `$Paths.NodeRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path `$Paths.NodeRoot 'node.exe') -Value '24.18.0' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path `$Paths.NodeRoot 'npm.cmd') -Value '@echo npm' -Encoding ASCII
    return [pscustomobject]@{ NodePath = (Join-Path `$Paths.NodeRoot 'node.exe'); NpmPath = (Join-Path `$Paths.NodeRoot 'npm.cmd') }
}
function Install-BackendPythonEnvironment {
    param(`$Paths, `$PythonPath, `$RequestedDevice, `$InitialDevice, `$CpuRequirementsPath, `$GpuRequirementsPath, `$VenvCreator, `$RequirementsInstaller, `$CudaSelfTester)
    New-Item -ItemType Directory -Path (Join-Path `$Paths.VenvRoot 'Scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path `$Paths.VenvRoot 'Scripts\python.exe') -Value 'venv-python' -Encoding ASCII
    return [pscustomobject]@{ VenvPythonPath = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe'); SelectedDevice = `$InitialDevice; RequirementsPath = `$GpuRequirementsPath }
}
function Invoke-NpmInstall { param(`$NpmPath, `$FrontendRoot) }
function Ensure-ModelFiles {
    param(`$Paths, `$Models)
    throw 'late-model-failure'
}
try {
    `$null = Invoke-BootstrapWorkflow -ProjectRoot '$escapedFixture' -Device 'auto' -ForceConfig -Start -NvidiaSmiAvailable '$true' -OsArchitectureOverride 'x64' -FreeSpaceGbOverride 24
    throw 'Expected late workflow failure.'
} catch {
    [ordered]@{
        Message = `$_.Exception.Message
        PythonExists = Test-Path -LiteralPath (Join-Path '$escapedFixture' '.runtime\python\python.exe')
        NodeExists = Test-Path -LiteralPath (Join-Path '$escapedFixture' '.runtime\node\node.exe')
        VenvExists = Test-Path -LiteralPath (Join-Path '$escapedFixture' 'backend\.venv\Scripts\python.exe')
        UserNoteExists = Test-Path -LiteralPath (Join-Path '$escapedFixture' 'backend\user-note.txt')
        EnvExists = Test-Path -LiteralPath (Join-Path '$escapedFixture' 'backend\.env')
        DoctorRan = Test-Path -LiteralPath (Join-Path '$escapedFixture' 'doctor-ran.txt')
        StartRan = Test-Path -LiteralPath (Join-Path '$escapedFixture' 'start-ran.txt')
    } | ConvertTo-Json -Compress
}
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Contains -ExpectedSubstring "late-model-failure" -Actual $state.Message -Message "Late workflow failure should propagate the model failure."
                    Assert-True -Condition $state.PythonExists -Message "Late workflow failure should retain the resolved Python runtime."
                    Assert-True -Condition $state.NodeExists -Message "Late workflow failure should retain the resolved Node runtime."
                    Assert-True -Condition $state.VenvExists -Message "Late workflow failure should retain the prepared venv."
                    Assert-True -Condition $state.UserNoteExists -Message "Late workflow failure should not remove unrelated user-owned artifacts."
                    Assert-False -Condition $state.EnvExists -Message "Late workflow failure before env generation should not create backend/.env."
                    Assert-False -Condition $state.DoctorRan -Message "Late workflow failure should not run doctor."
                    Assert-False -Condition $state.StartRan -Message "Late workflow failure should not run start."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "SkipRuntimeDownload fails when compatible runtimes are unavailable locally and on PATH"
            Body = {
                $fixture = New-BootstrapFixture
                try {
                    $result = Invoke-BootstrapScriptProcess -ProjectRoot $fixture -ArgumentList @(
                        "-Device",
                        "cpu",
                        "-SkipRuntimeDownload",
                        "-SkipModels",
                        "-DisablePathRuntimeProbe",
                        "-OsArchitectureOverride",
                        "x64",
                        "-FreeSpaceGbOverride",
                        "8"
                    )

                    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message "SkipRuntimeDownload should fail when no runtimes exist."
                    Assert-Contains -ExpectedSubstring "SkipRuntimeDownload" -Actual ($result.StdOut + $result.StdErr) -Message "Missing runtime failure should mention SkipRuntimeDownload."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor script AST parses cleanly, exposes the expected parameters, and stays idle when dot-sourced"
            Body = {
                $doctorScriptPath = Get-DoctorScriptPath
                $tokens = $null
                $parseErrors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($doctorScriptPath, [ref]$tokens, [ref]$parseErrors)

                Assert-Equal -Expected 0 -Actual $parseErrors.Count -Message "Doctor script parse errors were found."

                $parameterNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
                foreach ($parameterName in @("Device", "Json", "ProjectRoot")) {
                    Assert-True -Condition ($parameterNames -contains $parameterName) -Message "Missing required doctor parameter '$parameterName'."
                }

                $escapedDoctorPath = $doctorScriptPath.Replace("'", "''")
                $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$escapedDoctorPath'
'dot-sourced'
"@
                $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory (Split-Path -Parent $doctorScriptPath)
                Assert-Equal -Expected "dot-sourced" -Actual $result.StdOut.Trim() -Message "Doctor script should not auto-run when dot-sourced."
                Assert-Equal -Expected "" -Actual $result.StdErr.Trim() -Message "Doctor script emitted unexpected stderr when dot-sourced."
            }
        },
        @{
            Name = "Doctor fake fixture passes and human and JSON output stay secret-free"
            Body = {
                $fixture = New-DoctorFixture
                try {
                    $doctorScriptPath = (Get-DoctorScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$doctorScriptPath'
function Get-DoctorSystemFacts {
    param([string]`$ProjectRoot)
    return [pscustomobject]@{
        IsWindows = `$true
        Architecture = 'x64'
        FreeSpaceBytes = 20GB
    }
}
function Get-DoctorPythonInfo {
    param([object]`$Paths, [object]`$Manifest)
    return [pscustomobject]@{
        Version = '3.10.11'
        Path = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe')
        Source = 'backend-venv'
    }
}
function Get-DoctorNodeInfo {
    param([object]`$Paths, [object]`$Manifest)
    return [pscustomobject]@{
        Version = '24.18.0'
        Path = (Join-Path `$Paths.Root '.runtime\node\node.exe')
        NpmPath = (Join-Path `$Paths.Root '.runtime\node\npm.cmd')
        Source = 'path-node'
    }
}
function Invoke-DoctorPipCheck {
    param([string]`$PythonPath, [string]`$BackendRoot)
    return [pscustomobject]@{
        ExitCode = 0
        Message = 'pip check passed'
    }
}
function Get-DoctorTorchInfo {
    param([string]`$PythonPath)
    return [pscustomobject]@{
        Version = '2.7.1+cpu'
        CudaBuild = `$null
        CudaAvailable = `$false
    }
}
`$result = Invoke-DoctorMain -ProjectRoot '$escapedFixture' -Device auto
[ordered]@{
    ExitCode = `$result.ExitCode
    ResultCount = @(`$result.Results).Count
    Statuses = @(`$result.Results | ForEach-Object { `$_.status })
    Human = (Format-DoctorHumanOutput -Results `$result.Results)
    Json = (Format-DoctorJsonOutput -Results `$result.Results)
} | ConvertTo-Json -Compress
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected 0 -Actual $state.ExitCode -Message "Doctor fixture should pass."
                    Assert-True -Condition ($state.ResultCount -gt 0) -Message "Doctor should return a non-empty result set."
                    Assert-False -Condition (@($state.Statuses | Where-Object { $_ -eq 'FAIL' }).Count -gt 0) -Message "Doctor fixture should not report FAIL."
                    Assert-Contains -ExpectedSubstring "[PASS]" -Actual $state.Human -Message "Doctor human output should contain PASS markers."
                    Assert-Contains -ExpectedSubstring '"status":"PASS"' -Actual $state.Json -Message "Doctor JSON output should contain PASS records."
                    Assert-False -Condition ($state.Human.Contains("super-secret-fixture-value")) -Message "Doctor human output leaked the fixture secret."
                    Assert-False -Condition ($state.Json.Contains("super-secret-fixture-value")) -Message "Doctor JSON output leaked the fixture secret."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor fails with a nonzero exit code when a required model hash is wrong"
            Body = {
                $fixture = New-DoctorFixture
                try {
                    Set-Content -LiteralPath (Join-Path $fixture "models\tt100k-yolo11s-reference42.pt") -Value "corrupted-model" -Encoding ASCII
                    $doctorScriptPath = (Get-DoctorScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$doctorScriptPath'
function Get-DoctorSystemFacts {
    param([string]`$ProjectRoot)
    return [pscustomobject]@{
        IsWindows = `$true
        Architecture = 'x64'
        FreeSpaceBytes = 20GB
    }
}
function Get-DoctorPythonInfo {
    param([object]`$Paths, [object]`$Manifest)
    return [pscustomobject]@{
        Version = '3.10.11'
        Path = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe')
        Source = 'backend-venv'
    }
}
function Get-DoctorNodeInfo {
    param([object]`$Paths, [object]`$Manifest)
    return [pscustomobject]@{
        Version = '24.18.0'
        Path = (Join-Path `$Paths.Root '.runtime\node\node.exe')
        NpmPath = (Join-Path `$Paths.Root '.runtime\node\npm.cmd')
        Source = 'path-node'
    }
}
function Invoke-DoctorPipCheck {
    param([string]`$PythonPath, [string]`$BackendRoot)
    return [pscustomobject]@{
        ExitCode = 0
        Message = 'pip check passed'
    }
}
function Get-DoctorTorchInfo {
    param([string]`$PythonPath)
    return [pscustomobject]@{
        Version = '2.7.1+cpu'
        CudaBuild = `$null
        CudaAvailable = `$false
    }
}
`$result = Invoke-DoctorMain -ProjectRoot '$escapedFixture' -Device auto
[ordered]@{
    ExitCode = `$result.ExitCode
    Human = (Format-DoctorHumanOutput -Results `$result.Results)
    Json = (Format-DoctorJsonOutput -Results `$result.Results)
} | ConvertTo-Json -Compress
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected 1 -Actual $state.ExitCode -Message "Doctor should fail when a required model hash is wrong."
                    Assert-Contains -ExpectedSubstring "[FAIL]" -Actual $state.Human -Message "Doctor human output should mark a bad model hash as FAIL."
                    Assert-Contains -ExpectedSubstring "hash" -Actual $state.Human.ToLowerInvariant() -Message "Doctor human output should mention the hash problem."
                    Assert-Contains -ExpectedSubstring '"status":"FAIL"' -Actual $state.Json -Message "Doctor JSON output should include a FAIL record."
                    Assert-False -Condition ($state.Human.Contains("super-secret-fixture-value")) -Message "Doctor failure output leaked the fixture secret."
                    Assert-False -Condition ($state.Json.Contains("super-secret-fixture-value")) -Message "Doctor failure JSON leaked the fixture secret."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor reports an occupied random port as WARN without using the fixed app ports"
            Body = {
                $listenerState = Start-TestTcpListener
                try {
                    $doctorScriptPath = (Get-DoctorScriptPath).Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$doctorScriptPath'
`$checks = Get-DoctorPortCheckResults -Ports @($($listenerState.Port))
[ordered]@{
    Count = @(`$checks).Count
    Status = `$checks[0].status
    Message = `$checks[0].message
} | ConvertTo-Json -Compress
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory (Split-Path -Parent (Get-DoctorScriptPath))
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected 1 -Actual $state.Count -Message "Doctor should return one port check result for the random port."
                    Assert-Equal -Expected "WARN" -Actual $state.Status -Message "Occupied doctor port check should WARN."
                    Assert-Contains -ExpectedSubstring ([string]$listenerState.Port) -Actual $state.Message -Message "Port warning should mention the occupied random port."
                } finally {
                    $listenerState.Listener.Stop()
                }
            }
        },
        @{
            Name = "Doctor cpu mode accepts a CUDA torch build as usable for CPU inference without failing"
            Body = {
                $fixture = New-DoctorFixture
                try {
                    $doctorScriptPath = (Get-DoctorScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$doctorScriptPath'
function Get-DoctorSystemFacts {
    param([string]`$ProjectRoot)
    [pscustomobject]@{
        IsWindows = `$true
        Architecture = 'x64'
        FreeSpaceBytes = 20GB
    }
}
function Get-DoctorPythonInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '3.10.11'
        Path = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe')
        Source = 'backend-venv'
    }
}
function Get-DoctorNodeInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '24.18.0'
        Path = (Join-Path `$Paths.Root '.runtime\node\node.exe')
        NpmPath = (Join-Path `$Paths.Root '.runtime\node\npm.cmd')
        Source = 'path-node'
    }
}
function Invoke-DoctorPipCheck {
    param([string]`$PythonPath, [string]`$BackendRoot)
    [pscustomobject]@{
        ExitCode = 0
        Message = 'pip check passed'
    }
}
function Get-DoctorTorchInfo {
    param([string]`$PythonPath)
    [pscustomobject]@{
        Version = '2.7.1+cu128'
        CudaBuild = '12.8'
        CudaAvailable = `$true
    }
}
`$result = Invoke-DoctorMain -ProjectRoot '$escapedFixture' -Device cpu
`$torchBuild = @(`$result.Results | Where-Object { `$_.name -eq 'torch-build' })[0]
`$cudaState = @(`$result.Results | Where-Object { `$_.name -eq 'cuda-state' })[0]
[ordered]@{
    ExitCode = `$result.ExitCode
    TorchStatus = `$torchBuild.status
    TorchMessage = `$torchBuild.message
    CudaStatus = `$cudaState.status
    CudaMessage = `$cudaState.message
} | ConvertTo-Json -Compress
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected 0 -Actual $state.ExitCode -Message "CPU mode should not fail when a CUDA torch wheel is installed."
                    Assert-True -Condition (@("PASS", "WARN") -contains [string]$state.TorchStatus) -Message "CPU CUDA wheel status should be PASS or WARN."
                    Assert-True -Condition (@("PASS", "WARN") -contains [string]$state.CudaStatus) -Message "CPU CUDA availability status should be PASS or WARN."
                    Assert-Contains -ExpectedSubstring "usable" -Actual $state.TorchMessage.ToLowerInvariant() -Message "CPU CUDA wheel message should explain usability."
                    Assert-Contains -ExpectedSubstring "larger" -Actual $state.TorchMessage.ToLowerInvariant() -Message "CPU CUDA wheel message should mention the larger wheel size."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor auto mode emits a compute-device result resolved to gpu when CUDA is available"
            Body = {
                $fixture = New-DoctorFixture
                try {
                    $doctorScriptPath = (Get-DoctorScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$doctorScriptPath'
function Get-DoctorSystemFacts {
    param([string]`$ProjectRoot)
    [pscustomobject]@{
        IsWindows = `$true
        Architecture = 'x64'
        FreeSpaceBytes = 20GB
    }
}
function Get-DoctorPythonInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '3.10.11'
        Path = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe')
        Source = 'backend-venv'
    }
}
function Get-DoctorNodeInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '24.18.0'
        Path = (Join-Path `$Paths.Root '.runtime\node\node.exe')
        NpmPath = (Join-Path `$Paths.Root '.runtime\node\npm.cmd')
        Source = 'path-node'
    }
}
function Invoke-DoctorPipCheck {
    param([string]`$PythonPath, [string]`$BackendRoot)
    [pscustomobject]@{
        ExitCode = 0
        Message = 'pip check passed'
    }
}
function Get-DoctorTorchInfo {
    param([string]`$PythonPath)
    [pscustomobject]@{
        Version = '2.7.1+cu128'
        CudaBuild = '12.8'
        CudaAvailable = `$true
    }
}
`$result = Invoke-DoctorMain -ProjectRoot '$escapedFixture' -Device auto
`$compute = @(`$result.Results | Where-Object { `$_.name -eq 'compute-device' })[0]
[ordered]@{
    ExitCode = `$result.ExitCode
    Name = `$compute.name
    Status = `$compute.status
    Message = `$compute.message
} | ConvertTo-Json -Compress
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected 0 -Actual $state.ExitCode -Message "Auto mode with CUDA available should pass."
                    Assert-Equal -Expected "compute-device" -Actual $state.Name -Message "Compute-device result name mismatch."
                    Assert-Equal -Expected "PASS" -Actual $state.Status -Message "Compute-device result should PASS."
                    Assert-Contains -ExpectedSubstring "gpu" -Actual $state.Message.ToLowerInvariant() -Message "Compute-device message should resolve to GPU."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor auto mode emits a compute-device result resolved to cpu when CUDA is unavailable"
            Body = {
                $fixture = New-DoctorFixture
                try {
                    $doctorScriptPath = (Get-DoctorScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$doctorScriptPath'
function Get-DoctorSystemFacts {
    param([string]`$ProjectRoot)
    [pscustomobject]@{
        IsWindows = `$true
        Architecture = 'x64'
        FreeSpaceBytes = 20GB
    }
}
function Get-DoctorPythonInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '3.10.11'
        Path = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe')
        Source = 'backend-venv'
    }
}
function Get-DoctorNodeInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '24.18.0'
        Path = (Join-Path `$Paths.Root '.runtime\node\node.exe')
        NpmPath = (Join-Path `$Paths.Root '.runtime\node\npm.cmd')
        Source = 'path-node'
    }
}
function Invoke-DoctorPipCheck {
    param([string]`$PythonPath, [string]`$BackendRoot)
    [pscustomobject]@{
        ExitCode = 0
        Message = 'pip check passed'
    }
}
function Get-DoctorTorchInfo {
    param([string]`$PythonPath)
    [pscustomobject]@{
        Version = '2.7.1+cpu'
        CudaBuild = `$null
        CudaAvailable = `$false
    }
}
`$result = Invoke-DoctorMain -ProjectRoot '$escapedFixture' -Device auto
`$compute = @(`$result.Results | Where-Object { `$_.name -eq 'compute-device' })[0]
[ordered]@{
    ExitCode = `$result.ExitCode
    Name = `$compute.name
    Status = `$compute.status
    Message = `$compute.message
} | ConvertTo-Json -Compress
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected 0 -Actual $state.ExitCode -Message "Auto mode with CUDA unavailable should pass."
                    Assert-Equal -Expected "compute-device" -Actual $state.Name -Message "Compute-device result name mismatch."
                    Assert-Equal -Expected "PASS" -Actual $state.Status -Message "Compute-device result should PASS."
                    Assert-Contains -ExpectedSubstring "cpu" -Actual $state.Message.ToLowerInvariant() -Message "Compute-device message should resolve to CPU."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor rejects a project-local Python runtime routed through a junction before execution"
            Body = {
                $fixture = New-DoctorFixture
                $external = New-TempFixture
                try {
                    $runtimeRoot = Join-Path $fixture ".runtime"
                    $pythonLink = Join-Path $runtimeRoot "python"
                    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
                    New-Item -ItemType Directory -Path $external -Force | Out-Null
                    [System.IO.File]::WriteAllText((Join-Path $external "python.exe"), "external-python", [System.Text.Encoding]::ASCII)
                    New-Item -ItemType Junction -Path $pythonLink -Target $external | Out-Null
                    Assert-TestRequiresJunction -Path $pythonLink

                    $doctorScriptPath = (Get-DoctorScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$doctorScriptPath'
function Get-DoctorExactPythonVersion {
    param([string]`$PythonPath, [string]`$ProjectRoot)
    throw 'python-version-executed'
}
function Get-DoctorNodeInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '24.18.0'
        Path = (Join-Path `$Paths.Root '.runtime\node\node.exe')
        NpmPath = (Join-Path `$Paths.Root '.runtime\node\npm.cmd')
        Source = 'path-node'
    }
}
`$result = Invoke-DoctorMain -ProjectRoot '$escapedFixture' -Device auto
`$python = @(`$result.Results | Where-Object { `$_.name -eq 'python-version' })[0]
[ordered]@{
    Status = `$python.status
    Message = `$python.message
    Executed = `$python.message.Contains('python-version-executed')
} | ConvertTo-Json -Compress
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected "FAIL" -Actual $state.Status -Message "Project-local Python junction should FAIL."
                    Assert-Contains -ExpectedSubstring "reparse point" -Actual $state.Message.ToLowerInvariant() -Message "Project-local Python junction failure should mention reparse points."
                    Assert-False -Condition $state.Executed -Message "Project-local Python junction must fail before executing Python."
                } finally {
                    Remove-TempFixture -Path $external
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor rejects a project-local Node runtime routed through a junction before execution"
            Body = {
                $fixture = New-DoctorFixture
                $external = New-TempFixture
                try {
                    $runtimeRoot = Join-Path $fixture ".runtime"
                    $nodeLink = Join-Path $runtimeRoot "node"
                    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
                    New-Item -ItemType Directory -Path $external -Force | Out-Null
                    [System.IO.File]::WriteAllText((Join-Path $external "node.exe"), "external-node", [System.Text.Encoding]::ASCII)
                    [System.IO.File]::WriteAllText((Join-Path $external "npm.cmd"), "@echo npm", [System.Text.Encoding]::ASCII)
                    New-Item -ItemType Junction -Path $nodeLink -Target $external | Out-Null
                    Assert-TestRequiresJunction -Path $nodeLink

                    $doctorScriptPath = (Get-DoctorScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$doctorScriptPath'
function Get-DoctorPythonInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '3.10.11'
        Path = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe')
        Source = 'backend-venv'
    }
}
function Invoke-DoctorPipCheck {
    param([string]`$PythonPath, [string]`$BackendRoot)
    [pscustomobject]@{
        ExitCode = 0
        Message = 'pip check passed'
    }
}
function Get-DoctorTorchInfo {
    param([string]`$PythonPath)
    [pscustomobject]@{
        Version = '2.7.1+cpu'
        CudaBuild = `$null
        CudaAvailable = `$false
    }
}
function Get-DoctorExactNodeVersion {
    param([string]`$NodePath, [string]`$ProjectRoot)
    throw 'node-version-executed'
}
`$result = Invoke-DoctorMain -ProjectRoot '$escapedFixture' -Device auto
`$node = @(`$result.Results | Where-Object { `$_.name -eq 'node-version' })[0]
[ordered]@{
    Status = `$node.status
    Message = `$node.message
    Executed = `$node.message.Contains('node-version-executed')
} | ConvertTo-Json -Compress
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected "FAIL" -Actual $state.Status -Message "Project-local Node junction should FAIL."
                    Assert-Contains -ExpectedSubstring "reparse point" -Actual $state.Message.ToLowerInvariant() -Message "Project-local Node junction failure should mention reparse points."
                    Assert-False -Condition $state.Executed -Message "Project-local Node junction must fail before executing Node."
                } finally {
                    Remove-TempFixture -Path $external
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor rejects an external PATH Node executable leaf reparse point before execution without applying project containment"
            Body = {
                $fixture = New-DoctorFixture
                try {
                    $doctorScriptPath = (Get-DoctorScriptPath).Replace("'", "''")
                    $escapedFixture = $fixture.Replace("'", "''")
                    $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$doctorScriptPath'
`$projectRoot = '$escapedFixture'
`$fakeNodePath = 'C:\external\node.exe'
`$fakeNpmPath = 'C:\external\npm.cmd'
function Get-Command {
    param([string]`$Name)
    if (`$Name -eq 'node.exe') {
        return [pscustomobject]@{ Source = `$fakeNodePath }
    }

    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
}
function Test-Path {
    param([string]`$LiteralPath, [string]`$PathType)
    switch (`$LiteralPath) {
        `$fakeNodePath { return `$true }
        `$fakeNpmPath { return `$true }
        default { return Microsoft.PowerShell.Management\Test-Path @PSBoundParameters }
    }
}
function Get-Item {
    param([string]`$LiteralPath, [switch]`$Force, [string]`$ErrorAction)
    if (`$LiteralPath -eq `$fakeNodePath) {
        return [pscustomobject]@{ Attributes = [System.IO.FileAttributes]::ReparsePoint }
    }

    Microsoft.PowerShell.Management\Get-Item @PSBoundParameters
}
function Invoke-CheckedCommand {
    param([string]`$FilePath, [string[]]`$ArgumentList)
    throw 'node-version-executed'
}
`$paths = [pscustomobject]@{
    Root = `$projectRoot
    LocalNodePath = (Join-Path `$projectRoot '.runtime\node\node.exe')
    LocalNpmPath = (Join-Path `$projectRoot '.runtime\node\npm.cmd')
}
`$manifest = [pscustomobject]@{
    runtime = [pscustomobject]@{
        node = [pscustomobject]@{ version = '24.18.0' }
    }
}
try {
    Get-DoctorNodeInfo -Paths `$paths -Manifest `$manifest | Out-Null
    throw 'Expected external PATH node reparse rejection.'
} catch {
    [ordered]@{
        Message = `$_.Exception.Message
        Executed = `$_.Exception.Message.Contains('node-version-executed')
        Containment = `$_.Exception.Message.Contains('project root')
    } | ConvertTo-Json -Compress
}
"@
                    $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                    $state = $result.StdOut | ConvertFrom-Json
                    Assert-Contains -ExpectedSubstring "reparse point" -Actual $state.Message.ToLowerInvariant() -Message "External PATH node reparse rejection should mention reparse points."
                    Assert-False -Condition $state.Executed -Message "External PATH node reparse rejection must occur before execution."
                    Assert-False -Condition $state.Containment -Message "External PATH node reparse rejection must not use project containment messaging."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor Json mode converts early fatal setup errors into one safe FAIL result with empty stderr"
            Body = {
                $fixture = New-DoctorFixture
                try {
                    Set-Content -LiteralPath (Join-Path $fixture "scripts\config\bootstrap-manifest.json") -Value "{not-json" -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $fixture "backend\.env") -Value @(
                        "APP_MODE=local",
                        "DATABASE_URL=sqlite:///./data/local.db",
                        "JWT_SECRET_KEY=super-secret-fixture-value"
                    ) -Encoding ASCII

                    $result = Invoke-DoctorScriptProcess -ProjectRoot $fixture -ArgumentList @("-Json")
                    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message "Doctor Json mode should return nonzero for early fatal setup errors."
                    Assert-Equal -Expected "" -Actual $result.StdErr.Trim() -Message "Doctor Json mode should keep stderr empty for handled setup errors."

                    $json = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected 1 -Actual @($json).Count -Message "Doctor Json mode should emit exactly one normalized setup result."
                    Assert-Equal -Expected "FAIL" -Actual $json[0].status -Message "Doctor Json mode setup result should FAIL."
                    Assert-True -Condition ([bool]$json[0].required) -Message "Doctor Json mode setup result should be required."
                    Assert-Contains -ExpectedSubstring "manifest" -Actual ([string]$json[0].message).ToLowerInvariant() -Message "Doctor Json mode setup result should explain the manifest failure."
                    Assert-False -Condition (($result.StdOut + $result.StdErr).Contains("super-secret-fixture-value")) -Message "Doctor Json mode setup failure leaked a secret."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor Json mode normalizes invalid Device into one safe FAIL result with empty stderr"
            Body = {
                $fixture = New-DoctorFixture
                try {
                    $result = Invoke-DoctorScriptProcess -ProjectRoot $fixture -ArgumentList @("-Json", "-Device", "bogus")
                    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message "Doctor Json mode should return nonzero for invalid Device."
                    Assert-Equal -Expected "" -Actual $result.StdErr.Trim() -Message "Doctor Json invalid Device should keep stderr empty."

                    $json = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected 1 -Actual @($json).Count -Message "Doctor Json invalid Device should emit exactly one normalized result."
                    Assert-Equal -Expected "FAIL" -Actual $json[0].status -Message "Doctor Json invalid Device result should FAIL."
                    Assert-True -Condition ([bool]$json[0].required) -Message "Doctor Json invalid Device result should be required."
                    Assert-Contains -ExpectedSubstring "device" -Actual ([string]$json[0].message).ToLowerInvariant() -Message "Doctor Json invalid Device should mention the device category."
                    Assert-False -Condition (($result.StdOut + $result.StdErr).Contains("super-secret-fixture-value")) -Message "Doctor Json invalid Device leaked a secret."
                } finally {
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor Json mode normalizes a missing ProjectEnvironment module into one safe FAIL result with empty stderr"
            Body = {
                $fixture = New-DoctorFixture
                $doctorRoot = Split-Path -Parent (Get-DoctorScriptPath)
                $modulePath = Join-Path $doctorRoot "lib\ProjectEnvironment.psm1"
                $backupPath = $modulePath + ".json-test-backup"
                try {
                    Move-Item -LiteralPath $modulePath -Destination $backupPath -Force
                    $result = Invoke-DoctorScriptProcess -ProjectRoot $fixture -ArgumentList @("-Json")
                    Assert-Equal -Expected 1 -Actual $result.ExitCode -Message "Doctor Json mode should return nonzero when ProjectEnvironment is missing."
                    Assert-Equal -Expected "" -Actual $result.StdErr.Trim() -Message "Doctor Json missing-module path should keep stderr empty."

                    $json = $result.StdOut | ConvertFrom-Json
                    Assert-Equal -Expected 1 -Actual @($json).Count -Message "Doctor Json missing-module path should emit exactly one normalized result."
                    Assert-Equal -Expected "FAIL" -Actual $json[0].status -Message "Doctor Json missing-module result should FAIL."
                    Assert-True -Condition ([bool]$json[0].required) -Message "Doctor Json missing-module result should be required."
                    Assert-Contains -ExpectedSubstring "module" -Actual ([string]$json[0].message).ToLowerInvariant() -Message "Doctor Json missing-module result should mention the module category."
                    Assert-False -Condition (($result.StdOut + $result.StdErr).Contains("super-secret-fixture-value")) -Message "Doctor Json missing-module path leaked a secret."
                } finally {
                    if (Test-Path -LiteralPath $backupPath) {
                        Move-Item -LiteralPath $backupPath -Destination $modulePath -Force
                    }
                    Remove-TempFixture -Path $fixture
                }
            }
        },
        @{
            Name = "Doctor sanitizes secret-bearing probe seam failures in human and JSON output"
            Body = {
                $secret = "SENTINEL-SECRET-DOCTOR"
                $cases = @(
                    [pscustomobject]@{
                        Name = "python"
                        Script = @"
function Get-DoctorPythonInfo {
    param([object]`$Paths, [object]`$Manifest)
    throw 'python probe failed: SENTINEL-SECRET-DOCTOR'
}
function Get-DoctorNodeInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '24.18.0'
        Path = (Join-Path `$Paths.Root '.runtime\node\node.exe')
        NpmPath = (Join-Path `$Paths.Root '.runtime\node\npm.cmd')
        Source = 'path-node'
    }
}
"@
                    },
                    [pscustomobject]@{
                        Name = "node"
                        Script = @"
function Get-DoctorPythonInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '3.10.11'
        Path = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe')
        Source = 'backend-venv'
    }
}
function Get-DoctorNodeInfo {
    param([object]`$Paths, [object]`$Manifest)
    throw 'node probe failed: SENTINEL-SECRET-DOCTOR'
}
function Invoke-DoctorPipCheck {
    param([string]`$PythonPath, [string]`$BackendRoot)
    [pscustomobject]@{ ExitCode = 0; Message = 'pip check passed' }
}
function Get-DoctorTorchInfo {
    param([string]`$PythonPath)
    [pscustomobject]@{ Version = '2.7.1+cpu'; CudaBuild = `$null; CudaAvailable = `$false }
}
"@
                    },
                    [pscustomobject]@{
                        Name = "pip"
                        Script = @"
function Get-DoctorPythonInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '3.10.11'
        Path = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe')
        Source = 'backend-venv'
    }
}
function Get-DoctorNodeInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '24.18.0'
        Path = (Join-Path `$Paths.Root '.runtime\node\node.exe')
        NpmPath = (Join-Path `$Paths.Root '.runtime\node\npm.cmd')
        Source = 'path-node'
    }
}
function Invoke-DoctorPipCheck {
    param([string]`$PythonPath, [string]`$BackendRoot)
    throw 'pip probe failed: SENTINEL-SECRET-DOCTOR'
}
function Get-DoctorTorchInfo {
    param([string]`$PythonPath)
    [pscustomobject]@{ Version = '2.7.1+cpu'; CudaBuild = `$null; CudaAvailable = `$false }
}
"@
                    },
                    [pscustomobject]@{
                        Name = "torch"
                        Script = @"
function Get-DoctorPythonInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '3.10.11'
        Path = (Join-Path `$Paths.VenvRoot 'Scripts\python.exe')
        Source = 'backend-venv'
    }
}
function Get-DoctorNodeInfo {
    param([object]`$Paths, [object]`$Manifest)
    [pscustomobject]@{
        Version = '24.18.0'
        Path = (Join-Path `$Paths.Root '.runtime\node\node.exe')
        NpmPath = (Join-Path `$Paths.Root '.runtime\node\npm.cmd')
        Source = 'path-node'
    }
}
function Invoke-DoctorPipCheck {
    param([string]`$PythonPath, [string]`$BackendRoot)
    [pscustomobject]@{ ExitCode = 0; Message = 'pip check passed' }
}
function Get-DoctorTorchInfo {
    param([string]`$PythonPath)
    throw 'torch probe failed: SENTINEL-SECRET-DOCTOR'
}
"@
                    }
                )

                foreach ($case in $cases) {
                    $fixture = New-DoctorFixture
                    try {
                        $doctorScriptPath = (Get-DoctorScriptPath).Replace("'", "''")
                        $escapedFixture = $fixture.Replace("'", "''")
                        $childScript = @"
`$ErrorActionPreference = 'Stop'
. '$doctorScriptPath'
function Get-DoctorSystemFacts {
    param([string]`$ProjectRoot)
    [pscustomobject]@{
        IsWindows = `$true
        Architecture = 'x64'
        FreeSpaceBytes = 20GB
    }
}
$($case.Script)
`$result = Invoke-DoctorMain -ProjectRoot '$escapedFixture' -Device auto
[ordered]@{
    Human = (Format-DoctorHumanOutput -Results `$result.Results)
    Json = (Format-DoctorJsonOutput -Results `$result.Results)
} | ConvertTo-Json -Compress
"@
                        $result = Invoke-BootstrapChildScript -ScriptContent $childScript -WorkingDirectory $fixture
                        $state = $result.StdOut | ConvertFrom-Json
                        Assert-False -Condition ($state.Human.Contains($secret)) -Message "Doctor human output leaked a secret for $($case.Name) seam."
                        Assert-False -Condition ($state.Json.Contains($secret)) -Message "Doctor JSON output leaked a secret for $($case.Name) seam."
                    } finally {
                        Remove-TempFixture -Path $fixture
                    }
                }
            }
        }
    )
}

function Invoke-BootstrapScriptTests {
    $tests = Get-BootstrapScriptTests
    $results = @()

    foreach ($test in $tests) {
        try {
            & $test.Body
            $results += [pscustomobject]@{
                Name = $test.Name
                Passed = $true
                Error = $null
            }
        } catch {
            $results += [pscustomobject]@{
                Name = $test.Name
                Passed = $false
                Error = $_.Exception.Message
            }
        }
    }

    $passed = @($results | Where-Object { $_.Passed }).Count
    $failed = @($results | Where-Object { -not $_.Passed }).Count

    return [pscustomobject]@{
        Total = $results.Count
        Passed = $passed
        Failed = $failed
        Results = $results
    }
}
