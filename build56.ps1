Param(
    [string] $cacheDir = "C:\php-cache",
    [string] $workDir  = "C:\php-sdk",

    [string] $buildArch = "x86",
    [string] $vcVersion = "vc11",

    # See .\configure.bat --help for details
    [string[]] $configure = @(
        # Compilation options
        "--with-mp=auto",                     # Use multiple process, number determined by compiler

        # Really important options
        "--enable-snapshot-build",            # Optimise build for performance; requires clean
        "--enable-debug-pack",                # Generate external debugging symbols
        "--disable-zts",                      # Disable thread safety (it's experimental)

        # An empty one for those pesky commas
        ""
    ),

    [string] $binVersion = "20110915",
    [string] $sdkVersion = "5.6-$($vcVersion)-$($buildArch)",
    [string] $srcVersion = "5.6.21",

    [string] $binUrl    = "http://windows.php.net/downloads/php-sdk/php-sdk-binary-tools-$($binVersion).zip",
    [string] $binMd5sum = "C49E5782D6B1458A72525C87DE0D416A",

    [string] $sdkUrl    = "http://windows.php.net/downloads/php-sdk/deps-$($sdkVersion).7z",
    [string] $sdkMd5sum = "83E7772DA1B97BB28C0607DFD9B1E5A5",

    [string] $srcUrl    = "http://uk1.php.net/get/php-$($srcVersion).tar.bz2/from/this/mirror",
    [string] $srcMd5sum = "141464CE6B297AA2295B8416C6DBD5E5",

    [switch]   $fork,
    [switch]   $pause,
    [string[]] $actions = @(
        "clean",
        "prepare",
        "configure",
        "build",
        "snapshot",
        "test"
    ),

    [string] $x7zip = "C:\Program Files\7-Zip\7z.exe",
    [string] $vcDir = "C:\Program Files (x86)\Microsoft Visual Studio 11.0\VC"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$DebugPreference = "Continue"
$VerbosePreference = "Continue"

. (Join-Path $PSScriptRoot "common.ps1")

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
        -x7zip $x7zip `
        -vcDir $vcDir
