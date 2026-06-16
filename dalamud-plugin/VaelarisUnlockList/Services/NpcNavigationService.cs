using System.Globalization;
using System.Numerics;
using System.Text.RegularExpressions;
using Dalamud.Game.Text.SeStringHandling.Payloads;
using Dalamud.Plugin.Services;
using Dalamud.Utility;
using Lumina.Excel.Sheets;

namespace VaelarisUnlockList.Services;

public sealed class NpcNavigationService
{
    private readonly IDataManager dataManager;
    private readonly IGameGui gameGui;
    private readonly IClientState clientState;
    private readonly ICommandManager commandManager;
    private readonly IFramework framework;
    private readonly IChatGui chatGui;
    private readonly IPluginLog log;
    private List<NpcMapLocation>? locations;

    public NpcNavigationService(
        IDataManager dataManager,
        IGameGui gameGui,
        IClientState clientState,
        ICommandManager commandManager,
        IFramework framework,
        IChatGui chatGui,
        IPluginLog log)
    {
        this.dataManager = dataManager;
        this.gameGui = gameGui;
        this.clientState = clientState;
        this.commandManager = commandManager;
        this.framework = framework;
        this.chatGui = chatGui;
        this.log = log;
    }

    public void Navigate(string args)
    {
        var query = args.Trim().Trim('"');
        if (string.IsNullOrWhiteSpace(query))
        {
            chatGui.PrintError("Usage: /npc <npc name>. Example: /npc Rowena");
            return;
        }

        var location = FindBestMatch(query);
        if (location is null)
        {
            chatGui.PrintError($"NPC not found: {query}");
            return;
        }

        var payload = new MapLinkPayload(location.TerritoryTypeId, location.MapId, location.X, location.Y);
        if (!gameGui.OpenMapWithMapLink(payload))
        {
            chatGui.PrintError($"Could not open map for {location.Name}.");
            return;
        }

        chatGui.Print($"NPC: {location.Name} - {location.ZoneName} ({location.X:0.#}, {location.Y:0.#})");
        framework.RunOnTick(() =>
        {
            if (!commandManager.ProcessCommand("/gtf"))
            {
                chatGui.PrintError("Map flag opened, but /gtf was not found. Install/enable your goto-flag plugin or run /gtf manually.");
            }
        }, TimeSpan.FromMilliseconds(250));
    }

    private NpcMapLocation? FindBestMatch(string query)
    {
        var queryKey = NormalizeSearchKey(query);
        if (string.IsNullOrWhiteSpace(queryKey))
        {
            return null;
        }

        return GetLocations()
            .Select(location => new
            {
                Location = location,
                Score = Score(location, queryKey),
            })
            .Where(match => match.Score > 0)
            .OrderByDescending(match => match.Score)
            .ThenBy(match => match.Location.Name.Length)
            .ThenBy(match => match.Location.ZoneName, StringComparer.OrdinalIgnoreCase)
            .Select(match => match.Location)
            .FirstOrDefault();
    }

    private int Score(NpcMapLocation location, string queryKey)
    {
        var nameKey = NormalizeSearchKey(location.Name);
        var score = 0;
        if (nameKey == queryKey)
        {
            score += 1000;
        }
        else if (nameKey.StartsWith(queryKey, StringComparison.OrdinalIgnoreCase))
        {
            score += 700;
        }
        else if (nameKey.Contains(queryKey, StringComparison.OrdinalIgnoreCase))
        {
            score += 500;
        }
        else
        {
            return 0;
        }

        if (location.TerritoryTypeId == clientState.TerritoryType)
        {
            score += 100;
        }

        if (location.IsImportant)
        {
            score += 25;
        }

        return score;
    }

    private IReadOnlyList<NpcMapLocation> GetLocations()
    {
        if (locations is not null)
        {
            return locations;
        }

        locations = BuildLocations();
        return locations;
    }

