Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-RequiredManifestValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $value = Get-ObjectPropertyValue -Object $Object -Name $Name
    if ($null -eq $value) {
        throw "Missing required bootstrap manifest field: $Context.$Name"
    }

    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required bootstrap manifest field: $Context.$Name"
    }

    return $value
}

function Get-RequiredManifestString {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $value = Get-RequiredManifestValue -Object $Object -Name $Name -Context $Context
    if (-not ($value -is [string])) {
        throw "Invalid bootstrap manifest field: $Context.$Name must be a string."
    }

    return $value
}

function Assert-LeafFilename {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $isDotSegment = $Value -eq "." -or $Value -eq ".."
    $hasInvalidCharacter = $Value.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0
    $normalizedValue = $Value.TrimEnd([char[]]@(" ", "."))
    $extensionIndex = $normalizedValue.IndexOf(".")
    $baseName = if ($extensionIndex -ge 0) {
        $normalizedValue.Substring(0, $extensionIndex)
    } else {
        $normalizedValue
    }
    $normalizedBaseName = $baseName.TrimEnd().ToUpperInvariant()
    $isReservedDeviceName = $normalizedBaseName -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'

    if ($isDotSegment -or [System.IO.Path]::IsPathRooted($Value) -or $hasInvalidCharacter -or $isReservedDeviceName) {
        throw "Invalid bootstrap manifest field: $Context must be a leaf filename."
    }
}

function Assert-NumericDottedVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($Value -notmatch '^\d+(?:\.\d+)+$') {
        throw "Invalid bootstrap manifest field: $Context must be a numeric dotted version."
    }
}

function Assert-HttpsUrl {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $uri = $null
    if (-not [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri) -or
        -not $uri.Scheme.Equals("https", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Invalid bootstrap manifest field: $Context must be an HTTPS URL."
    }
}

function Assert-Sha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($Value -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "Invalid bootstrap manifest field: $Context must be exactly 64 hexadecimal characters."
    }
}

function Assert-PositiveInteger {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $integerTypes = @(
        [byte], [sbyte], [int16], [uint16], [int32], [uint32], [int64], [uint64]
    )
    if ($integerTypes -notcontains $Value.GetType() -or $Value -le 0) {
        throw "Invalid bootstrap manifest field: $Context must be a positive integer."
    }
}

function ConvertTo-VersionSegments {
    param([Parameter(Mandatory = $true)][string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) {
        throw "Version must not be empty."
    }

    $segments = @()
    foreach ($segment in $Version.Trim().Split(".")) {
        if ($segment -notmatch "^\d+$") {
            throw "Invalid version segment '$segment' in version '$Version'."
        }

        $segments += [int]$segment
    }

    return $segments
}

function ConvertTo-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath.Length -gt 3 -and ($fullPath.EndsWith("\") -or $fullPath.EndsWith("/"))) {
        return $fullPath.TrimEnd("\", "/")
    }

    return $fullPath
}

function Get-ProcessRecord {
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    $filter = "ProcessId = $ProcessId"

    try {
        return Get-CimInstance Win32_Process -Filter $filter -ErrorAction Stop
    } catch {
        try {
            return Get-WmiObject Win32_Process -Filter $filter -ErrorAction Stop
        } catch {
            return $null
        }
    }
}

function Get-IdentityValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property) {
            return $property.Value
        }
    }

    return $null
}

function ConvertTo-UtcDateTime {
    param([Parameter(Mandatory = $true)]$Value)

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime()
    }

    return ([datetime]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture)).ToUniversalTime()
}

