# Unlock List Dalamud Plugin

Dalamud plugin for the FFXIV unlockables data used by this repository.

## What is included

- `VaelarisUnlockList/` - Dalamud plugin project targeting API 15 through `Dalamud.NET.Sdk/15.0.0`.
- `tools/build-plugin-data.mjs` - exporter that reads the site JSON files and writes `VaelarisUnlockList/Data/unlockables.json`.
- `VaelarisUnlockList/Data/unlockables.json` - generated plugin dataset with resolved game IDs where known.
- `VaelarisUnlockList/images/icon.png` - 512x512 plugin icon asset.
- `dist/pluginmaster.json` - custom Dalamud repository manifest.

## Build prerequisites

- XIVLauncher and Dalamud installed and run at least once.
- .NET SDK 10.x for Dalamud API 15.

## Regenerate data

From the repository root:

```powershell
node .\dalamud-plugin\tools\build-plugin-data.mjs
```

## Build

```powershell
dotnet build .\dalamud-plugin\VaelarisUnlockList\VaelarisUnlockList.csproj
```

## Install from GitHub

Add this URL to Dalamud Custom Plugin Repositories:

```text
https://raw.githubusercontent.com/hartturmch/ffxiv-unlocklist/refs/heads/main/dalamud-plugin/dist/pluginmaster.json
```

Then install **Unlock List** from the Dalamud Plugin Installer.

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
.\dalamud-plugin\tools\package-github.ps1 -Owner "hartturmch" -Repo "ffxiv-unlocklist" -Branch "main"
```

Commit and push:

- `dalamud-plugin/dist/pluginmaster.json`
- `dalamud-plugin/dist/VaelarisUnlockList-0.1.0.0.zip`
- `dalamud-plugin/dist/icon.png`

Dalamud repository URL:

```text
https://raw.githubusercontent.com/hartturmch/ffxiv-unlocklist/refs/heads/main/dalamud-plugin/dist/pluginmaster.json
```

## In-game

The plugin adds `/vunlock` and a main UI button in Dalamud. It can:

- load the generated unlockables dataset;
- use generated and runtime-resolved Lumina row IDs;
- mark quest-backed entries complete with `IUnlockState.IsQuestCompleted`;
- mark aether current entries complete where the aether current ID is known;
- keep manual completion state for entries that cannot be auto-detected yet;
- filter by search text, category, map, current zone, completion visibility, and status;
- open the in-game map with a flag for entries that have coordinates and a resolvable map.

Some unlocks still show as **Needs Manual Check** when the game does not expose a reliable completion state or the ID is not resolved yet.
