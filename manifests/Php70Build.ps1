Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

Configuration Php70Build
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

        cChocoPackageInstaller installGit
        {
            Name = "git"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        cChocoPackageInstaller installVs2015
        {
            Name = "visualstudio2015community"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        cChocoPackageInstaller installVcRedist2015
        {
            Name = "vcredist2015"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        cChocoPackageInstaller install7zip
        {
            Name = "7zip"
            DependsOn = "[cChocoInstaller]installChoco"
        }
    }
}
