Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

try {
    Get-Command chocolatey >$null
} catch {
    (New-Object Net.WebClient).DownloadString("https://chocolatey.org/install.ps1") `
            | Invoke-Expression
}

# Upgrade to WMF 5.0 for DSC
if ($PSVersionTable.PSVersion.Major -lt 5) {
    & chocolatey install -y powershell
}

Install-PackageProvider -Name NuGet -Force
Install-Module -Name cChoco -Force
