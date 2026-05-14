using System.Globalization;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;
using Dalamud.Game.Text.SeStringHandling.Payloads;
using Dalamud.Plugin.Services;
using Lumina.Excel.Sheets;
using VaelarisUnlockList.Models;

namespace VaelarisUnlockList.Services;

public sealed class UnlockDataService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly IDataManager dataManager;
    private readonly IGameGui gameGui;
    private readonly IUnlockState unlockState;
    private readonly IPluginLog log;
    private readonly Configuration configuration;

    private readonly Dictionary<string, uint> questIdsByName = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, List<QuestNameTarget>> questTargetsByLooseName = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, List<TerritoryMapTarget>> territoryTargetsByPlace = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<uint, List<uint>> aetherCurrentIdsByTerritory = [];
    private readonly Dictionary<string, List<uint>> aetherCurrentIdsByZone = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<uint, uint> aetherCurrentIdByQuestId = [];

    private UnlockDataset dataset = new();

    public UnlockDataService(
        IDataManager dataManager,
        IGameGui gameGui,
        IUnlockState unlockState,
        IPluginLog log,
        Configuration configuration)
    {
        this.dataManager = dataManager;
        this.gameGui = gameGui;
        this.unlockState = unlockState;
        this.log = log;
        this.configuration = configuration;
    }

    public IReadOnlyList<UnlockableEntry> Items => dataset.Items;

    public string GeneratedAt => dataset.GeneratedAt;

    public void Load()
    {
        var assemblyDir = Plugin.PluginInterface.AssemblyLocation.Directory?.FullName
            ?? Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)
            ?? string.Empty;
        var dataPath = Path.Combine(assemblyDir, "Data", "unlockables.json");

        dataset = JsonSerializer.Deserialize<UnlockDataset>(File.ReadAllText(dataPath), JsonOptions) ?? new UnlockDataset();
        BuildQuestIndex();
        BuildTerritoryIndex();
        BuildAetherCurrentIndex();
        WarmResolvedIds();
        log.Information("Loaded {Count} Vaelaris unlockables from {Path}", dataset.Items.Count, dataPath);
    }

    public IEnumerable<ResolvedUnlockable> ResolveAll(bool currentZoneOnly, uint currentTerritoryType)
    {
        foreach (var item in dataset.Items.OrderBy(item => item.SortOrder))
        {
            var resolved = Resolve(item);
            if (currentZoneOnly && resolved.TerritoryTypeId != currentTerritoryType)
            {
                continue;
            }

            yield return resolved;
        }
    }

    public ResolvedUnlockable Resolve(UnlockableEntry item)
    {
        var gameData = GetMergedGameData(item);
        var questRowId = gameData.QuestId;
        var aetherCurrentRowId = gameData.AetherCurrentId;
        var autoTracked = questRowId is not null || aetherCurrentRowId is not null;
        var isComplete = IsManualComplete(item.Id)
            || (questRowId is not null && IsQuestComplete(questRowId.Value))
            || (aetherCurrentRowId is not null && IsAetherCurrentComplete(aetherCurrentRowId.Value));
        var mapTarget = ResolveMapTarget(item, gameData);

        return new ResolvedUnlockable
        {
            Entry = item,
            QuestRowId = questRowId,
            AetherCurrentRowId = aetherCurrentRowId,
            TerritoryTypeId = mapTarget?.TerritoryTypeId,
            MapId = mapTarget?.MapId,
            MapLocation = mapTarget?.Location,
            IsComplete = isComplete,
            IsAutoTracked = autoTracked,
        };
    }

    public void SetManualComplete(string id, bool isComplete)
    {
        if (isComplete)
        {
            configuration.ManualCompletedIds.Add(id);
        }
        else
        {
            configuration.ManualCompletedIds.Remove(id);
        }

        configuration.Save();
    }

    public string ExportResolvedDataset()
    {
        var clone = JsonSerializer.Deserialize<UnlockDataset>(JsonSerializer.Serialize(dataset, JsonOptions), JsonOptions) ?? new UnlockDataset();
        foreach (var item in clone.Items)
        {
            item.GameData = GetMergedGameData(item);
        }

        var outputPath = Path.Combine(Plugin.PluginInterface.ConfigDirectory.FullName, "unlockables.resolved.json");
        File.WriteAllText(outputPath, JsonSerializer.Serialize(clone, new JsonSerializerOptions(JsonOptions) { WriteIndented = true }));
        return outputPath;
    }

    public string ValidateResolvedIds()
    {
        var issues = new List<ValidationIssue>();

        foreach (var item in dataset.Items)
        {
            var gameData = GetMergedGameData(item);
            ValidateQuestId(item, gameData, issues);
            ValidateMapId(item, gameData, issues);
            ValidateAetherCurrentId(item, gameData, issues);
        }

        var report = new
        {
            generatedAt = DateTimeOffset.UtcNow.ToString("O"),
            summary = new
            {
                total = dataset.Items.Count,
                issues = issues.Count,
                errors = issues.Count(issue => issue.Severity == "error"),
                warnings = issues.Count(issue => issue.Severity == "warning"),
                byType = issues.GroupBy(issue => issue.Type).OrderBy(group => group.Key).ToDictionary(group => group.Key, group => group.Count()),
            },
            issues,
        };

        var outputPath = Path.Combine(Plugin.PluginInterface.ConfigDirectory.FullName, "id-validation-report.json");
        File.WriteAllText(outputPath, JsonSerializer.Serialize(report, new JsonSerializerOptions(JsonOptions) { WriteIndented = true }));
        return outputPath;
    }

    public bool OpenMap(ResolvedUnlockable unlockable)
    {
        if (!unlockable.CanOpenMap || unlockable.TerritoryTypeId is null || unlockable.MapId is null || unlockable.MapLocation?.X is null || unlockable.MapLocation.Y is null)
        {
            return false;
        }

        var payload = new MapLinkPayload(
            unlockable.TerritoryTypeId.Value,
            unlockable.MapId.Value,
            unlockable.MapLocation.X.Value,
            unlockable.MapLocation.Y.Value);

        return gameGui.OpenMapWithMapLink(payload);
    }

    private bool IsManualComplete(string id)
    {
        return configuration.ManualCompletedIds.Contains(id);
    }

    private void ValidateQuestId(UnlockableEntry item, GameDataIds gameData, List<ValidationIssue> issues)
    {
        var expectedNames = item.Completion.QuestNames
            .Concat(item.QuestNames)
            .Where(name => !string.IsNullOrWhiteSpace(name) && !IsGenericQuestName(name) && !IsAmbiguousMultiQuestName(name))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (expectedNames.Count == 0)
        {
            return;
        }

        if (gameData.QuestId is null)
        {
            AddIssue(issues, "warning", "MissingQuestId", item, string.Join(" / ", expectedNames), "", "Resolve quest ID or leave manual if this is not a real quest.");
            return;
        }

        if (!dataManager.GetExcelSheet<Quest>().TryGetRow(gameData.QuestId.Value, out var quest))
        {
            AddIssue(issues, "error", "InvalidQuestId", item, string.Join(" / ", expectedNames), gameData.QuestId.Value.ToString(CultureInfo.InvariantCulture), "Quest row does not exist.");
            return;
        }

        var actualName = quest.Name.ToString();
        if (!expectedNames.Any(name => NamesMatch(name, actualName)))
        {
            AddIssue(issues, "error", "QuestNameMismatch", item, string.Join(" / ", expectedNames), $"{gameData.QuestId}: {actualName}", "Quest ID points to a different quest name.");
        }
    }

    private void ValidateMapId(UnlockableEntry item, GameDataIds gameData, List<ValidationIssue> issues)
    {
        var expectedPlaces = item.Locations
            .Select(location => location.Place)
            .Concat([item.Zone])
            .Where(place => !string.IsNullOrWhiteSpace(place))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        var hasCoordinates = item.Locations.Any(location => location.X is not null && location.Y is not null);
        if (!hasCoordinates)
        {
            return;
        }

        if (gameData.TerritoryTypeId is null || gameData.MapId is null)
        {
            AddIssue(issues, "warning", "MissingMapId", item, string.Join(" / ", expectedPlaces), "", "Coordinates exist, but territory/map IDs are unresolved.");
            return;
        }

        if (!dataManager.GetExcelSheet<TerritoryType>().TryGetRow(gameData.TerritoryTypeId.Value, out var territory))
        {
            AddIssue(issues, "error", "InvalidTerritoryTypeId", item, string.Join(" / ", expectedPlaces), gameData.TerritoryTypeId.Value.ToString(CultureInfo.InvariantCulture), "TerritoryType row does not exist.");
            return;
        }

        if (!dataManager.GetExcelSheet<Map>().TryGetRow(gameData.MapId.Value, out var map))
        {
            AddIssue(issues, "error", "InvalidMapId", item, string.Join(" / ", expectedPlaces), gameData.MapId.Value.ToString(CultureInfo.InvariantCulture), "Map row does not exist.");
            return;
        }

        var actualNames = new[]
        {
            territory.PlaceName.Value.Name.ToString(),
            territory.PlaceNameZone.Value.Name.ToString(),
            map.PlaceName.Value.Name.ToString(),
            map.PlaceNameSub.Value.Name.ToString(),
        }.Where(name => !string.IsNullOrWhiteSpace(name)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

        if (expectedPlaces.Count > 0 && !expectedPlaces.Any(expected => actualNames.Any(actual => NamesMatch(expected, actual))))
        {
            AddIssue(issues, "warning", "MapPlaceMismatch", item, string.Join(" / ", expectedPlaces), $"{gameData.TerritoryTypeId}/{gameData.MapId}: {string.Join(" / ", actualNames)}", "Map opens, but place name differs from dataset.");
        }
    }

    private void ValidateAetherCurrentId(UnlockableEntry item, GameDataIds gameData, List<ValidationIssue> issues)
    {
        if (!string.Equals(item.Source, "aether-currents", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (gameData.AetherCurrentId is null)
        {
            AddIssue(issues, "warning", "MissingAetherCurrentId", item, item.Title, "", "Aether current item has no resolved current ID.");
            return;
        }

        if (!dataManager.GetExcelSheet<AetherCurrent>().TryGetRow(gameData.AetherCurrentId.Value, out var current))
        {
            AddIssue(issues, "error", "InvalidAetherCurrentId", item, item.Title, gameData.AetherCurrentId.Value.ToString(CultureInfo.InvariantCulture), "AetherCurrent row does not exist.");
            return;
        }

        if (gameData.QuestId is not null && current.Quest.RowId != 0 && current.Quest.RowId != gameData.QuestId)
        {
            AddIssue(issues, "error", "AetherQuestMismatch", item, gameData.QuestId.Value.ToString(CultureInfo.InvariantCulture), current.Quest.RowId.ToString(CultureInfo.InvariantCulture), "Aether current points to a different quest.");
        }
    }

    private static void AddIssue(List<ValidationIssue> issues, string severity, string type, UnlockableEntry item, string expected, string actual, string suggestion)
    {
        issues.Add(new ValidationIssue
        {
            Severity = severity,
            Type = type,
            Id = item.Id,
            Title = item.Title,
            Expected = expected,
            Actual = actual,
            Suggestion = suggestion,
        });
    }

    private static bool NamesMatch(string expected, string actual)
    {
        var expectedKey = NormalizeLooseKey(expected);
        var actualKey = NormalizeLooseKey(RemoveIconGlyphs(actual));
        return expectedKey == actualKey
            || expectedKey.StartsWith(actualKey, StringComparison.OrdinalIgnoreCase)
            || actualKey.StartsWith(expectedKey, StringComparison.OrdinalIgnoreCase)
            || Math.Abs(expectedKey.Length - actualKey.Length) <= 1
                && (expectedKey.Contains(actualKey, StringComparison.OrdinalIgnoreCase) || actualKey.Contains(expectedKey, StringComparison.OrdinalIgnoreCase));
    }

    private GameDataIds GetMergedGameData(UnlockableEntry item)
    {
        var merged = item.GameData.Clone();
        if (configuration.ResolvedGameDataIds.TryGetValue(item.Id, out var cached))
        {
            merged.QuestId ??= cached.QuestId;
            merged.TerritoryTypeId ??= cached.TerritoryTypeId;
            merged.MapId ??= cached.MapId;
            merged.AetherCurrentId ??= cached.AetherCurrentId;
            merged.UnlockLinkId ??= cached.UnlockLinkId;
        }

        SanitizeMergedGameData(item, merged);
        return merged;
    }

    private void SanitizeMergedGameData(UnlockableEntry item, GameDataIds gameData)
    {
        if (gameData.AetherCurrentId is not null
            && gameData.QuestId is not null
            && dataManager.GetExcelSheet<AetherCurrent>().TryGetRow(gameData.AetherCurrentId.Value, out var current)
            && current.Quest.RowId != 0
            && current.Quest.RowId != gameData.QuestId)
        {
            gameData.AetherCurrentId = null;
        }

        if (gameData.TerritoryTypeId is null || gameData.MapId is null)
        {
            return;
        }

        var expectedPlaces = item.Locations
            .Select(location => location.Place)
            .Concat([item.Zone])
            .Where(place => !string.IsNullOrWhiteSpace(place))
            .ToList();
        if (expectedPlaces.Count == 0)
        {
            return;
        }

        if (!dataManager.GetExcelSheet<TerritoryType>().TryGetRow(gameData.TerritoryTypeId.Value, out var territory)
            || !dataManager.GetExcelSheet<Map>().TryGetRow(gameData.MapId.Value, out var map))
        {
            gameData.TerritoryTypeId = null;
            gameData.MapId = null;
            return;
        }

        var actualPlaces = new[]
        {
            territory.PlaceName.Value.Name.ToString(),
            territory.PlaceNameZone.Value.Name.ToString(),
            map.PlaceName.Value.Name.ToString(),
            map.PlaceNameSub.Value.Name.ToString(),
        };

        if (!expectedPlaces.Any(expected => actualPlaces.Any(actual => NamesMatch(expected, actual))))
        {
            gameData.TerritoryTypeId = null;
            gameData.MapId = null;
        }
    }

    private void WarmResolvedIds()
    {
        var changed = false;
        foreach (var item in dataset.Items)
        {
            var resolved = GetMergedGameData(item);
            resolved.QuestId ??= ResolveQuestRowId(item);

            var mapTarget = ResolveMapTarget(item, resolved);
            resolved.TerritoryTypeId ??= mapTarget?.TerritoryTypeId;
            resolved.MapId ??= mapTarget?.MapId;
            resolved.AetherCurrentId ??= ResolveAetherCurrentRowId(item, resolved);

            if (!HasAnyResolvedId(resolved))
            {
                continue;
            }

            if (!configuration.ResolvedGameDataIds.TryGetValue(item.Id, out var cached)
                || cached.QuestId != resolved.QuestId
                || cached.TerritoryTypeId != resolved.TerritoryTypeId
                || cached.MapId != resolved.MapId
                || cached.AetherCurrentId != resolved.AetherCurrentId
                || cached.UnlockLinkId != resolved.UnlockLinkId)
            {
                configuration.ResolvedGameDataIds[item.Id] = resolved;
                changed = true;
            }
        }

        if (changed)
        {
            configuration.Save();
        }
    }

    private static bool HasAnyResolvedId(GameDataIds gameData)
    {
        return gameData.QuestId is not null
            || gameData.TerritoryTypeId is not null
            || gameData.MapId is not null
            || gameData.AetherCurrentId is not null
            || gameData.UnlockLinkId is not null;
    }

    private uint? ResolveQuestRowId(UnlockableEntry item)
    {
        if (item.GameData.QuestId is not null)
        {
            return item.GameData.QuestId;
        }

        foreach (var questName in ExpandQuestNameCandidates(item.Completion.QuestNames.Concat(item.QuestNames)))
        {
            if (IsGenericQuestName(questName))
            {
                continue;
            }

            if (questIdsByName.TryGetValue(NormalizeKey(questName), out var rowId))
            {
                return rowId;
            }

            var looseKey = NormalizeLooseKey(questName);
            if (questTargetsByLooseName.TryGetValue(looseKey, out var exactTargets) && exactTargets.Count == 1)
            {
                return exactTargets[0].RowId;
            }

            var containedTargets = questTargetsByLooseName.Values
                .SelectMany(targets => targets)
                .Where(target => target.LooseName.Contains(looseKey, StringComparison.OrdinalIgnoreCase) || looseKey.Contains(target.LooseName, StringComparison.OrdinalIgnoreCase))
                .GroupBy(target => target.RowId)
                .Select(group => group.First())
                .ToList();

            if (containedTargets.Count == 1)
            {
                return containedTargets[0].RowId;
            }
        }

        return null;
    }

    private uint? ResolveAetherCurrentRowId(UnlockableEntry item, GameDataIds gameData)
    {
        if (!string.Equals(item.Source, "aether-currents", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (gameData.AetherCurrentId is not null)
        {
            return gameData.AetherCurrentId;
        }

        if (gameData.QuestId is not null)
        {
            if (aetherCurrentIdByQuestId.TryGetValue(gameData.QuestId.Value, out var currentIdByQuest))
            {
                return currentIdByQuest;
            }
        }

        if (!string.Equals(item.Subtype, "Field", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var currentIds = ResolveAetherCurrentIdsForZone(item, gameData);
        if (currentIds.Count == 0)
        {
            return null;
        }

        var fieldIndex = GetFieldCurrentIndex(item);
        if (fieldIndex is null)
        {
            return null;
        }

        var fieldCurrents = currentIds
            .Select(id => dataManager.GetExcelSheet<AetherCurrent>().TryGetRow(id, out var current)
                ? new { Id = id, Current = current }
                : null)
            .Where(current => current is not null && current.Current.Quest.RowId == 0)
            .Select(current => current!.Id)
            .ToList();

        return fieldIndex.Value > 0 && fieldIndex.Value <= fieldCurrents.Count
            ? fieldCurrents[fieldIndex.Value - 1]
            : null;
    }

    private static int? GetFieldCurrentIndex(UnlockableEntry item)
    {
        var match = Regex.Match(item.Title, @"#(?<n>\d+)");
        if (match.Success && int.TryParse(match.Groups["n"].Value, out var fromTitle))
        {
            return fromTitle;
        }

        match = Regex.Match(item.Id, @"\|Field\|(?<n>\d+)$", RegexOptions.IgnoreCase);
        return match.Success && int.TryParse(match.Groups["n"].Value, out var fromId) ? fromId : null;
    }

    private bool IsQuestComplete(uint questRowId)
    {
        try
        {
            if (dataManager.GetExcelSheet<Quest>().TryGetRow(questRowId, out var quest))
            {
                return unlockState.IsQuestCompleted(quest);
            }
        }
        catch (Exception ex)
        {
            log.Debug(ex, "Could not check quest completion for row {QuestRowId}", questRowId);
        }

        return false;
    }

    private bool IsAetherCurrentComplete(uint aetherCurrentRowId)
    {
        try
        {
            if (dataManager.GetExcelSheet<AetherCurrent>().TryGetRow(aetherCurrentRowId, out var current))
            {
                return unlockState.IsAetherCurrentUnlocked(current);
            }
        }
        catch (Exception ex)
        {
            log.Debug(ex, "Could not check aether current completion for row {AetherCurrentRowId}", aetherCurrentRowId);
        }

        return false;
    }

    private ResolvedMapTarget? ResolveMapTarget(UnlockableEntry item, GameDataIds gameData)
    {
        if (gameData.TerritoryTypeId is not null && gameData.MapId is not null)
        {
            var explicitLocation = item.Locations.FirstOrDefault(location => location.X is not null && location.Y is not null);
            if (explicitLocation is not null)
            {
                return new ResolvedMapTarget(gameData.TerritoryTypeId.Value, gameData.MapId.Value, explicitLocation);
            }
        }

        var questMapTarget = ResolveMapTargetFromQuestIssuer(item, gameData);
        if (questMapTarget is not null)
        {
            return questMapTarget;
        }

        foreach (var location in item.Locations)
        {
            if (location.X is null || location.Y is null)
            {
                continue;
            }

            var place = FirstNonEmpty(location.Place, item.Zone);
            if (string.IsNullOrWhiteSpace(place))
            {
                continue;
            }

            if (!TryGetTerritoryTargets(place, out var targets))
            {
                continue;
            }

            var target = targets.FirstOrDefault(target => target.MapId != 0);
            if (target is not null)
            {
                return new ResolvedMapTarget(target.TerritoryTypeId, target.MapId, location);
            }
        }

        return null;
    }

    private ResolvedMapTarget? ResolveMapTargetFromQuestIssuer(UnlockableEntry item, GameDataIds gameData)
    {
        var location = item.Locations.FirstOrDefault(location => location.X is not null && location.Y is not null);
        if (location is null || gameData.QuestId is null)
        {
            return null;
        }

        if (!dataManager.GetExcelSheet<Quest>().TryGetRow(gameData.QuestId.Value, out var quest) || quest.IssuerLocation.RowId == 0)
        {
            return null;
        }

        var issuerLocation = quest.IssuerLocation.Value;
        var expectedPlaces = item.Locations
            .Select(location => location.Place)
            .Concat([item.Zone])
            .Where(place => !string.IsNullOrWhiteSpace(place))
            .ToList();
        var actualPlaces = new[]
        {
            issuerLocation.Territory.Value.PlaceName.Value.Name.ToString(),
            issuerLocation.Territory.Value.PlaceNameZone.Value.Name.ToString(),
            issuerLocation.Map.Value.PlaceName.Value.Name.ToString(),
            issuerLocation.Map.Value.PlaceNameSub.Value.Name.ToString(),
        };

        if (expectedPlaces.Count > 0 && !expectedPlaces.Any(expected => actualPlaces.Any(actual => NamesMatch(expected, actual))))
        {
            return null;
        }

        return issuerLocation.Territory.RowId != 0 && issuerLocation.Map.RowId != 0
            ? new ResolvedMapTarget(issuerLocation.Territory.RowId, issuerLocation.Map.RowId, location)
            : null;
    }

    private void BuildQuestIndex()
    {
        questIdsByName.Clear();
        questTargetsByLooseName.Clear();

        foreach (var quest in dataManager.GetExcelSheet<Quest>())
        {
            var name = quest.Name.ToString();
            if (string.IsNullOrWhiteSpace(name))
            {
                continue;
            }

            AddQuestName(name, quest.RowId);
        }
    }

    private void BuildTerritoryIndex()
    {
        territoryTargetsByPlace.Clear();

        foreach (var territory in dataManager.GetExcelSheet<TerritoryType>())
        {
            var placeName = territory.PlaceName.Value.Name.ToString();
            if (string.IsNullOrWhiteSpace(placeName))
            {
                continue;
            }

            AddTerritoryTarget(placeName, territory.RowId, territory.Map.RowId);

            var zoneName = territory.PlaceNameZone.Value.Name.ToString();
            AddTerritoryTarget(zoneName, territory.RowId, territory.Map.RowId);

            var mapPlaceName = territory.Map.Value.PlaceName.Value.Name.ToString();
            AddTerritoryTarget(mapPlaceName, territory.RowId, territory.Map.RowId);
        }
    }

    private void BuildAetherCurrentIndex()
    {
        aetherCurrentIdsByTerritory.Clear();
        aetherCurrentIdsByZone.Clear();
        aetherCurrentIdByQuestId.Clear();

        foreach (var set in dataManager.GetExcelSheet<AetherCurrentCompFlgSet>())
        {
            var territoryId = set.Territory.RowId;
            if (territoryId == 0)
            {
                continue;
            }

            var ids = new List<uint>();
            foreach (var current in set.AetherCurrents)
            {
                if (current.RowId != 0)
                {
                    ids.Add(current.RowId);
                }
            }

            if (ids.Count > 0)
            {
                aetherCurrentIdsByTerritory[territoryId] = ids;
                AddAetherZoneIndex(set.Territory.Value.PlaceName.Value.Name.ToString(), ids);
                AddAetherZoneIndex(set.Territory.Value.PlaceNameZone.Value.Name.ToString(), ids);
            }
        }

        foreach (var current in dataManager.GetExcelSheet<AetherCurrent>())
        {
            var questId = current.Quest.RowId;
            if (questId != 0)
            {
                aetherCurrentIdByQuestId.TryAdd(questId, current.RowId);
            }
        }
    }

    private List<uint> ResolveAetherCurrentIdsForZone(UnlockableEntry item, GameDataIds gameData)
    {
        if (gameData.TerritoryTypeId is not null && aetherCurrentIdsByTerritory.TryGetValue(gameData.TerritoryTypeId.Value, out var byTerritory))
        {
            return byTerritory;
        }

        var zoneKey = NormalizeLooseKey(item.Zone);
        return !string.IsNullOrWhiteSpace(zoneKey) && aetherCurrentIdsByZone.TryGetValue(zoneKey, out var byZone)
            ? byZone
            : [];
    }

    private void AddAetherZoneIndex(string zoneName, List<uint> ids)
    {
        var key = NormalizeLooseKey(zoneName);
        if (!string.IsNullOrWhiteSpace(key))
        {
            aetherCurrentIdsByZone[key] = ids;
        }
    }

    private void AddQuestName(string name, uint rowId)
    {
        var key = NormalizeKey(name);
        if (!string.IsNullOrWhiteSpace(key))
        {
            questIdsByName.TryAdd(key, rowId);
        }

        var looseKey = NormalizeLooseKey(name);
        if (!string.IsNullOrWhiteSpace(looseKey))
        {
            questIdsByName.TryAdd(looseKey, rowId);
            if (!questTargetsByLooseName.TryGetValue(looseKey, out var targets))
            {
                targets = [];
                questTargetsByLooseName[looseKey] = targets;
            }

            targets.Add(new QuestNameTarget(rowId, name, looseKey));
        }
    }

    private static IEnumerable<string> ExpandQuestNameCandidates(IEnumerable<string> names)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rawName in names)
        {
            foreach (var candidate in ExpandQuestNameCandidate(rawName))
            {
                if (seen.Add(candidate))
                {
                    yield return candidate;
                }
            }
        }
    }

    private static IEnumerable<string> ExpandQuestNameCandidate(string rawName)
    {
        var name = CleanQuestName(rawName);
        if (string.IsNullOrWhiteSpace(name))
        {
            yield break;
        }

        yield return name;

        foreach (var part in name.Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var cleanPart = CleanQuestName(part);
            if (!string.IsNullOrWhiteSpace(cleanPart))
            {
                yield return cleanPart;
            }
        }

        var withoutParentheses = Regex.Replace(name, @"\s*\([^)]*\)", string.Empty).Trim();
        if (!string.IsNullOrWhiteSpace(withoutParentheses) && !string.Equals(withoutParentheses, name, StringComparison.OrdinalIgnoreCase))
        {
            yield return withoutParentheses;
        }

        if (name.StartsWith("A Relic Reborn:", StringComparison.OrdinalIgnoreCase))
        {
            yield return "A Relic Reborn";
        }
    }

    private static string CleanQuestName(string value)
    {
        var cleaned = NormalizeApostrophes(value)
            .Replace("*", string.Empty, StringComparison.Ordinal)
            .Replace("(Quest)", string.Empty, StringComparison.OrdinalIgnoreCase)
            .Replace("Foosteps", "Footsteps", StringComparison.OrdinalIgnoreCase)
            .Trim();

        cleaned = Regex.Replace(cleaned, @"\s+", " ");
        return cleaned;
    }

    private static bool IsGenericQuestName(string name)
    {
        var loose = NormalizeLooseKey(name);
        return loose is "" or "DUNGEON" or "QUEST" or "TRIAL" or "RAID" or "CONTENT" or "UNLOCK"
            || name.Trim() == "-";
    }

    private static bool IsAmbiguousMultiQuestName(string name)
    {
        var loose = NormalizeLooseKey(name);
        return loose is "THECOMPANYYOUKEEP" or "COMPANYYOUKEEP" or "MYLITTLECHOCOBO" or "SQUADRONANDCOMMANDER" or "ARELICREBORN" or "RELICREBORN";
    }

    private void AddTerritoryTarget(string placeName, uint territoryId, uint mapId)
    {
        var key = NormalizeKey(placeName);
        if (!string.IsNullOrWhiteSpace(key))
        {
            AddTerritoryTargetByKey(key, territoryId, mapId);
        }

        var looseKey = NormalizeLooseKey(placeName);
        if (!string.IsNullOrWhiteSpace(looseKey))
        {
            AddTerritoryTargetByKey(looseKey, territoryId, mapId);
        }
    }

    private void AddTerritoryTargetByKey(string key, uint territoryId, uint mapId)
    {
        if (!territoryTargetsByPlace.TryGetValue(key, out var targets))
        {
            targets = [];
            territoryTargetsByPlace[key] = targets;
        }

        if (targets.All(target => target.TerritoryTypeId != territoryId || target.MapId != mapId))
        {
            targets.Add(new TerritoryMapTarget(territoryId, mapId));
        }
    }

    private bool TryGetTerritoryTargets(string place, out List<TerritoryMapTarget> targets)
    {
        return territoryTargetsByPlace.TryGetValue(NormalizeKey(place), out targets!)
            || territoryTargetsByPlace.TryGetValue(NormalizeLooseKey(place), out targets!);
    }

    private static string FirstNonEmpty(params string[] values)
    {
        return values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value)) ?? string.Empty;
    }

    private static string NormalizeKey(string value)
    {
        return NormalizeApostrophes(value).Trim().Normalize().ToUpper(CultureInfo.InvariantCulture);
    }

    private static string NormalizeLooseKey(string value)
    {
        var normalized = NormalizeKey(value);
        var loose = Regex.Replace(normalized, @"[^\p{L}\p{Nd}]+", string.Empty);
        return loose.StartsWith("THE", StringComparison.OrdinalIgnoreCase) && loose.Length > 3
            ? loose[3..]
            : loose;
    }

    private static string NormalizeApostrophes(string value)
    {
        return value
            .Replace('’', '\'')
            .Replace('`', '\'')
            .Replace("Foosteps", "Footsteps", StringComparison.OrdinalIgnoreCase);
    }

    private static string RemoveIconGlyphs(string value)
    {
        return Regex.Replace(value, @"[\uE000-\uF8FF]", string.Empty).Trim();
    }

    private sealed record TerritoryMapTarget(uint TerritoryTypeId, uint MapId);

    private sealed record QuestNameTarget(uint RowId, string Name, string LooseName);

    private sealed record ResolvedMapTarget(uint TerritoryTypeId, uint MapId, UnlockLocation Location);
}
