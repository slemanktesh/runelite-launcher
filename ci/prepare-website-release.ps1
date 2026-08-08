[CmdletBinding()]
param(
    [string] $ArtifactsDirectory,

    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory,

    [string] $BuildFile,

    [switch] $ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

if ([string]::IsNullOrWhiteSpace($BuildFile))
{
    $BuildFile = Join-Path $PSScriptRoot "..\build.gradle.kts"
}

$canonicalFileNames = @(
    "aleges-windows-x64.exe",
    "aleges-windows-x86.exe",
    "aleges-windows-arm64.exe",
    "aleges-linux-x64.AppImage",
    "aleges-linux-aarch64.AppImage",
    "aleges-client.jar",
    "aleges-macos-intel.dmg",
    "aleges-macos-apple-silicon.dmg",
    "aleges-macos-app.tar"
)

$updateTargets = @(
    [pscustomobject]@{ Os = "windows"; Arch = "amd64";  Platform = "windows-x64";           Canonical = "aleges-windows-x64.exe";              Extension = ".exe" },
    [pscustomobject]@{ Os = "windows"; Arch = "x86";    Platform = "windows-x86";           Canonical = "aleges-windows-x86.exe";              Extension = ".exe" },
    [pscustomobject]@{ Os = "windows"; Arch = "aarch64"; Platform = "windows-arm64";         Canonical = "aleges-windows-arm64.exe";            Extension = ".exe" },
    [pscustomobject]@{ Os = "linux";   Arch = "amd64";  Platform = "linux-x64";             Canonical = "aleges-linux-x64.AppImage";           Extension = ".AppImage" },
    [pscustomobject]@{ Os = "linux";   Arch = "aarch64"; Platform = "linux-aarch64";         Canonical = "aleges-linux-aarch64.AppImage";       Extension = ".AppImage" },
    [pscustomobject]@{ Os = "macos";   Arch = "x86_64"; Platform = "macos-intel";           Canonical = "aleges-macos-intel.dmg";              Extension = ".dmg" },
    [pscustomobject]@{ Os = "macos";   Arch = "aarch64"; Platform = "macos-apple-silicon";   Canonical = "aleges-macos-apple-silicon.dmg";      Extension = ".dmg" }
)

function Get-LauncherVersion
{
    param([Parameter(Mandatory = $true)][string] $Path)

    if (!(Test-Path -LiteralPath $Path -PathType Leaf))
    {
        throw "Build file does not exist: $Path"
    }

    $matches = [regex]::Matches(
        [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path),
        '(?m)^\s*version\s*=\s*"([^"]+)"\s*$')

    if ($matches.Count -ne 1)
    {
        throw "Expected exactly one launcher version assignment in $Path; found $($matches.Count)."
    }

    $version = $matches[0].Groups[1].Value
    if ($version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$')
    {
        throw "Launcher version '$version' is not safe for an immutable filename and URL."
    }

    return $version
}

function Get-LowercaseSha256
{
    param([Parameter(Mandatory = $true)][string] $Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ImmutableFileName
{
    param(
        [Parameter(Mandatory = $true)] $Target,
        [Parameter(Mandatory = $true)][string] $Version
    )

    return "aleges-launcher-$Version-$($Target.Platform)$($Target.Extension)"
}

function Assert-LauncherJarBranding
{
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Version
    )

    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try
    {
        $propertiesEntryName = "net/runelite/launcher/launcher.properties"
        $propertiesEntries = @($zip.Entries | Where-Object { $_.FullName -ceq $propertiesEntryName })
        if ($propertiesEntries.Count -ne 1)
        {
            throw "Expected one $propertiesEntryName entry in aleges-client.jar; found $($propertiesEntries.Count)."
        }

        $reader = [IO.StreamReader]::new($propertiesEntries[0].Open(), [Text.Encoding]::UTF8, $true)
        try
        {
            $propertiesText = $reader.ReadToEnd()
        }
        finally
        {
            $reader.Dispose()
        }

        $expectedProperties = [ordered]@{
            "runelite.launcher.version" = $Version
            "runelite.bootstrap" = "https://aleges.com/integration/bootstrap.json"
            "runelite.download.link" = "https://aleges.com/"
            "runelite.128" = "runelite_128.png"
            "runelite.splash" = "runelite_splash.png"
        }

        $propertyLines = @($propertiesText -split "\r?\n")
        foreach ($key in $expectedProperties.Keys)
        {
            $prefix = "$key="
            $matchingLines = @($propertyLines | Where-Object { $_.StartsWith($prefix, [StringComparison]::Ordinal) })
            if ($matchingLines.Count -ne 1)
            {
                throw "Expected one $key property in aleges-client.jar; found $($matchingLines.Count)."
            }

            $actualValue = $matchingLines[0].Substring($prefix.Length)
            $expectedValue = $expectedProperties[$key]
            if ($actualValue -cne $expectedValue)
            {
                throw "Invalid $key in aleges-client.jar: expected '$expectedValue', got '$actualValue'."
            }
        }

        foreach ($assetName in @($expectedProperties["runelite.128"], $expectedProperties["runelite.splash"]))
        {
            $entryName = "net/runelite/launcher/$assetName"
            $assetEntries = @($zip.Entries | Where-Object { $_.FullName -ceq $entryName })
            if ($assetEntries.Count -ne 1)
            {
                throw "Expected one Aleges launcher asset $entryName; found $($assetEntries.Count)."
            }

            if ($assetEntries[0].Length -le 0)
            {
                throw "Aleges launcher asset is empty: $entryName"
            }
        }
    }
    finally
    {
        $zip.Dispose()
    }
}

function Assert-Release
{
    param(
        [Parameter(Mandatory = $true)][string] $Directory,
        [Parameter(Mandatory = $true)][string] $Version
    )

    if (!(Test-Path -LiteralPath $Directory -PathType Container))
    {
        throw "Release directory does not exist: $Directory"
    }

    $downloadsDirectory = Join-Path $Directory "downloads"
    if (!(Test-Path -LiteralPath $downloadsDirectory -PathType Container))
    {
        throw "Release downloads directory does not exist: $downloadsDirectory"
    }

    $rootItems = @(Get-ChildItem -LiteralPath $Directory -Force)
    $expectedRootItems = @(
        [pscustomobject]@{ Name = "downloads"; IsDirectory = $true },
        [pscustomobject]@{ Name = "aleges-launcher-updates.json"; IsDirectory = $false }
    )
    if ($rootItems.Count -ne $expectedRootItems.Count)
    {
        throw "Release root must contain only downloads and aleges-launcher-updates.json."
    }

    foreach ($expectedRootItem in $expectedRootItems)
    {
        $matchingRootItems = @($rootItems | Where-Object {
            $_.Name -ceq $expectedRootItem.Name -and $_.PSIsContainer -eq $expectedRootItem.IsDirectory
        })
        if ($matchingRootItems.Count -ne 1)
        {
            throw "Release root item is missing or has the wrong type: $($expectedRootItem.Name)"
        }
    }

    $expectedDownloadFileNames = @($canonicalFileNames)
    foreach ($target in $updateTargets)
    {
        $expectedDownloadFileNames += Get-ImmutableFileName -Target $target -Version $Version
    }

    $downloadItems = @(Get-ChildItem -LiteralPath $downloadsDirectory -Force)
    if ($downloadItems.Count -ne $expectedDownloadFileNames.Count)
    {
        throw "Release downloads directory must contain exactly $($expectedDownloadFileNames.Count) files; found $($downloadItems.Count)."
    }

    foreach ($expectedFileName in $expectedDownloadFileNames)
    {
        $matchingDownloadItems = @($downloadItems | Where-Object {
            $_.Name -ceq $expectedFileName -and !$_.PSIsContainer
        })
        if ($matchingDownloadItems.Count -ne 1)
        {
            throw "Release download is missing or has the wrong type: $expectedFileName"
        }
    }

    foreach ($fileName in $canonicalFileNames)
    {
        $path = Join-Path $downloadsDirectory $fileName
        if (!(Test-Path -LiteralPath $path -PathType Leaf))
        {
            throw "Canonical website file is missing: $fileName"
        }

        if ((Get-Item -LiteralPath $path).Length -le 0)
        {
            throw "Canonical website file is empty: $fileName"
        }
    }

    Assert-LauncherJarBranding -Path (Join-Path $downloadsDirectory "aleges-client.jar") -Version $Version

    $manifestPath = Join-Path $Directory "aleges-launcher-updates.json"
    if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf))
    {
        throw "Launcher update manifest is missing: $manifestPath"
    }

    $parsedUpdates = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $updates = @($parsedUpdates | ForEach-Object { $_ })
    if ($updates.Count -ne $updateTargets.Count)
    {
        throw "Expected $($updateTargets.Count) launcher update entries; found $($updates.Count)."
    }

    $expectedProperties = @(
        "arch",
        "hash",
        "minimumVersion",
        "name",
        "os",
        "rollout",
        "size",
        "url",
        "version"
    ) | Sort-Object

    foreach ($target in $updateTargets)
    {
        $immutableName = Get-ImmutableFileName -Target $target -Version $Version
        $immutablePath = Join-Path $downloadsDirectory $immutableName
        $canonicalPath = Join-Path $downloadsDirectory $target.Canonical

        if (!(Test-Path -LiteralPath $immutablePath -PathType Leaf))
        {
            throw "Immutable launcher update file is missing: $immutableName"
        }

        $immutableItem = Get-Item -LiteralPath $immutablePath
        $immutableHash = Get-LowercaseSha256 -Path $immutablePath
        $canonicalHash = Get-LowercaseSha256 -Path $canonicalPath
        if ($immutableItem.Length -ne (Get-Item -LiteralPath $canonicalPath).Length -or $immutableHash -ne $canonicalHash)
        {
            throw "Immutable file does not match its canonical source: $immutableName"
        }

        $matchingUpdates = @($updates | Where-Object { $_.os -eq $target.Os -and $_.arch -eq $target.Arch })
        if ($matchingUpdates.Count -ne 1)
        {
            throw "Expected one update selector for $($target.Os)/$($target.Arch); found $($matchingUpdates.Count)."
        }

        $update = $matchingUpdates[0]
        $actualProperties = @($update.PSObject.Properties.Name) | Sort-Object
        if (($actualProperties -join "\n") -ne ($expectedProperties -join "\n"))
        {
            throw "Update entry for $($target.Os)/$($target.Arch) does not have the exact Update property set."
        }

        $expectedUrl = "https://aleges.com/downloads/$immutableName"
        if ($update.name -ne $immutableName -or
            $update.version -ne $Version -or
            $update.minimumVersion -ne "2.6.0" -or
            $update.url -ne $expectedUrl -or
            $update.hash -cne $immutableHash -or
            [int64] $update.size -ne $immutableItem.Length -or
            [double] $update.rollout -ne 1)
        {
            throw "Update metadata does not match the immutable file for $($target.Os)/$($target.Arch)."
        }
    }

    $selectorCount = @($updates | ForEach-Object { "$($_.os)/$($_.arch)" } | Sort-Object -Unique).Count
    $nameCount = @($updates.name | Sort-Object -Unique).Count
    $urlCount = @($updates.url | Sort-Object -Unique).Count
    if ($selectorCount -ne $updateTargets.Count -or $nameCount -ne $updateTargets.Count -or $urlCount -ne $updateTargets.Count)
    {
        throw "Launcher update selectors, names, and URLs must all be unique."
    }
}

$launcherVersion = Get-LauncherVersion -Path $BuildFile
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)

