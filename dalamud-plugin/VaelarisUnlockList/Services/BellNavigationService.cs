using System.Numerics;
using Dalamud.Game.Text.SeStringHandling.Payloads;
using Dalamud.Plugin.Services;
using Dalamud.Utility;
using Lumina.Excel.Sheets;

namespace VaelarisUnlockList.Services;

public sealed class BellNavigationService
{
    private readonly IDataManager dataManager;
    private readonly IGameGui gameGui;
    private readonly IClientState clientState;
    private readonly IObjectTable objectTable;
    private readonly ICommandManager commandManager;
    private readonly IFramework framework;
    private readonly IChatGui chatGui;
    private readonly IPluginLog log;
    private List<BellMapLocation>? locations;

    public BellNavigationService(
        IDataManager dataManager,
        IGameGui gameGui,
        IClientState clientState,
        IObjectTable objectTable,
        ICommandManager commandManager,
        IFramework framework,
        IChatGui chatGui,
        IPluginLog log)
    {
        this.dataManager = dataManager;
        this.gameGui = gameGui;
        this.clientState = clientState;
        this.objectTable = objectTable;
        this.commandManager = commandManager;
        this.framework = framework;
        this.chatGui = chatGui;
        this.log = log;
    }

    public void Navigate()
    {
        var player = objectTable.LocalPlayer;
        if (player is null)
        {
            chatGui.PrintError("Could not find your current position.");
            return;
        }

        var currentTerritory = clientState.TerritoryType;
        var bell = FindBestBell(player.Position, currentTerritory);

        if (bell is null)
        {
            chatGui.PrintError("No retainer bell location found.");
            return;
        }

        var payload = new MapLinkPayload(bell.TerritoryTypeId, bell.MapId, bell.X, bell.Y);
        if (!gameGui.OpenMapWithMapLink(payload))
        {
            chatGui.PrintError("Could not open map for the nearest retainer bell.");
            return;
        }

        var currentZoneText = bell.TerritoryTypeId == currentTerritory ? string.Empty : " in a nearby zone";
        chatGui.Print($"Nearest retainer bell{currentZoneText}: {bell.ZoneName} ({bell.X:0.#}, {bell.Y:0.#})");
        framework.RunOnTick(() =>
        {
            if (!commandManager.ProcessCommand("/gtf"))
            {
                chatGui.PrintError("Map flag opened, but /gtf was not found. Install/enable your goto-flag plugin or run /gtf manually.");
            }
        }, TimeSpan.FromMilliseconds(250));
    }

    private BellMapLocation? FindBestBell(Vector3 playerPosition, uint currentTerritory)
    {
        var allLocations = GetLocations();
        var sameTerritory = allLocations
            .Where(location => location.TerritoryTypeId == currentTerritory)
            .OrderBy(location => Vector3.DistanceSquared(playerPosition, location.WorldPosition))
            .FirstOrDefault();
        if (sameTerritory is not null)
        {
            return sameTerritory;
        }

        var currentNames = GetCurrentTerritoryNames(currentTerritory);
        var sameArea = allLocations
            .Select(location => new
            {
                Location = location,
                Score = ScoreNearbyZone(location, currentNames),
            })
            .Where(match => match.Score > 0)
            .OrderByDescending(match => match.Score)
            .ThenBy(match => Vector3.DistanceSquared(playerPosition, match.Location.WorldPosition))
            .ThenBy(match => match.Location.ZoneName, StringComparer.OrdinalIgnoreCase)
            .Select(match => match.Location)
            .FirstOrDefault();
        if (sameArea is not null)
        {
            return sameArea;
        }

        return allLocations
            .OrderBy(location => IsPreferredHub(location) ? 0 : 1)
            .ThenBy(location => location.ZoneName, StringComparer.OrdinalIgnoreCase)
            .ThenBy(location => location.X)
            .ThenBy(location => location.Y)
            .FirstOrDefault();
    }

    private HashSet<string> GetCurrentTerritoryNames(uint territoryTypeId)
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (!dataManager.GetExcelSheet<TerritoryType>().TryGetRow(territoryTypeId, out var territory))
        {
            return names;
        }