function ConvertTo-WindowsCommandArgument {
    param([AllowNull()][string]$Argument)

    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashCount = 0

    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq "\") {
            $backslashCount++
            continue
        }

        if ($character -eq '"') {
            if ($backslashCount -gt 0) {
                [void]$builder.Append("\" * ($backslashCount * 2))
                $backslashCount = 0
            }

            [void]$builder.Append('\"')
            continue
        }

        if ($backslashCount -gt 0) {
            [void]$builder.Append("\" * $backslashCount)
            $backslashCount = 0
        }

        [void]$builder.Append($character)
    }

    if ($backslashCount -gt 0) {
        [void]$builder.Append("\" * ($backslashCount * 2))
    }

    [void]$builder.Append('"')
    return $builder.ToString()
}

function Test-KnownDeviceMode {
    param([Parameter(Mandatory = $true)][string]$Mode)

    return @("auto", "cpu", "gpu") -contains $Mode
}

function Get-ProjectRoot {
    return $script:ProjectRoot
}

function Read-BootstrapManifest {
    param(
        [string]$Path = (Join-Path (Get-ProjectRoot) "scripts\config\bootstrap-manifest.json")
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $manifest = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json

    $schemaVersion = Get-RequiredManifestValue -Object $manifest -Name "schemaVersion" -Context "manifest"
    if ([int]$schemaVersion -ne 1) {
        throw "Unsupported bootstrap manifest schemaVersion: $schemaVersion"
    }

    $runtime = Get-RequiredManifestValue -Object $manifest -Name "runtime" -Context "manifest"
    foreach ($runtimeName in @("python", "node")) {
        $runtimeRecord = Get-RequiredManifestValue -Object $runtime -Name $runtimeName -Context "runtime"
        $context = "runtime.$runtimeName"
        $version = Get-RequiredManifestString -Object $runtimeRecord -Name "version" -Context $context
        $filename = Get-RequiredManifestString -Object $runtimeRecord -Name "filename" -Context $context
        $url = Get-RequiredManifestString -Object $runtimeRecord -Name "url" -Context $context
        $sha256 = Get-RequiredManifestString -Object $runtimeRecord -Name "sha256" -Context $context
        Assert-LeafFilename -Value $filename -Context "$context.filename"
        Assert-NumericDottedVersion -Value $version -Context "$context.version"
        Assert-HttpsUrl -Value $url -Context "$context.url"
        Assert-Sha256 -Value $sha256 -Context "$context.sha256"
    }

    $release = Get-RequiredManifestValue -Object $manifest -Name "release" -Context "manifest"
    $repository = Get-RequiredManifestString -Object $release -Name "repository" -Context "release"
    $tag = Get-RequiredManifestString -Object $release -Name "tag" -Context "release"
    $models = Get-RequiredManifestValue -Object $release -Name "models" -Context "release"
    foreach ($model in @($models)) {
        $context = "release.models[]"
        $filename = Get-RequiredManifestString -Object $model -Name "filename" -Context $context
        $bytes = Get-RequiredManifestValue -Object $model -Name "bytes" -Context $context
        $sha256 = Get-RequiredManifestString -Object $model -Name "sha256" -Context $context
        $url = Get-RequiredManifestString -Object $model -Name "url" -Context $context
        foreach ($field in @("source", "license", "purpose")) {
            [void](Get-RequiredManifestString -Object $model -Name $field -Context $context)
        }

        Assert-LeafFilename -Value $filename -Context "$context.filename"
        Assert-PositiveInteger -Value $bytes -Context "$context.bytes"
        Assert-Sha256 -Value $sha256 -Context "$context.sha256"
        Assert-HttpsUrl -Value $url -Context "$context.url"
        $expectedUrl = "https://github.com/$repository/releases/download/$tag/$filename"
        if (-not $url.Equals($expectedUrl, [System.StringComparison]::Ordinal)) {
            throw "Invalid bootstrap manifest field: $context.url must equal '$expectedUrl'."
        }
    }

    return $manifest
}

function Compare-Version {
    param(
        [Parameter(Mandatory = $true)][string]$LeftVersion,
        [Parameter(Mandatory = $true)][string]$RightVersion
    )

    $leftSegments = ConvertTo-VersionSegments -Version $LeftVersion
    $rightSegments = ConvertTo-VersionSegments -Version $RightVersion
    $count = [Math]::Max($leftSegments.Count, $rightSegments.Count)

    for ($index = 0; $index -lt $count; $index++) {
        $left = if ($index -lt $leftSegments.Count) { $leftSegments[$index] } else { 0 }
        $right = if ($index -lt $rightSegments.Count) { $rightSegments[$index] } else { 0 }

        if ($left -gt $right) {
            return 1
        }

        if ($left -lt $right) {
            return -1
        }
    }

    return 0
}

function Test-VersionAtLeast {
    param(
        [Parameter(Mandatory = $true)][string]$ActualVersion,
        [Parameter(Mandatory = $true)][string]$MinimumVersion
    )

    return (Compare-Version -LeftVersion $ActualVersion -RightVersion $MinimumVersion) -ge 0
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $fileHash = Get-FileHash -Algorithm SHA256 -LiteralPath $Path -ErrorAction Stop
    } catch {
        throw "Unable to calculate SHA256 for '$Path': $($_.Exception.Message)"
    }

    return $fileHash.Hash.ToUpperInvariant()
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    $expected = $ExpectedSha256.Trim().ToUpperInvariant()
    $actual = Get-FileSha256 -Path $Path
    if ($expected -ne $actual) {
        throw "File SHA256 mismatch for '$Path'. Expected: $expected. Actual: $actual."
    }
}

function Resolve-DeviceMode {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedMode,
        [Parameter(Mandatory = $true)][bool]$HasNvidia
    )

    $mode = $RequestedMode.Trim().ToLowerInvariant()
    switch ($mode) {
        "cpu" { return "cpu" }
        "auto" { if ($HasNvidia) { return "gpu" } else { return "cpu" } }
        "gpu" {
            if (-not $HasNvidia) {
                throw "GPU mode requires Nvidia support."
            }

            return "gpu"
        }
        default {
            throw "Unsupported device mode: $RequestedMode"
        }
    }
}