if (!$ValidateOnly)
{
    if ([string]::IsNullOrWhiteSpace($ArtifactsDirectory))
    {
        throw "ArtifactsDirectory is required unless ValidateOnly is set."
    }

    $artifactsPath = [IO.Path]::GetFullPath($ArtifactsDirectory)
    if (!(Test-Path -LiteralPath $artifactsPath -PathType Container))
    {
        throw "Downloaded artifact directory does not exist: $artifactsPath"
    }

    if (Test-Path -LiteralPath $outputPath)
    {
        if (@(Get-ChildItem -LiteralPath $outputPath -Force).Count -ne 0)
        {
            throw "Output directory must be empty: $outputPath"
        }
    }
    else
    {
        New-Item -ItemType Directory -Path $outputPath | Out-Null
    }

    $downloadsPath = Join-Path $outputPath "downloads"
    New-Item -ItemType Directory -Path $downloadsPath | Out-Null

    foreach ($fileName in $canonicalFileNames)
    {
        $sourcePath = Join-Path $artifactsPath $fileName
        if (!(Test-Path -LiteralPath $sourcePath -PathType Leaf))
        {
            throw "Downloaded website artifact is missing: $fileName"
        }

        if ((Get-Item -LiteralPath $sourcePath).Length -le 0)
        {
            throw "Downloaded website artifact is empty: $fileName"
        }

        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $downloadsPath $fileName)
    }

    $updates = @()
    foreach ($target in $updateTargets)
    {
        $canonicalPath = Join-Path $downloadsPath $target.Canonical
        $immutableName = Get-ImmutableFileName -Target $target -Version $launcherVersion
        $immutablePath = Join-Path $downloadsPath $immutableName
        Copy-Item -LiteralPath $canonicalPath -Destination $immutablePath

        $immutableItem = Get-Item -LiteralPath $immutablePath
        if ($immutableItem.Length -gt [int]::MaxValue)
        {
            throw "Update file exceeds the launcher's integer size field: $immutableName"
        }

        $updates += [pscustomobject][ordered]@{
            os = $target.Os
            arch = $target.Arch
            name = $immutableName
            version = $launcherVersion
            minimumVersion = "2.6.0"
            url = "https://aleges.com/downloads/$immutableName"
            hash = Get-LowercaseSha256 -Path $immutablePath
            size = [int64] $immutableItem.Length
            rollout = 1
        }
    }

    $manifestPath = Join-Path $outputPath "aleges-launcher-updates.json"
    $manifestJson = ConvertTo-Json -InputObject $updates -Depth 4
    [IO.File]::WriteAllText(
        $manifestPath,
        $manifestJson + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false))
}

Assert-Release -Directory $outputPath -Version $launcherVersion
Write-Host "Validated Aleges website release $launcherVersion in $outputPath"
