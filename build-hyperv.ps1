#!/usr/local/bin/pwsh
#Requires -RunAsAdministrator
param(
  [switch]$offline,
  [switch]$SkipPester,
  [switch]$ServerOnly,
  [switch]$TentacleOnly,
  [string]$OctopusVersion,
  [switch]$retainondestroy,
  [switch]$debug
)

. Tests/powershell-helpers.ps1

Start-Transcript .\vagrant-hyperv.log

Set-OctopusDscEnvVars @PSBoundParameters

# remove psreadline as it interferes with the SMB password prompt
if(Get-Module PSReadLine) {
  Remove-Module PSReadLine
}

if (-not (Test-AppExists "vagrant")) {
  Write-Output "Please install vagrant from vagrantup.com."
  exit 1
}
Write-Output "Vagrant installed - good."

if ((Get-CimInstance Win32_OperatingSystem).PRODUCTTYPE -eq 1) {
    # client OS detected
    if ((Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V').State -eq 'Disabled') {
        Write-Output 'Please install Hyper-V.'
        exit 1
    }
}
else {
    # server OS detected
    if ((Get-WindowsFeature 'Hyper-V').State -eq 'Disabled') {
        Write-Output 'Please install Hyper-V.'
        exit 1
    }
}
Write-Output "Hyper-V installed - good."

if (-not (Get-VMSwitch -Name $env:OctopusDSCVMSwitch -ErrorAction SilentlyContinue)) {
    Write-Output "Could not find a Hyper-V switch called $($env:OctopusDSCVMSwitch)"
    exit 1
}
Write-Output (@("Hyper-V virtual switch '", $env:OctopusDSCVMSwitch, "' detected - good.") -join "")

Test-CustomVersionOfVagrantDscPluginIsInstalled
Test-PluginInstalled "vagrant-winrm-syncedfolders"
Test-PluginInstalled "vagrant-winrm-file-download"

Remove-OldLogsBeforeNewRun

if(-not $SkipPester) {
  Import-PowerShellModule -Name "Pester" -MinimumVersion "5.0.2"
  Import-PowerShellModule -Name "PSScriptAnalyzer" -MinimumVersion "1.19.0"
  Write-Output "Running Pester Tests"

  $configuration = [PesterConfiguration]::Default
  $configuration.TestResult.Enabled = $true
  $configuration.TestResult.OutputPath = 'PesterTestResults.xml'
  $configuration.TestResult.OutputFormat = 'NUnitXml'
  $configuration.Run.PassThru = $true
  $configuration.Run.Exit = $true
  $configuration.Output.Verbosity = 'Detailed'
  $result = Invoke-Pester -configuration $configuration

  if ($result.FailedCount -gt 0) {
    exit 1
  }
} else {
  Write-Output "-SkipPester was specified, skipping pester tests"
}

$splat = @{
  provider="hyperv";
  retainondestroy = $retainondestroy.IsPresent; # set to $true to override in this script
  debug = $debug.IsPresent; # set to $true to override in this script
}

Invoke-VagrantWithRetries @splat

Write-Output "Don't forget to run 'vagrant destroy -f' when you have finished"

stop-transcript