function New-SecureToken {
    param([ValidateRange(1, 4096)][int]$ByteCount = 32)

    $bytes = New-Object byte[] $ByteCount
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }

    return ([System.BitConverter]::ToString($bytes)).Replace("-", "")
}

function New-LocalEnvContent {
    param(
        [Alias("Secret")]
        [Parameter(Mandatory = $true)][string]$JwtSecretKey,
        [Parameter(Mandatory = $true)][string]$YoloDevice,
        [Parameter(Mandatory = $true)][string]$GtsrbDevice
    )

    if ([string]::IsNullOrWhiteSpace($JwtSecretKey)) {
        throw "JwtSecretKey must not be empty."
    }

    $normalizedYoloDevice = $YoloDevice.Trim().ToLowerInvariant()
    $normalizedGtsrbDevice = $GtsrbDevice.Trim().ToLowerInvariant()
    if (-not (Test-KnownDeviceMode -Mode $normalizedYoloDevice)) {
        throw "Unsupported YOLO device mode: $YoloDevice"
    }

    if (-not (Test-KnownDeviceMode -Mode $normalizedGtsrbDevice)) {
        throw "Unsupported GTSRB device mode: $GtsrbDevice"
    }

    $lines = @(
        "APP_MODE=local",
        "DATABASE_URL=sqlite:///./data/local.db",
        "REDIS_ENABLED=false",
        "MINIO_ENABLED=false",
        "YOLO_MODEL_PATH=../models/tt100k-yolo11s-reference42.pt",
        "YOLO_DEVICE=$normalizedYoloDevice",
        "GTSRB_MODEL_PATH=../models/gtsrb-yolo11n-cls.pt",
        "GTSRB_DEVICE=$normalizedGtsrbDevice",
        "JWT_SECRET_KEY=$JwtSecretKey"
    )

    return ($lines -join "`r`n") + "`r`n"
}

