function waitForInput() {
    if ($pause) {
        Write-Host "Pausing; press any key to continue..."
        $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") >$null

        Clear-Host
    }
}

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
        if ($attempt -gt 1) {
            Write-Warning "MD5 checksum did not match expected $($desiredMd5sum)"
        }

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
    & $x7zip x $binFile "-o$($workDir)" -r -y

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
    & $x7zip x $srcFile "-o$($target)" -r -y
    & $x7zip x $tarball "-o$($target)" -r -y
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
    & $x7zip x $sdkFile "-o$($parent)" -r -y
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

    Write-Host "Setting NO_INTERACTION for the test suite"
    $env:NO_INTERACTION = 1
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
        [string]   $buildTargetDir,
        [string]   $depsDir,
        [string[]] $configure
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

function test() {
    Param(
        [string] $buildTargetDir,
        [string] $srcVersion
    )

    try {
        Push-Location $buildTargetDir

        # Run the tests directly rather than using the nmake test target, as the
        # generated Makefile incorrectly attempts to run a partial build of PHP
        # before the libraries have been bundled. This leads to errors like the
        # following:
        #
        #     The program can't start because SSLEAY32.dll is missing from your
        #     computer. Try reinstalling the program to fix this problem.

        Write-Host "Running test suite"
        $command = & nmake /NOLOGO /N test
        $command = $command.Replace("`"Release\php.exe`"", "$(Get-Location)\Release\php-$($srcVersion)\php.exe")
        $command = $command.Trim().Split(" ")
        $commandArgs = $command[1..($command.Length-1)]

        & $command[0].Replace("`"", "") @commandArgs
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

function Do-PhpBuild() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({(Test-Path -Path $_ -Type Container) -or -not (Test-Path -Path $_)})]
        [string] $cacheDir,

        [Parameter(Mandatory=$true)]
        [ValidateScript({(Test-Path -Path $_ -Type Container) -or -not (Test-Path -Path $_)})]
        [string] $workDir,

        [Parameter(Mandatory=$true)]
        [ValidateSet("x86", "x64")]
        [string] $buildArch,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $vcVersion,

        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [System.Collections.ArrayList] $configure,

        [Parameter(Mandatory=$true)]
        [string] $binVersion,

        [Parameter(Mandatory=$true)]
        [string] $sdkVersion,

        [Parameter(Mandatory=$true)]
        [string] $srcVersion,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({$_.Length -eq 32})]
        [string] $binMd5sum,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({$_.Length -eq 32})]
        [string] $sdkMd5sum,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({$_.Length -eq 32})]
        [string] $srcMd5sum,

        [Parameter(Mandatory=$true)]
        [string] $binUrl,

        [Parameter(Mandatory=$true)]
        [string] $sdkUrl,

        [Parameter(Mandatory=$true)]
        [string] $srcUrl,

        [Parameter(Mandatory=$true)]
        [bool] $fork,

        [Parameter(Mandatory=$true)]
        [bool] $pause,

        [Parameter(Mandatory=$true)]
        [string[]] $actions,

        [Parameter(Mandatory=$true)]
        #[ValidateScript({Write-Host $_; Test-Path -Path $_ -Type Leaf})]
        [string] $x7zip,

        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path -Path $_ -Type Container})]
        [string] $vcDir
    )

    Write-Host $x7zip

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
        waitForInput
    }

    if ($actions.Contains("clean") -or !(Test-Path -Type Container -Path $workDir)) {
        initWorkDir -binFile $cache.BinFile -workDir $workDir
        waitForInput
    }

    if ($actions.Contains("prepare")) {
        prepareEnvironment -workDir $workDir -vcVersion $vcVersion `
                -srcFile $cache.SrcFile -sdkFile $Cache.SdkFile
        waitForInput
    }

    $buildTargetDir = getBuildTargetDir -workDir $workDir -vcVersion $vcVersion `
            -buildArch $buildArch -srcVersion $srcVersion
    $depsDir        = getDepsDir -workDir $workDir -vcVersion $vcVersion `
            -buildArch $buildArch
    initEnvironment -vcDir $vcDir
    waitForInput

    if ($actions.Contains("configure")) {
        configure -buildTargetDir $buildTargetDir -depsDir $depsDir `
                -configure $configure

        waitForInput
    }

    if ($actions.Contains("build")) {
        build -buildTargetDir $buildTargetDir -vcVersion $vcVersion `
                -buildArch $buildArch -srcVersion $srcVersion
        waitForInput
    }

    if ($actions.Contains("snapshot")) {
        snapshot -buildTargetDir $buildTargetDir
        waitForInput
    }

    if ($actions.Contains("test")) {
        test -buildTargetDir $buildTargetDir -srcVersion $srcVersion
        waitForInput
    }
}
