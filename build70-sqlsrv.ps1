Param(
    [string] $cacheDir = "C:\php-cache",
    [string] $workDir  = "C:\php-sdk",

    [string] $buildArch = "x64",
    [string] $vcVersion = "vc14",

    [string] $sqlsrvRepo = "https://github.com/Microsoft/msphpsql.git",
    [string] $sqlsrvRef  = "v4.1.3-Windows",
    [string] $sqlsrvDir  = "C:\php-cache\extensions\sqlsrv",

    # See .\configure.bat --help for details
    [string[]] $configure = @(
        # Compilation options
        "--with-mp=auto",                     # Use multiple process, number determined by compiler

        # Really important options
        "--enable-snapshot-build",            # Optimise build for performance; requires clean
        "--enable-debug-pack",                # Generate external debugging symbols
        "--disable-zts",                      # Disable thread safety (it's experimental)

        # Microsoft SQL Server extensions
        "--with-odbcver=0x0380",              # Microsoft/msphpsql#45
        "--enable-pdo=shared",
        "--enable-sqlsrv=shared",
        "--with-pdo-sqlsrv=shared",

        # An empty one for those pesky commas
        ""
    ),

    [string[]] $testExtensionBlacklist = @(
        "interbase",
        "pdo_firebird",
        "snmp"
    ),

    [string] $binVersion = "20110915",
    [string] $sdkVersion = "7.0-$($vcVersion)-$($buildArch)",
    [string] $srcVersion = "7.0.14",

    [string] $binUrl    = "http://windows.php.net/downloads/php-sdk/php-sdk-binary-tools-$($binVersion).zip",
    [string] $binMd5sum = "C49E5782D6B1458A72525C87DE0D416A",

    [string] $sdkUrl    = "http://windows.php.net/downloads/php-sdk/deps-$($sdkVersion).7z",
    [string] $sdkMd5sum = "98841D20C844265A3A0C14070FD38887",

    [string] $srcUrl    = "http://uk1.php.net/get/php-$($srcVersion).tar.bz2/from/this/mirror",
    [string] $srcMd5sum = "903FF1FD199201D7E69DC0963797072B",

    [switch]   $fork,
    [switch]   $pause,
    [string[]] $actions = @(
        "clean",
        "prepare",
        "prepare-extensions",
        "configure",
        "build",
        "snapshot",
        "test-blacklist",
        "test"
    ),

    [string] $x7zip = "C:\Program Files\7-Zip\7z.exe",
    [string] $vcDir = "C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$DebugPreference = "Continue"
$VerbosePreference = "Continue"

. (Join-Path $PSScriptRoot "common.ps1")

function fetchSqlsrvExtension() {
    Param(
        [string]   $repo,
        [string]   $ref,
        [string]   $dir
    )

    if (!(Test-Path $dir)) {
        & git clone $repo $dir
    }

    Push-Location $dir
    try {
        & git remote set-url origin $repo
        & git checkout $ref
        & git reset --hard $ref
    } finally {
        Pop-Location
    }
}

if ($actions.Contains("prepare-extensions")) {
    # Otherwise we errors to the effect of:
    # fatal: Invalid symlink 'C:/vagrant': Function not implemented
    Push-Location "$($env:HOMEDRIVE)\"
    try {
        $extSrcDirs = @()

        fetchSqlsrvExtension -repo $sqlsrvRepo -ref $sqlsrvRef -dir $sqlsrvDir
        $extSrcDirs += Join-Path $sqlsrvDir "sqlsrv"
        $extSrcDirs += Join-Path $sqlsrvDir "pdo_sqlsrv"

        $extSrcDirs | ForEach-Object {
            Write-Host "Queueing extension $($_)"
            addExtension -srcDir $_
        }
    } finally {
        Pop-Location
    }
}

Do-PhpBuild `
        -cacheDir $cacheDir `
        -workDir $workDir `
        -buildArch $buildArch `
        -vcVersion $vcVersion `
        -configure $configure `
        -testExtensionBlacklist $testExtensionBlacklist `
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
