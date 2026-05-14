# FFXIV Unlock List

FFXIV unlock tracker and Dalamud plugin for finding unlockable content, checking what your character already has, and opening map locations in game.

## Dalamud Plugin

Plugin name: **Unlock List**

Author: **Stan**

Command:

```text
/vunlock
```

### What It Does

- Shows FFXIV unlockables in an in-game checklist.
- Tracks completed quest-backed unlocks automatically when Dalamud can read the character state.
- Supports manual completion for entries that cannot be detected automatically.
- Searches unlocks, quests, zones, and requirements.
- Filters by category, map, current zone, completion visibility, and status.
- Opens map flags for unlocks with known coordinates.
- Shows prerequisite quests in requirements so hidden unlock chains are easier to follow.
- Includes developer tools for resolved ID export and validation reports.

### Install

1. Open Dalamud settings in game.
2. Go to **Experimental**.
3. Add this custom plugin repository:

```text
https://raw.githubusercontent.com/hartturmch/ffxiv-unlocklist/main/dalamud-plugin/dist/pluginmaster.json
```

4. Save.
5. Open Dalamud Plugin Installer.
6. Search for **Unlock List**.
7. Install.
8. Run `/vunlock`.

### Current State

This is a custom repo plugin. It is not in the official Dalamud plugin list.

Most quest-backed entries can be tracked automatically. Some content still needs manual checking because FFXIV/Dalamud unlock state is not exposed for every unlock type.
