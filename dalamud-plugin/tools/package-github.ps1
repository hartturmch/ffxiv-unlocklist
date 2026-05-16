param(
    [Parameter(Mandatory = $true)]
    [string]$Owner,

    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [string]$Branch = 'master',

    [string]$Configuration = 'Release',

    [string]$Version = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BaseUrl = "https://raw.githubusercontent.com/$Owner/$Repo/refs/heads/$Branch/dalamud-plugin/dist"
$PackageScript = Join-Path $PSScriptRoot 'package-release.ps1'

& $PackageScript -Configuration $Configuration -BaseUrl $BaseUrl -Version $Version

Write-Host ''
Write-Host 'GitHub raw repository URL for Dalamud:'
Write-Host "$BaseUrl/pluginmaster.json"
Write-Host ''
Write-Host 'Commit and push these files:'
Write-Host '  dalamud-plugin/dist/pluginmaster.json'
Write-Host '  dalamud-plugin/dist/icon.png'
Write-Host '  dalamud-plugin/dist/VaelarisUnlockList-*.zip'
