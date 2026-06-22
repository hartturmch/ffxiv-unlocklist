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
        var housingFallback = FindHousingFallback(currentNames, allLocations);
        if (housingFallback is not null)
        {
            return housingFallback;
        }

        var regionalFallback = FindRegionalFallback(currentTerritory, currentNames, allLocations);
        if (regionalFallback is not null)
        {
            return regionalFallback;
        }

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

        return null;
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
        AddName(names, territory.PlaceNameRegion.Value.Name.ToString());
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
        AddKnownBellLocations(results, seen);

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

    private void AddKnownBellLocations(List<BellMapLocation> results, HashSet<string> seen)
    {
        foreach (var known in KnownBellLocations)
        {
            if (!dataManager.GetExcelSheet<TerritoryType>().TryGetRow(known.TerritoryTypeId, out var territory))
            {
                continue;
            }

            var map = territory.Map.ValueNullable;
            if (map is null || map.Value.RowId == 0)
            {
                continue;
            }

            var mapCoordinates = MapUtil.WorldToMap(new Vector2(known.WorldPosition.X, known.WorldPosition.Z), map.Value);
            if (!IsUsableMapCoordinate(mapCoordinates.X) || !IsUsableMapCoordinate(mapCoordinates.Y))
            {
                continue;
            }

            var zoneName = FirstNonEmpty(
                territory.PlaceName.Value.Name.ToString(),
                territory.PlaceNameZone.Value.Name.ToString(),
                map.Value.PlaceName.Value.Name.ToString(),
                map.Value.PlaceNameSub.Value.Name.ToString(),
                known.ZoneName);
            var roundedX = MathF.Round(mapCoordinates.X, 1);
            var roundedY = MathF.Round(mapCoordinates.Y, 1);
            var key = $"{known.TerritoryTypeId}|{map.Value.RowId}|{roundedX:0.0}|{roundedY:0.0}";
            if (!seen.Add(key))
            {
                continue;
            }

            results.Add(new BellMapLocation(
                "Summoning Bell",
                zoneName,
                known.TerritoryTypeId,
                map.Value.RowId,
                roundedX,
                roundedY,
                known.WorldPosition));
        }
    }

    private static bool IsRetainerBellName(string name)
    {
        return name.Equals("Summoning Bell", StringComparison.OrdinalIgnoreCase)
            || name.Equals("Retainer Bell", StringComparison.OrdinalIgnoreCase);
    }

    private static BellMapLocation? FindHousingFallback(HashSet<string> currentNames, IReadOnlyList<BellMapLocation> locations)
    {
        var territoryId = currentNames switch
        {
            var names when ContainsAny(names, "mist", "topmast") => 129u,
            var names when ContainsAny(names, "thelavenderbeds", "lavenderbeds", "lilyhills") => 133u,
            var names when ContainsAny(names, "thegoblet", "goblet", "sultanasbreath") => 131u,
            var names when ContainsAny(names, "shirogane", "kobaigoten") => 628u,
            var names when ContainsAny(names, "empyreum", "ingleside") => 419u,
            _ => 0u,
        };

        return territoryId == 0
            ? null
            : locations.FirstOrDefault(location => location.TerritoryTypeId == territoryId);
    }

    private BellMapLocation? FindRegionalFallback(uint currentTerritory, HashSet<string> currentNames, IReadOnlyList<BellMapLocation> locations)
    {
        var territoryId = currentNames switch
        {
            var names when ContainsAny(names, "lanoscea", "limsalominsa", "mist", "wolvesdenpier") => 129u,
            var names when ContainsAny(names, "blackshroud", "gridania", "lavenderbeds") => 133u,
            var names when ContainsAny(names, "thanalan", "uldah", "goblet", "goldsaucer") => 131u,
            var names when ContainsAny(names, "coerthas", "dravania", "abalanthiasspine", "ishgard") => 419u,
            var names when ContainsAny(names, "gyrabania", "rhalgrsreach") => 635u,
            var names when ContainsAny(names, "hingashi", "othard", "kugane", "rubysea", "yanxia", "azimsteppe") => 628u,
            var names when ContainsAny(names, "kholusia", "eulmore") => 820u,
            var names when ContainsAny(names, "norvrandt", "lakeland", "amharaeng", "ilmheg", "raktikagreatwood", "tempest", "crystarium") => 819u,
            var names when ContainsAny(names, "thavnair", "radzathan") => 963u,
            var names when ContainsAny(names, "northernempty", "oldsharlayan", "labyrinthos", "garlemald", "marelamentorum", "ultimathule") => 962u,
            var names when ContainsAny(names, "xaktural", "shaaloani", "heritagefound", "solutionnine", "livingmemory") => 1186u,
            var names when ContainsAny(names, "yoktural", "tuliyollal", "urqopacha", "kozamauka", "yaktel") => 1185u,
            _ => GetExpansionHubTerritoryId(currentTerritory),
        };

        return territoryId == 0
            ? null
            : locations.FirstOrDefault(location => location.TerritoryTypeId == territoryId);
    }

    private uint GetExpansionHubTerritoryId(uint currentTerritory)
    {
        if (!dataManager.GetExcelSheet<TerritoryType>().TryGetRow(currentTerritory, out var territory))
        {
            return 0;
        }

        return territory.ExVersion.RowId switch
        {
            0 => 131u,
            1 => 419u,
            2 => 635u,
            3 => 819u,
            4 => 962u,
            5 => 1185u,
            _ => 0u,
        };
    }

    private static bool IsUsableMapCoordinate(float value)
    {
        return !float.IsNaN(value) && value >= 0f && value <= 50f;
    }

    private static bool ContainsAny(HashSet<string> names, params string[] candidates)
    {
        return candidates.Any(candidate => names.Contains(candidate));
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

    private static readonly KnownBellLocation[] KnownBellLocations =
    [
        new("Limsa Lominsa Lower Decks", 129, new Vector3(-123.88806f, 17.990356f, 21.469421f)),
        new("Old Gridania", 133, new Vector3(171.00781f, 15.487854f, -101.487854f)),
        new("Ul'dah - Steps of Thal", 131, new Vector3(148.91272f, 3.982544f, -44.205383f)),
        new("The Pillars", 419, new Vector3(-151.1712f, -12.64978f, -11.7647705f)),
        new("Rhalgr's Reach", 635, new Vector3(-57.63336f, -0.015319824f, 49.30188f)),
        new("Kugane", 628, new Vector3(19.394226f, 4.043579f, 53.025024f)),
        new("The Doman Enclave", 759, new Vector3(60.56299f, -0.015319824f, -3.982666f)),
        new("The Crystarium", 819, new Vector3(-69.840576f, -7.7058716f, 123.49121f)),
        new("Eulmore", 820, new Vector3(7.1869507f, 83.17688f, 31.448853f)),
        new("Old Sharlayan", 962, new Vector3(42.09961f, 2.517002f, -39.414062f)),
        new("Radz-at-Han", 963, new Vector3(26.749023f, -0.015319824f, -53.696533f)),
        new("Tuliyollal", 1185, new Vector3(18.57019f, -14.023071f, 120.408936f)),
        new("Solution Nine", 1186, new Vector3(-151.59845f, 0.59503174f, -15.304871f)),
    ];

    private sealed record KnownBellLocation(string ZoneName, uint TerritoryTypeId, Vector3 WorldPosition);
}