    private List<NpcMapLocation> BuildLocations()
    {
        var results = new List<NpcMapLocation>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var residentSheet = dataManager.GetExcelSheet<ENpcResident>();
        var baseSheet = dataManager.GetExcelSheet<ENpcBase>();

        foreach (var level in dataManager.GetExcelSheet<Level>())
        {
            if (!TryGetResident(level, residentSheet, out var resident))
            {
                continue;
            }

            var name = resident.Singular.ToString();
            if (string.IsNullOrWhiteSpace(name) || IsPlaceholderName(name))
            {
                continue;
            }

            var map = level.Map.ValueNullable ?? level.Territory.ValueNullable?.Map.ValueNullable;
            var territory = level.Territory.ValueNullable;
            if (map is null || territory is null || map.Value.RowId == 0 || territory.Value.RowId == 0)
            {
                continue;
            }

            var mapCoordinates = MapUtil.WorldToMap(new Vector2(level.X, level.Z), map.Value);
            if (!IsUsableMapCoordinate(mapCoordinates.X) || !IsUsableMapCoordinate(mapCoordinates.Y))
            {
                continue;
            }

            var zoneName = FirstNonEmpty(
                territory.Value.PlaceName.Value.Name.ToString(),
                territory.Value.PlaceNameZone.Value.Name.ToString(),
                map.Value.PlaceName.Value.Name.ToString(),
                map.Value.PlaceNameSub.Value.Name.ToString());
            var mapName = FirstNonEmpty(
                map.Value.PlaceNameSub.Value.Name.ToString(),
                map.Value.PlaceName.Value.Name.ToString(),
                zoneName);

            if (string.IsNullOrWhiteSpace(zoneName))
            {
                continue;
            }

            var roundedX = MathF.Round(mapCoordinates.X, 1);
            var roundedY = MathF.Round(mapCoordinates.Y, 1);
            var key = $"{name}|{territory.Value.RowId}|{map.Value.RowId}|{roundedX:0.0}|{roundedY:0.0}";
            if (!seen.Add(key))
            {
                continue;
            }

            results.Add(new NpcMapLocation(
                name,
                zoneName,
                mapName,
                territory.Value.RowId,
                map.Value.RowId,
                roundedX,
                roundedY,
                IsImportantNpc(level, baseSheet)));
        }

        log.Information("Indexed {Count} NPC map locations.", results.Count);
        return results;
    }

    private static bool TryGetResident(Level level, Lumina.Excel.ExcelSheet<ENpcResident> residentSheet, out ENpcResident resident)
    {
        if (level.EventId.RowId != 0 && residentSheet.TryGetRow(level.EventId.RowId, out resident))
        {
            return true;
        }

        if (level.Object.RowId != 0 && residentSheet.TryGetRow(level.Object.RowId, out resident))
        {
            return true;
        }

        resident = default;
        return false;
    }

    private static bool IsImportantNpc(Level level, Lumina.Excel.ExcelSheet<ENpcBase> baseSheet)
    {
        if (level.Object.RowId != 0 && baseSheet.TryGetRow(level.Object.RowId, out var npcBase))
        {
            return npcBase.Important;
        }

        return level.EventId.RowId != 0 && baseSheet.TryGetRow(level.EventId.RowId, out npcBase) && npcBase.Important;
    }

    private static bool IsUsableMapCoordinate(float value)
    {
        return !float.IsNaN(value) && value >= 0f && value <= 50f;
    }

    private static bool IsPlaceholderName(string name)
    {
        var key = NormalizeSearchKey(name);
        return key.Length == 0 || key is "unknown" or "dummy" or "none";
    }

    private static string NormalizeSearchKey(string value)
    {
        value = value
            .Normalize()
            .ToLower(CultureInfo.InvariantCulture)
            .Replace('’', '\'')
            .Replace('`', '\'');
        return Regex.Replace(value, @"[^\p{L}\p{Nd}]+", string.Empty);
    }

    private static string FirstNonEmpty(params string[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;
    }
}
