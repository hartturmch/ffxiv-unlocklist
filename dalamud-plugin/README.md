# Unlock List Dalamud Plugin

Prototype Dalamud plugin for the FFXIV unlockables data used by this site.

## What is included

- `VaelarisUnlockList/` - Dalamud plugin project targeting API 15 through `Dalamud.NET.Sdk/15.0.0`.
- `tools/build-plugin-data.mjs` - exporter that reads the site JSON files and writes `VaelarisUnlockList/Data/unlockables.json`.
- `VaelarisUnlockList/Data/unlockables.json` - generated plugin dataset.
- `VaelarisUnlockList/images/icon.png` - 512x512 plugin icon asset.

## Build prerequisites

- XIVLauncher and Dalamud installed and run at least once.
- .NET SDK 10.x for Dalamud API 15.

This machine currently has .NET runtimes only, so `dotnet build` cannot run here until the SDK is installed.

## Regenerate data

From the repository root:

```powershell
node .\dalamud-plugin\tools\build-plugin-data.mjs
```

## Build

```powershell
dotnet build .\dalamud-plugin\VaelarisUnlockList\VaelarisUnlockList.csproj
```

## Package release

Builds a zip and local `pluginmaster.json` under `dalamud-plugin/dist`.

```powershell
.\dalamud-plugin\tools\package-release.ps1 -Configuration Release -BaseUrl "https://your-host.example/unlock-list"
```

Host these files from `dalamud-plugin/dist` at the same base URL:

- `pluginmaster.json`
- `VaelarisUnlockList-0.1.0.0.zip`
- `icon.png`

Then add the hosted `pluginmaster.json` URL to Dalamud Custom Plugin Repositories.

## Package for GitHub raw hosting

Use this when `dalamud-plugin/dist` will be committed to a GitHub repo.

```powershell
.\dalamud-plugin\tools\package-github.ps1 -Owner "YOUR_GITHUB_USER" -Repo "ffxiv-unlocklist" -Branch "master"
```

Commit and push:

- `dalamud-plugin/dist/pluginmaster.json`
- `dalamud-plugin/dist/VaelarisUnlockList-0.1.0.0.zip`
- `dalamud-plugin/dist/icon.png`

Dalamud repository URL:

```text
https://raw.githubusercontent.com/YOUR_GITHUB_USER/ffxiv-unlocklist/master/dalamud-plugin/dist/pluginmaster.json
```

## In-game

The plugin adds `/vunlock` and a main UI button in Dalamud. The first version can:

- load the generated unlockables dataset;
- resolve quest names to Lumina quest row IDs at runtime;
- mark quest-backed entries complete with `IUnlockState.IsQuestCompleted`;
- keep manual completion state for entries that cannot be auto-detected yet;
- resolve places to territory/map IDs where possible;
- open the in-game map with a flag for entries that have coordinates and a resolvable map.

The next data improvement is to add explicit `questId`, `territoryTypeId`, `mapId`, and `aetherCurrentId` fields to the exporter so the plugin no longer relies on name matching.

For a public/custom plugin repository, host `VaelarisUnlockList/images/icon.png` and set the generated repository entry's `IconUrl` to the raw PNG URL. Local dev plugin paths do not use a public `IconUrl`.
