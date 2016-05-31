# Modelled after the "step by step" build instructions:
# https://wiki.php.net/internals/windows/stepbystepbuild

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
        "--enable-one-shot",                  # Optimise build for performance; requires clean
        "--enable-debug-pack",                # Generate external debugging symbols
        "--disable-zts",                      # Disable thread safety (it's experimental)
        "--disable-all",                      # Disable all extensions by default

        # Optional libraries
        "--with-xml",                         # Expat XML parser
        "--with-libxml",                      # XML parser

        # SAPIs
        "--enable-cli",                       # Command line (php.exe)

        # Miscellaneous extensions
        "--enable-ctype",                     # Character type checking
        "--with-curl",                        # cURL HTTP client
        "--with-gd",                          # Graphics processing
        "--with-iconv",                       # Character set conversion
        "--enable-intl",                      # Internationalisation
        "--enable-json",                      # JSON encode/decode
        "--enable-mbstring",                  # Multibyte strings
        "--with-openssl",                     # OpenSSL PKI
        "--enable-pdo",                       # PHP Data Objects
        "--enable-soap",                      # SOAP client
        "--enable-tokenizer",                 # Tokenizer for PHP source

        # XML extensions
        "--with-dom",                         # Document Object Model
        "--with-simplexml"                    # SimpleXML parser
        "--enable-xmlreader",                 # XMLReader
        "--with-xmlrpc",                      # XMLRPC-EPI support
        "--enable-xmlwriter",                 # XMLWriter

        # Compression
        "--enable-zip",                       # Zip compression
        "--enable-zlib",                      # Zlib compression

        # Database extensions
        #"--with-pdo-sqlsrv",
        #"--with-sqlsrv",

        # An empty one for those pesky commas
        ""
    ),

    [string] $binVersion = "20110915",
    [string] $sdkVersion = "5.6-$($vcVersion)-$($buildArch)",
    [string] $srcVersion = "5.6.21",

    [string] $binMd5sum = "C49E5782D6B1458A72525C87DE0D416A",
    [string] $sdkMd5sum = "DF4B4EE51A92EAE6740F4071B6F181B0",
    [string] $srcMd5sum = "141464CE6B297AA2295B8416C6DBD5E5",

    [string] $binUrl = "http://windows.php.net/downloads/php-sdk/php-sdk-binary-tools-$($binVersion).zip",
    [string] $sdkUrl = "http://windows.php.net/downloads/php-sdk/deps-$($sdkVersion).7z",
    [string] $srcUrl = "http://uk1.php.net/get/php-$($srcVersion).tar.bz2/from/this/mirror",

    [switch]   $fork,
    [string[]] $actions = @("cache", "clean", "prepare", "configure", "build", "snapshot"),

    [string] $7zip = "C:\Program Files\7-Zip\7z.exe",
    [string] $vcDir = "C:\Program Files (x86)\Microsoft Visual Studio 11.0\VC"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$DebugPreference = "Continue"
$VerbosePreference = "Continue"

function cacheFile() {
    Param(
        [string] $url,
        [string] $filename,
        [string] $desiredMd5sum,
        [string] $cacheDir,
        [int]    $maxAttempts = 3
    )

    $target = Join-Path $cacheDir $filename
    Write-Verbose "Downloading $($url) to $($target)"

    $md5sum = ""
    if (Test-Path -Path $target -Type Leaf) {
        $md5sum = (Get-FileHash -Algorithm MD5 -Path $target).Hash
    }

    $attempt = 0
    while (!(Test-Path -Path $target -Type Leaf) `
            -or $md5sum -ne $desiredMd5sum) {
        $attempt++
        if ($attempt -gt $maxAttempts) {
            Write-Error "Failed after $($maxAttempts) attempts"
            return
        }

        Write-Verbose "Attempt $($attempt) of $($maxAttempts)"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($url, $target)

        $md5sum = (Get-FileHash -Algorithm MD5 -Path $target).Hash
        Write-Verbose "Resulting MD5 checksum $($md5sum)"
    }

    return $target
}

function makeDirs() {
    if (!(Test-Path -Type Container -Path $workDir)) {
        New-Item -ItemType Directory -Path $workDir >$null
    }

    if (!(Test-Path -Type Container -Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir >$null
    }
}

function downloadSources() {
    Param(
        [string] $cacheDir,
        [string] $binUrl,
        [string] $binVersion,
        [string] $binMd5sum,
        [string] $sdkUrl,
        [string] $sdkVersion,
        [string] $sdkMd5sum,
        [string] $srcUrl,
        [string] $srcVersion,
        [string] $srcMd5sum
    )

    Write-Host "Populating cache"

    return New-Object PSObject -Property @{
        BinFile = cacheFile -url $binUrl -filename "bin-$($binVersion).zip" `
                -desiredMd5sum $binMd5sum -cacheDir $cacheDir
        SdkFile = cacheFile -url $sdkUrl -filename "sdk-$($sdkVersion).7z" `
                -desiredMd5sum $sdkMd5sum -cacheDir $cacheDir
        SrcFile = cacheFile -url $srcUrl -filename "src-$($srcVersion).tar.bz2" `
                -desiredMd5sum $srcMd5sum -cacheDir $cacheDir
    }
}

