Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Configuration Php56Build
{
    Import-DscResource -ModuleName cChoco

    Node "localhost"
    {
        LocalConfigurationManager
        {
            DebugMode = "ForceModuleImport"
        }

        cChocoInstaller installChoco
        {
            InstallDir = "C:\ProgramData\choco"
        }

        cChocoPackageInstaller installWmf5
        {
            Name = "powershell"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        cChocoPackageInstaller installVs2012
        {
            Name = "visualstudio2012wdx"
        }

        cChocoPackageInstaller installVcRedist2012
        {
            Name = "vcredist2012"
        }

        cChocoPackageInstaller install7zip
        {
            Name = "7zip"
        }
    }
}
