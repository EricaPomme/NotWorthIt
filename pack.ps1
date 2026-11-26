#Requires -Version 5.1

<#
.SYNOPSIS
    Packs NotWorthIt into a versioned distribution zip under dist\.

.DESCRIPTION
    Stages the addon payload into a single NotWorthIt\ wrapper folder (the
    installed layout) and compresses it to dist\NotWorthIt-<version>.zip,
    ready to upload to CurseForge or a GitHub release, or to extract
    straight into Interface\AddOns\ for an instant install.

    The version is read from the '## Version:' line of NotWorthIt.toc and
    the run fails loudly when it is missing or malformed. Staging happens
    in a temp directory that is always removed, and only the payload items
    are packaged: repo tooling, including this script, stays out of the
    archive.

.PARAMETER OutputPath
    Directory that receives the zip. Defaults to dist\ under the repository
    root; relative paths resolve against the repository root. Created when
    missing; an existing archive of the same name is overwritten.

.EXAMPLE
    .\pack.ps1

    Packs the current version into dist\NotWorthIt-<version>.zip.

.EXAMPLE
    .\pack.ps1 -WhatIf

    Dry run: prints the plan without staging, creating dist\, or writing
    the zip.

.EXAMPLE
    .\pack.ps1 -OutputPath C:\Temp\release

    Packs into an arbitrary output directory.
#>

[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The script reports colour-coded packaging status to the operator.')]
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Named constants - keep in sync with pack.sh (Portability contract).
$addonName = 'NotWorthIt'
$payloadItems = @('NotWorthIt.lua', 'NotWorthIt.toc', 'README.md', 'CHANGELOG.md')
$defaultOutputSubdir = 'dist'

# The script lives at the repository root, so $PSScriptRoot is the repo root.
$repoRoot = $PSScriptRoot

# Payload validation: fail with the full missing list before any output.
$missingItems = @()
foreach ($item in $payloadItems) {
    if (-not (Test-Path -LiteralPath (Join-Path -Path $repoRoot -ChildPath $item) -PathType Leaf)) {
        $missingItems += $item
    }
}
if ($missingItems.Count -gt 0) {
    throw (@"
pack: missing payload item(s) in ${repoRoot}:
$($missingItems -join "`n  ")

The archive needs every payload item listed above. Restore or regenerate
them, or update `$payloadItems in pack.ps1 (and pack.sh) if the payload
changed.
"@)
}

# Version source: the '## Version:' line of the .toc.
$tocPath = Join-Path -Path $repoRoot -ChildPath ($addonName + '.toc')
$versionMatch = Select-String -LiteralPath $tocPath -Pattern '^##\s*Version:\s*(.+?)\s*$' |
    Select-Object -First 1
if ($null -eq $versionMatch) {
    throw "pack: no '## Version:' line found in $tocPath."
}
$version = $versionMatch.Matches[0].Groups[1].Value
if ($version -notmatch '^[0-9A-Za-z.\-]+$') {
    throw "pack: unusable version '$version' in $tocPath."
}

# Destination: -OutputPath wins, else dist\ under the repo root.
if ($OutputPath) {
    if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        $destination = $OutputPath
    }
    else {
        $destination = Join-Path -Path $repoRoot -ChildPath $OutputPath
    }
}
else {
    $destination = Join-Path -Path $repoRoot -ChildPath $defaultOutputSubdir
}
$archivePath = Join-Path -Path $destination -ChildPath ($addonName + '-' + $version + '.zip')

# Single ShouldProcess gate before any mutation, so -WhatIf creates nothing
# anywhere: not the archive, not the output directory, not the staging tree.
if (-not $PSCmdlet.ShouldProcess($archivePath, "pack $addonName version $version (payload of $($payloadItems.Count) items)")) {
    return
}

$stagingRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ($addonName + '-pack-' + [System.IO.Path]::GetRandomFileName())
try {
    $stagedFolder = Join-Path -Path $stagingRoot -ChildPath $addonName
    New-Item -ItemType Directory -Path $stagedFolder -Force | Out-Null
    Write-Verbose "Staging payload into $stagedFolder"
    foreach ($item in $payloadItems) {
        Copy-Item -LiteralPath (Join-Path -Path $repoRoot -ChildPath $item) -Destination $stagedFolder -Force
    }
    $stagedFileCount = (Get-ChildItem -LiteralPath $stagedFolder -Recurse -File).Count
    Write-Verbose "Staged $stagedFileCount file(s); creating output directory $destination"

    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Compress-Archive -Path $stagedFolder -DestinationPath $archivePath -Force
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$archiveSizeKb = [math]::Round((Get-Item -LiteralPath $archivePath).Length / 1KB)
Write-Host "Packed $addonName $version ($stagedFileCount files) -> $archivePath ($archiveSizeKb KB)" -ForegroundColor Green
Write-Host 'Recipient paths:'
Write-Host '  - Upload the zip to CurseForge or attach it to a GitHub release.'
Write-Host '  - Or extract it into Interface\AddOns\ for an instant install.'