function initWorkDir() {
    Param(
        [string] $binFile,
        [string] $workDir
    )

    Write-Host "Preparing build tree in $($workDir)"

    if (Test-Path -Path $workDir) {
        Write-Warning "Removing existing tree"
        Remove-Item -Force -Recurse -Path $workDir
    }

    Write-Debug "Extracting PHP binary tools"
    & $7zip x $binFile "-o$($workDir)" -r -y

    try {
        Push-Location $workDir

        Write-Debug "Creating build directories"
        & "$($workDir)\bin\phpsdk_buildtree.bat" phpdev
        foreach ($unsupportedVcVersion in @("vc11", "vc14")) {
            $target = "$($workDir)\phpdev\$($unsupportedVcVersion)"
            if (Test-Path -Type Container -Path $target) {
                Continue
            }
            Write-Warning "Copying vc9 directory structure for $($unsupportedVcVersion)"
            Copy-Item -Recurse "$($workDir)\phpdev\vc9" $target
        }
    } finally {
        Pop-Location
    }
}

# Unfortunately this is very much necessary:
# http://stackoverflow.com/a/2124759
function invokeBatchFile() {
    Param(
        [string] $batchFile,
        [string] $argumentList
    )

    Write-Host "Invoking batch file $($batchFile)"
    $batchFileInfo = Get-Item $batchFile

    try {
        Push-Location $batchFileInfo.DirectoryName

        & cmd /c ".\$($batchFileInfo.Name) $($argumentList) & set" | ForEach-Object {
            if ($_ -match "^(.*?)=(.*)$") {
                $pair = $_.Split("=")
                Write-Debug "Setting `$env:$($pair[0]) to $($pair[1])"
                Set-Item -Force -Path "ENV:\$($pair[0])" -Value $pair[1]
            }
        }
    } finally {
        Pop-Location
    }
}

function extractSource() {
    Param(
        [string] $srcFile,
        [string] $vcVersion,
        [string] $buildArch,
        [string] $workDir
    )

    $target  = "$($workDir)\phpdev\$($vcVersion)\$($buildArch)"
    $tarball = Join-Path $target (Get-Item $srcFile).BaseName

    Write-Host "Extracting source archive $($srcFile) to $($target)"
    & $7zip x $srcFile "-o$($target)" -r -y
    & $7zip x $tarball "-o$($target)" -r -y
    Remove-Item -Path $tarball
}

function extractSdk() {
    Param(
        [string] $sdkFile,
        [string] $vcVersion,
        [string] $buildArch,
        [string] $workDir
    )

    $parent = "$($workDir)\phpdev\$($vcVersion)\$($buildArch)"
    $deps   = "$($parent)\deps"

    Write-Host "Extracting SDK archive $($sdkFile) to $($deps)"
    if (Test-Path $deps) {
        Write-Warning "Removing existing deps directory $($deps)"
        Remove-Item -Force -Recurse $deps
    }
    & $7zip x $sdkFile "-o$($parent)" -r -y
}