        AddName(names, territory.PlaceName.Value.Name.ToString());
        AddName(names, territory.PlaceNameZone.Value.Name.ToString());
        AddName(names, territory.Map.Value.PlaceName.Value.Name.ToString());
        AddName(names, territory.Map.Value.PlaceNameSub.Value.Name.ToString());
        return names;
    }

    private static int ScoreNearbyZone(BellMapLocation location, HashSet<string> currentNames)
    {
        var zoneKey = NormalizePlaceName(location.ZoneName);
        if (string.IsNullOrWhiteSpace(zoneKey))
        {
            return 0;
        }

        if (currentNames.Contains(zoneKey))
        {
            return 100;
        }

        return currentNames.Any(name => name.Contains(zoneKey, StringComparison.OrdinalIgnoreCase)
            || zoneKey.Contains(name, StringComparison.OrdinalIgnoreCase))
            ? 50
            : 0;
    }

    private IReadOnlyList<BellMapLocation> GetLocations()
    {
        if (locations is not null)
        {
            return locations;
        }

        locations = BuildLocations();
        return locations;
    }

    private List<BellMapLocation> BuildLocations()
    {
        var results = new List<BellMapLocation>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var bellNameIds = dataManager.GetExcelSheet<EObjName>()
            .Where(name => IsRetainerBellName(name.Singular.ToString()))
            .Select(name => name.RowId)
            .ToHashSet();
        var bellObjectIds = dataManager.GetExcelSheet<EObj>()
            .Where(obj => bellNameIds.Contains(obj.RowId) || bellNameIds.Contains(obj.Data.RowId))
            .Select(obj => obj.RowId)
            .Concat(bellNameIds)
            .ToHashSet();

        foreach (var level in dataManager.GetExcelSheet<Level>())
        {
            if (!bellObjectIds.Contains(level.Object.RowId) && !bellObjectIds.Contains(level.EventId.RowId))
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
            var roundedX = MathF.Round(mapCoordinates.X, 1);
            var roundedY = MathF.Round(mapCoordinates.Y, 1);
            var key = $"{territory.Value.RowId}|{map.Value.RowId}|{roundedX:0.0}|{roundedY:0.0}";
            if (!seen.Add(key))
            {
                continue;
            }

            results.Add(new BellMapLocation(
                "Summoning Bell",
                zoneName,
                territory.Value.RowId,
                map.Value.RowId,
                roundedX,
                roundedY,
                new Vector3(level.X, level.Y, level.Z)));
        }

        log.Information("Indexed {Count} retainer bell map locations.", results.Count);
        return results;
    }

    private static bool IsRetainerBellName(string name)
    {
        return name.Equals("Summoning Bell", StringComparison.OrdinalIgnoreCase)
            || name.Equals("Retainer Bell", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsUsableMapCoordinate(float value)
    {
        return !float.IsNaN(value) && value >= 0f && value <= 50f;
    }

    private static bool IsPreferredHub(BellMapLocation location)
    {
        return location.ZoneName.Equals("Limsa Lominsa Lower Decks", StringComparison.OrdinalIgnoreCase)
            || location.ZoneName.Equals("Ul'dah - Steps of Thal", StringComparison.OrdinalIgnoreCase)
            || location.ZoneName.Equals("New Gridania", StringComparison.OrdinalIgnoreCase)
            || location.ZoneName.Equals("Old Sharlayan", StringComparison.OrdinalIgnoreCase)
            || location.ZoneName.Equals("Tuliyollal", StringComparison.OrdinalIgnoreCase);
    }

    private static void AddName(HashSet<string> names, string name)
    {
        var key = NormalizePlaceName(name);
        if (!string.IsNullOrWhiteSpace(key))
        {
            names.Add(key);
        }
    }

    private static string NormalizePlaceName(string value)
    {
        return value
            .Normalize()
            .ToLowerInvariant()
            .Replace("'", string.Empty)
            .Replace(" ", string.Empty)
            .Replace("-", string.Empty);
    }

    private static string FirstNonEmpty(params string[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;
    }
}
