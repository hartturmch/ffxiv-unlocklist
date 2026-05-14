param(
    [string]$Configuration = 'Release',
    [string]$BaseUrl = 'https://example.com/unlock-list',
    [string]$Version = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PluginName = 'VaelarisUnlockList'
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$PluginRoot = Join-Path $RepoRoot 'dalamud-plugin\VaelarisUnlockList'
$ProjectPath = Join-Path $PluginRoot "$PluginName.csproj"
$DistRoot = Join-Path $RepoRoot 'dalamud-plugin\dist'

if (-not $Version) {
    [xml]$project = Get-Content $ProjectPath
    $Version = [string]$project.Project.PropertyGroup.Version
}

$BuildOut = Join-Path $PluginRoot "bin\$Configuration"
$StageRoot = Join-Path $DistRoot "$PluginName-$Version"
$ZipPath = Join-Path $DistRoot "$PluginName-$Version.zip"
$RepoPath = Join-Path $DistRoot 'pluginmaster.json'

dotnet build $ProjectPath -c $Configuration

if (Test-Path $StageRoot) {
    Remove-Item -LiteralPath $StageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $StageRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $StageRoot 'Data') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $StageRoot 'images') | Out-Null
New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null

Copy-Item -LiteralPath (Join-Path $BuildOut "$PluginName.dll") -Destination $StageRoot
Copy-Item -LiteralPath (Join-Path $BuildOut "$PluginName.json") -Destination $StageRoot
Copy-Item -LiteralPath (Join-Path $BuildOut 'Data\unlockables.json') -Destination (Join-Path $StageRoot 'Data')
Copy-Item -LiteralPath (Join-Path $BuildOut 'images\icon.png') -Destination (Join-Path $StageRoot 'images')

if (Test-Path $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}
Compress-Archive -Path (Join-Path $StageRoot '*') -DestinationPath $ZipPath -Force

$manifest = Get-Content (Join-Path $StageRoot "$PluginName.json") -Raw | ConvertFrom-Json
$downloadLink = "$BaseUrl/$PluginName-$Version.zip"
$iconUrl = "$BaseUrl/icon.png"
$repoEntry = [ordered]@{
    Author = $manifest.Author
    Name = $manifest.Name
    InternalName = $PluginName
    AssemblyVersion = $Version
    TestingAssemblyVersion = $Version
    Punchline = $manifest.Punchline
    Description = $manifest.Description
    ApplicableVersion = $manifest.ApplicableVersion
    Tags = $manifest.Tags
    DalamudApiLevel = 15
    DownloadLinkInstall = $downloadLink
    DownloadLinkUpdate = $downloadLink
    DownloadLinkTesting = $downloadLink
    IconUrl = $iconUrl
    IsHide = $false
    IsTestingExclusive = $false
}

$repoJson = @($repoEntry) | ConvertTo-Json -Depth 8
if (-not $repoJson.TrimStart().StartsWith('[')) {
    $repoJson = "[$repoJson]"
}
$repoJson | Set-Content -LiteralPath $RepoPath -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $StageRoot 'images\icon.png') -Destination (Join-Path $DistRoot 'icon.png') -Force
Remove-Item -LiteralPath $StageRoot -Recurse -Force

Write-Host "Built $ZipPath"
Write-Host "Wrote $RepoPath"
Write-Host "Host these files under: $BaseUrl"