function prepareEnvironment() {
    Param(
        [string] $workDir,
        [string] $vcVersion,
        [string] $srcFile,
        [string] $sdkFile
    )

    Write-Host "Preparing work directory"

    try {
        Push-Location $workDir

        Write-Host "Extracting PHP source to work directory"
        extractSource -srcFile $srcFile -vcVersion $vcVersion -buildArch $buildArch `
                -workDir $workDir

        Write-Host "Extracting PHP SDK to work directory"
        extractSdk -sdkFile $sdkFile -vcVersion $vcVersion -buildArch $buildArch `
                -workDir $workDir
    } finally {
        Pop-Location
    }
}

function initEnvironment() {
    Param(
        [string] $vcDir
    )

    Write-Host "Configuring environment from $($vcDir)"

    invokeBatchFile -batchFile "$($vcDir)\vcvarsall.bat"
    invokeBatchFile -batchFile "$($workDir)\bin\phpsdk_setvars.bat" `
            -argumentList $buildArch
}

function getBuildTargetDir() {
    Param(
        [string] $workDir,
        [string] $vcVersion,
        [string] $buildArch,
        [string] $srcVersion
    )
    return "$($workDir)\phpdev\$($vcVersion)\$($buildArch)\php-$($srcVersion)"
}

function getDepsDir() {
    Param(
        [string] $workDir,
        [string] $vcVersion,
        [string] $buildArch
    )

    return "$($workDir)\phpdev\$($vcVersion)\$($buildArch)\deps"
}


function configure() {
    Param(
        [string] $buildTargetDir,
        [string] $depsDir
    )

    $configureFlags = $configure | Foreach-Object {
        $_.Replace("{deps}", $depsDir)
    }
    Write-Debug "Final configure command is $([System.String]::Join(" ", $configureFlags))"

    try {
        Push-Location $buildTargetDir

        Write-Host "Generating configure"
        & .\buildconf.bat

        Write-Host "Configuring build"
        & .\configure.bat @configureFlags
    } finally {
        Pop-Location
    }
}

function build() {
    Param(
        [string] $buildTargetDir,
        [string] $vcVersion,
        [string] $buildArch,
        [string] $srcVersion
    )

    Write-Host "Building $($srcVersion) for $($buildArch) with $($vcVersion)"

    try {
        Push-Location $buildTargetDir

        Write-Host "Running nmake"
        & nmake
    } finally {
        Pop-Location
    }
}

function snapshot() {
    Param(
        [string] $buildTargetDir
    )

    try {
        Push-Location $buildTargetDir

        Write-Host "Packaging snapshot"
        & nmake snap
    } finally {
        Pop-Location
    }
}

if ($fork) {
    Write-Host "Spawning child process to host build"
    $PSBoundParameters.Remove("fork") >$null

    & $MyInvocation.MyCommand.Definition @PSBoundParameters

    Exit
}

makeDirs
if ($actions.Contains("cache")) {
    $cache = downloadSources -cacheDir $cacheDir `
            -binUrl $binUrl -binVersion $binVersion -binMd5sum $binMd5sum `
            -sdkUrl $sdkUrl -sdkVersion $sdkVersion -sdkMd5sum $sdkMd5sum `
            -srcUrl $srcUrl -srcVersion $srcVersion -srcMd5sum $srcMd5sum
}

if ($actions.Contains("clean") -or !(Test-Path -Type Container -Path $workDir)) {
    initWorkDir -binFile $cache.BinFile -workDir $workDir
}

if ($actions.Contains("prepare")) {
    prepareEnvironment -workDir $workDir -vcVersion $vcVersion `
            -srcFile $cache.SrcFile -sdkFile $Cache.SdkFile
}

$buildTargetDir = getBuildTargetDir -workDir $workDir -vcVersion $vcVersion `
        -buildArch $buildArch -srcVersion $srcVersion
$depsDir        = getDepsDir -workDir $workDir -vcVersion $vcVersion `
        -buildArch $buildArch
initEnvironment -vcDir $vcDir

if ($actions.Contains("configure")) {
    configure -buildTargetDir $buildTargetDir -depsDir $depsDir `
            -configure $configure
}

if ($actions.Contains("build")) {
    build -buildTargetDir $buildTargetDir -vcVersion $vcVersion `
            -buildArch $buildArch -srcVersion $srcVersion
}

if ($actions.Contains("snapshot")) {
    snapshot -buildTargetDir $buildTargetDir
}
