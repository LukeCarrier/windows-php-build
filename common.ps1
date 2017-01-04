$global:PHP_WINDOWS_EXT_DIRS = @()

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
        [string] $buildArch,
        [string] $vcDir
    )

    if (Test-Path Env:\PHP_WINDOWS_VC_DIR) {
        if (($env:PHP_WINDOWS_VC_DIR -eq $vcDir) -and ($env:PHP_WINDOWS_VC_ARCH -eq $buildArch)) {
            Write-Warning "Skipping environment initialisation; it's already happened"
            return
        } else {
            throw "Cannot initialise environment for `"$($vcDir)`" ($($buildArch)); already done for `"$($env:PHP_WINDOWS_VC_DIR)`" ($($env:PHP_WINDOWS_VC_ARCH))"
        }
    }
    $env:PHP_WINDOWS_VC_DIR  = $vcDir
    $env:PHP_WINDOWS_VC_ARCH = $buildArch

    Write-Host "Configuring environment from $($vcDir)"

    invokeBatchFile -batchFile "$($vcDir)\vcvarsall.bat" `
            -argumentList $buildArch
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

    $configureFlags = $configure | ForEach-Object {
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

function addExtension() {
    Param(
        [string[]] $srcDir
    )

    $global:PHP_WINDOWS_EXT_DIRS += $srcDir
}

function installExtensions() {
    Param(
        [string] $buildTargetDir
    )

    Write-Debug "Installing $($global:PHP_WINDOWS_EXT_DIRS.Count) extensions into build directory"
    $global:PHP_WINDOWS_EXT_DIRS | ForEach-Object {
        $extName = (Get-Item $_).BaseName
        $extTargetDir = Join-Path (Join-Path $buildTargetDir "ext") $extName
        Write-Debug "Installing extension $($extName) to $($extTargetDir)"

        if (Test-Path $extTargetDir) {
            Write-Warning "Removing existing extension directory $($extTargetDir)"
            Remove-Item -Force -Recurse $extTargetDir
        }
        Copy-Item -Recurse $_ $extTargetDir
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

function blacklistExtensionsInTest() {
    Param(
        [string] $buildTargetDir,
        [string] $srcVersion,
        [string[]] $buildArch,
        [string[]] $testExtensionBlacklist
    )

    $tmpIni = $buildTargetDir
    if ($buildArch -ne "x86") {
        $tmpIni += "\$($buildArch)"
    }
    $tmpIni += "\Release\tmp-php.ini"
    Write-Host "Blacklisting $($testExtensionBlacklist -join ", ") extensions in $($tmpIni)"

    $tmpIniContents = Get-Content -Raw -Path $tmpIni
    foreach ($extension in $testExtensionBlacklist) {
        $tmpIniContents = $tmpIniContents -replace "((?!;)(zend_)?extension=php_$($extension)\.dll)", ";`$1"
    }

    Set-Content -Value $tmpIniContents -Path $tmpIni
}

function test() {
    Param(
        [string] $buildTargetDir,
        [string] $srcVersion
    )

    try {
        Write-Host "Running test suite"
        Push-Location $buildTargetDir

        # Get the command to run the tests from nmake rather than than Invoking
        # the nmake test target, as the generated Makefile is broken.
        $command = & nmake /NOLOGO /N test

        $command = ($command.Split([Environment]::NewLine.ToCharArray()) | ForEach-Object {
            if ($_ -like "*set PATH=*") {
                # PHP >= 7.0.14 execute a set-tmp-env target here which attempts
                # to run SET PATH=xxx. This doesn't work in PowerShell, so we
                # have to fix up the command first. We'll run the tests in a
                # subprocess to avoid polluting the build environment.
                $_.Trim().Replace("set PATH=", "`$env:PATH = `"") + "`""
            } elseif ($_ -like "*php.exe*") {
                # Older versions of PHP incorrectly attempt to test an orphaned
                # release binary without bundled libraries and extensions.
                # Correct the path to the PHP binary to be tested to work around
                # the following style of failure:
                #
                #     The program can't start because SSLEAY32.dll is missing
                #     from your computer. Try reinstalling the program to fix
                #     this problem.
                "& " + $_.Trim().Replace("`"Release\php.exe`"", "$($buildTargetDir)\Release\php-$($srcVersion)\php.exe")
            } else {
                "& " + $_.Trim()
            }
        }) -join ";`n"

        Write-Debug "Patched > $($command)"
        $block = [ScriptBlock]::Create("Set-Location $(Get-Location)`n" + $command)
        $completeStates = @("Completed", "Failed")
        try {
            $job = Start-Job -ScriptBlock $block
            while ($job.HasMoreData -or !($completeStates.Contains($job.State))) {
                try {
                    Receive-Job -Job $job
                } catch {
                    # Raised to indicate stderr output or failure? Either way,
                    # not an issue for us.
                }
            }
        } finally {
            Remove-Job -Force -Job $job
        }
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

        [Parameter(Mandatory=$false)]
        $testExtensionBlacklist = @(),

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

    if ($fork) {
        Write-Host "Spawning child process to host build"
        $PSBoundParameters.Remove("fork") >$null

        & $MyInvocation.MyCommand.Definition @PSBoundParameters

        Exit
    }

    makeDirs
    $cache = downloadSources -cacheDir $cacheDir `
            -binUrl $binUrl -binVersion $binVersion -binMd5sum $binMd5sum `
            -sdkUrl $sdkUrl -sdkVersion $sdkVersion -sdkMd5sum $sdkMd5sum `
            -srcUrl $srcUrl -srcVersion $srcVersion -srcMd5sum $srcMd5sum
    waitForInput

    $buildTargetDir = getBuildTargetDir -workDir $workDir -vcVersion $vcVersion `
            -buildArch $buildArch -srcVersion $srcVersion
    $depsDir        = getDepsDir -workDir $workDir -vcVersion $vcVersion `
            -buildArch $buildArch

    if ($actions.Contains("clean") -or !(Test-Path -Type Container -Path $workDir)) {
        initWorkDir -binFile $cache.BinFile -workDir $workDir
        waitForInput
    }

    if ($actions.Contains("prepare")) {
        prepareEnvironment -workDir $workDir -vcVersion $vcVersion `
                -srcFile $cache.SrcFile -sdkFile $Cache.SdkFile
        waitForInput
    }

    if ($actions.Contains("prepare-extensions")) {
        installExtensions -buildTargetDir $buildTargetDir
    }

    initEnvironment -buildArch $buildArch -vcDir $vcDir
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

    if ($actions.Contains("test-blacklist")) {
        blacklistExtensionsInTest -buildTargetDir $buildTargetDir `
                -srcVersion $srcVersion -buildArch $buildArch `
                -testExtensionBlacklist $testExtensionBlacklist
        waitForInput
    }

    if ($actions.Contains("test")) {
        test -buildTargetDir $buildTargetDir -srcVersion $srcVersion
        waitForInput
    }
}
