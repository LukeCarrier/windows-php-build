Param(
    [string] $cacheDir,
    [string] $workDir,

    [string] $buildArch,
    [string] $vcVersion,

    [string[]] $configure,

    [string] $binVersion,
    [string] $sdkVersion,
    [string] $srcVersion,

    [string] $binMd5sum,
    [string] $sdkMd5sum,
    [string] $srcMd5sum,

    [string] $binUrl,
    [string] $sdkUrl,
    [string] $srcUrl,

    [switch]   $fork,
    [switch]   $pause,
    [string[]] $actions,

    [string] $7zip,
    [string] $vcDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$DebugPreference = "Continue"
$VerbosePreference = "Continue"

. (Join-Path Get-Location "common.ps1")

Do-PhpBuild `
        -cacheDir $cacheDir `
        -workDir $workDir `
        -buildArch $buildArch `
        -vcVersion $vcVersion `
        -configure $configure `
        -binVersion $binVersion `
        -sdkVersion $sdkVersion `
        -srcVersion $srcVersion `
        -binMd5sum $binMd5sum `
        -sdkMd5sum $sdkMd5sum `
        -srcMd5sum $srcMd5sum `
        -binUrl $binUrl `
        -sdkUrl $sdkUrl `
        -srcUrl $srcUrl `
        -fork $fork `
        -pause $pause `
        -actions $actions `
        -7zip $7zip `
        -vcDir $vcDir