function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $normalizedRoot = ConvertTo-NormalizedPath -Path $RootPath
    $candidatePath = $Path
    if (-not [System.IO.Path]::IsPathRooted($candidatePath)) {
        $candidatePath = Join-Path $normalizedRoot $candidatePath
    }

    $normalizedCandidate = ConvertTo-NormalizedPath -Path $candidatePath
    if ($normalizedCandidate.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $normalizedCandidate.StartsWith($normalizedRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ProjectProcessIdentity {
    param([int]$ProcessId = $PID)

    $process = Get-Process -Id $ProcessId -ErrorAction Stop
    $record = $null
    $executablePath = $null
    $commandLine = $null

    if ($ProcessId -eq $PID) {
        $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
        try {
            $executablePath = $currentProcess.MainModule.FileName
        } finally {
            $currentProcess.Dispose()
        }

        $commandLine = [System.Environment]::CommandLine
    } else {
        $record = Get-ProcessRecord -ProcessId $ProcessId
        if ($null -ne $record) {
            $executablePath = Get-IdentityValue -Object $record -Names @("ExecutablePath")
            $commandLine = Get-IdentityValue -Object $record -Names @("CommandLine")
        }
    }

    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        try {
            $executablePath = $process.Path
        } catch {
            try {
                $executablePath = $process.MainModule.FileName
            } catch {
                $executablePath = $null
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        throw "Unable to determine executable path for process $ProcessId."
    }

    return [pscustomobject]@{
        Pid = $process.Id
        ExecutablePath = $executablePath
        StartTimeUtc = $process.StartTime.ToUniversalTime()
        CommandLine = $commandLine
    }
}

function Test-ProjectProcessIdentity {
    param(
        [Parameter(Mandatory = $true)][psobject]$RecordedIdentity,
        [int]$ProcessId = $PID
    )

    $actualIdentity = Get-ProjectProcessIdentity -ProcessId $ProcessId

    $recordedPid = Get-IdentityValue -Object $RecordedIdentity -Names @("Pid", "PID", "ProcessId")
    if ($null -ne $recordedPid -and [int]$recordedPid -ne [int]$actualIdentity.Pid) {
        return $false
    }

    $recordedPath = Get-IdentityValue -Object $RecordedIdentity -Names @("ExecutablePath", "Path", "Executable")
    if (-not [string]::IsNullOrWhiteSpace($recordedPath)) {
        $normalizedRecordedPath = ConvertTo-NormalizedPath -Path $recordedPath
        $normalizedActualPath = ConvertTo-NormalizedPath -Path $actualIdentity.ExecutablePath
        if (-not $normalizedRecordedPath.Equals($normalizedActualPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    $recordedStartTime = Get-IdentityValue -Object $RecordedIdentity -Names @("StartTimeUtc", "StartTime", "StartedAtUtc")
    if ($null -ne $recordedStartTime) {
        $expectedStartTime = ConvertTo-UtcDateTime -Value $recordedStartTime
        if ($expectedStartTime -ne $actualIdentity.StartTimeUtc) {
            return $false
        }
    }

    $recordedCommandLine = Get-IdentityValue -Object $RecordedIdentity -Names @("CommandLine")
    if (-not [string]::IsNullOrWhiteSpace($recordedCommandLine)) {
        if (-not $recordedCommandLine.Equals($actualIdentity.CommandLine, [System.StringComparison]::Ordinal)) {
            return $false
        }
    }

    return $true
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = (Get-ProjectRoot),
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 30
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = (@($ArgumentList | ForEach-Object { ConvertTo-WindowsCommandArgument -Argument $_ }) -join " ")
    $startInfo.WorkingDirectory = $WorkingDirectory
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

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                }
            } catch {
            }

            [void]$process.WaitForExit(5000)
            try {
                [void]$stdoutTask.GetAwaiter().GetResult()
                [void]$stderrTask.GetAwaiter().GetResult()
            } catch {
            }

            throw "Process timed out after $TimeoutSeconds seconds: $FilePath $($startInfo.Arguments)"
        }

        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
    } finally {
        $process.Dispose()
    }

    $result = [pscustomobject]@{
        FilePath = $FilePath
        Arguments = $startInfo.Arguments
        ExitCode = $exitCode
        StdOut = $stdout
        StdErr = $stderr
    }

    if ($exitCode -ne 0) {
        $message = "Process exited with code $exitCode`: $FilePath $($startInfo.Arguments)"
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            $message += "`r`nSTDOUT:`r`n$stdout"
        }

        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            $message += "`r`nSTDERR:`r`n$stderr"
        }

        throw $message
    }

    return $result
}

Export-ModuleMember -Function @(
    "Get-ProjectRoot",
    "Read-BootstrapManifest",
    "Compare-Version",
    "Test-VersionAtLeast",
    "Get-FileSha256",
    "Assert-FileHash",
    "Resolve-DeviceMode",
    "New-SecureToken",
    "New-LocalEnvContent",
    "Test-PathInsideRoot",
    "Get-ProjectProcessIdentity",
    "Test-ProjectProcessIdentity",
    "Invoke-CheckedCommand"
)
