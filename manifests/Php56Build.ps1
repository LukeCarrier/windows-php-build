Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

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

        cChocoPackageInstaller installGit
        {
            Name = "git"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        cChocoPackageInstaller installVs2012
        {
            Name = "visualstudio2012wdx"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        cChocoPackageInstaller installVcRedist2012
        {
            Name = "vcredist2012"
            DependsOn = "[cChocoInstaller]installChoco"
        }

        cChocoPackageInstaller install7zip
        {
            Name = "7zip"
            DependsOn = "[cChocoInstaller]installChoco"
        }
    }
}
