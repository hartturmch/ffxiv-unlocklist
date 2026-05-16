using System.Numerics;
using Dalamud.Bindings.ImGui;
using Dalamud.Interface.Utility;
using Dalamud.Interface.Utility.Raii;
using Dalamud.Interface.Windowing;
using VaelarisUnlockList.Models;
using VaelarisUnlockList.Services;

namespace VaelarisUnlockList.Windows;

public sealed class MainWindow : Window, IDisposable
{
    private static readonly TimeSpan RefreshInterval = TimeSpan.FromSeconds(10);

    private readonly Plugin plugin;
    private string search = string.Empty;
    private string categorySearch = string.Empty;
    private string mapSearch = string.Empty;
    private List<ResolvedUnlockable> resolvedCache = [];
    private DateTime nextRefreshUtc = DateTime.MinValue;

    public MainWindow(Plugin plugin)
        : base("Unlock List##VaelarisUnlockList")
    {
        this.plugin = plugin;
        SizeConstraints = new WindowSizeConstraints
        {
            MinimumSize = new Vector2(520, 420),
            MaximumSize = new Vector2(float.MaxValue, float.MaxValue),
        };
    }

    public void Dispose()
    {
    }

    public override void Draw()
    {
        var currentTerritory = Plugin.ClientState.TerritoryType;
        var resolvedItems = GetResolvedCache(currentTerritory);

        DrawToolbar(resolvedItems, currentTerritory);

        var hasSearch = HasSearchText();
        var allItems = plugin.Configuration.CurrentZoneOnly
            ? resolvedItems.Where(item => item.TerritoryTypeId == currentTerritory).ToList()
            : resolvedItems;
        var filteredItems = allItems
            .Where(MatchesSearch)
            .Where(item => hasSearch || IsStatusFilter("Complete") || plugin.Configuration.ShowCompleted || !item.IsComplete)
            .Where(MatchesCategoryFilter)
            .Where(MatchesMapFilter)
            .Where(item => hasSearch || MatchesStatusFilter(item))
            .ToList();

        var total = allItems.Count;
        var complete = allItems.Count(item => item.IsComplete);
        ImGui.TextUnformatted($"{complete} / {total} complete");

        ImGui.Separator();

        var footerHeight = ImGui.GetFrameHeightWithSpacing() + (8f * ImGuiHelpers.GlobalScale);
        using var child = ImRaii.Child("unlock-list", new Vector2(0, -footerHeight), true);
        if (!child.Success)
        {
            return;
        }

        foreach (var group in filteredItems.GroupBy(item => item.Entry.Section))
        {
            ImGui.Spacing();
            ImGui.TextUnformatted(group.Key);
            ImGui.Separator();
            foreach (var item in group)
            {
                DrawUnlockable(item);
            }
        }

        child.Dispose();
        ImGui.Separator();
        DrawFooterFilters();
    }

    private void DrawToolbar(IReadOnlyList<ResolvedUnlockable> resolvedItems, uint currentTerritory)
    {
        ImGui.SetNextItemWidth(Math.Max(220f, ImGui.GetContentRegionAvail().X - (260f * ImGuiHelpers.GlobalScale)));
        ImGui.InputTextWithHint("##unlock-search", "Search unlocks, quests, zones...", ref search, 160);

        ImGui.SameLine();
        if (ImGui.Button("Reload"))
        {
            plugin.UnlockData.Load();
            InvalidateResolvedCache();
        }

        var currentZoneOnly = plugin.Configuration.CurrentZoneOnly;
        if (ImGui.Checkbox("Current zone", ref currentZoneOnly))
        {
            plugin.Configuration.CurrentZoneOnly = currentZoneOnly;
            plugin.Configuration.Save();
        }

        ImGui.SameLine();
        var showCompleted = plugin.Configuration.ShowCompleted;
        if (ImGui.Checkbox("Show completed", ref showCompleted))
        {
            plugin.Configuration.ShowCompleted = showCompleted;
            plugin.Configuration.Save();
        }

        DrawFilterCombos();

        var nextCurrentZone = resolvedItems.FirstOrDefault(item => !item.IsComplete && item.CanOpenMap && item.TerritoryTypeId == currentTerritory);

        if (nextCurrentZone is null)
        {
            ImGui.BeginDisabled();
        }

        if (ImGui.Button("Next unlock in this zone") && nextCurrentZone is not null)
        {
            plugin.UnlockData.OpenMap(nextCurrentZone);
        }

        if (ImGui.IsItemHovered())
        {
            ImGui.SetTooltip("Open the map flag for the next incomplete unlock in your current zone.");
        }

        if (nextCurrentZone is null)
        {
            ImGui.EndDisabled();
        }

        ImGui.SameLine();
        var showDevTools = plugin.Configuration.ShowDevTools;
        if (ImGui.Checkbox("Dev", ref showDevTools))
        {
            plugin.Configuration.ShowDevTools = showDevTools;
            plugin.Configuration.Save();
        }

        if (plugin.Configuration.ShowDevTools)
        {
            ImGui.SameLine();
            if (ImGui.Button("Export Resolved IDs (Dev)"))
            {
                plugin.UnlockData.ExportResolvedDataset();
            }

            if (ImGui.IsItemHovered())
            {
                ImGui.SetTooltip($"Export cached game IDs to unlockables.resolved.json.\nData: {plugin.UnlockData.GeneratedAt}\nResolved IDs cached: {plugin.Configuration.ResolvedGameDataIds.Count}");
            }

            ImGui.SameLine();
            if (ImGui.Button("Validate IDs (Dev)"))
            {
                plugin.UnlockData.ValidateResolvedIds();
            }

            if (ImGui.IsItemHovered())
            {
                ImGui.SetTooltip("Write id-validation-report.json with missing or suspicious IDs.");
            }
        }
    }

    private void DrawFilterCombos()
    {
        var categoryFilter = plugin.Configuration.CategoryFilter;
        var categories = plugin.UnlockData.Items
            .Select(item => item.Category)
            .Where(category => !string.IsNullOrWhiteSpace(category))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToList();

        ImGui.SetNextItemWidth(220f * ImGuiHelpers.GlobalScale);
        if (ImGui.BeginCombo("Category", string.IsNullOrWhiteSpace(categoryFilter) ? "All" : categoryFilter))
        {
            ImGui.SetNextItemWidth(-1);
            ImGui.InputTextWithHint("##category-search", "Filter categories...", ref categorySearch, 80);
            ImGui.Separator();

            if (ImGui.Selectable("All", string.IsNullOrWhiteSpace(categoryFilter)))
            {
                plugin.Configuration.CategoryFilter = string.Empty;
                plugin.Configuration.Save();
            }

            foreach (var category in categories.Where(category => string.IsNullOrWhiteSpace(categorySearch) || category.Contains(categorySearch, StringComparison.OrdinalIgnoreCase)))
            {
                if (ImGui.Selectable(category, string.Equals(categoryFilter, category, StringComparison.OrdinalIgnoreCase)))
                {
                    plugin.Configuration.CategoryFilter = category;
                    plugin.Configuration.Save();
                }
            }

            ImGui.EndCombo();
        }

        ImGui.SameLine();
        DrawMapFilterCombo();
    }

    private void DrawMapFilterCombo()
    {
        var mapFilter = plugin.Configuration.MapFilter;
        var maps = plugin.UnlockData.Items
            .Select(item => string.IsNullOrWhiteSpace(item.Zone) ? item.Locations.FirstOrDefault()?.Place ?? string.Empty : item.Zone)
            .Where(zone => !string.IsNullOrWhiteSpace(zone))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToList();

        ImGui.SetNextItemWidth(220f * ImGuiHelpers.GlobalScale);
        if (ImGui.BeginCombo("Map", string.IsNullOrWhiteSpace(mapFilter) ? "All" : mapFilter))
        {
            ImGui.SetNextItemWidth(-1);
            ImGui.InputTextWithHint("##map-search", "Filter maps...", ref mapSearch, 80);
            ImGui.Separator();

            if (ImGui.Selectable("All", string.IsNullOrWhiteSpace(mapFilter)))
            {
                plugin.Configuration.MapFilter = string.Empty;
                plugin.Configuration.Save();
            }

            foreach (var map in maps.Where(map => string.IsNullOrWhiteSpace(mapSearch) || map.Contains(mapSearch, StringComparison.OrdinalIgnoreCase)))
            {
                if (ImGui.Selectable(map, string.Equals(mapFilter, map, StringComparison.OrdinalIgnoreCase)))
                {
                    plugin.Configuration.MapFilter = map;
                    plugin.Configuration.Save();
                }
            }

            ImGui.EndCombo();
        }
    }

    private void DrawFooterFilters()
    {
        var statusFilter = plugin.Configuration.StatusFilter;
        ImGui.SetNextItemWidth(160f * ImGuiHelpers.GlobalScale);
        if (ImGui.BeginCombo("Status", string.IsNullOrWhiteSpace(statusFilter) ? "All" : statusFilter))
        {
            foreach (var status in new[] { "All", "Open", "Complete", "Manual", "Needs Manual Check" })
            {
                var value = status == "All" ? string.Empty : status;
                if (ImGui.Selectable(status, string.Equals(statusFilter, value, StringComparison.OrdinalIgnoreCase)))
                {
                    plugin.Configuration.StatusFilter = value;
                    plugin.Configuration.Save();
                }
            }

            ImGui.EndCombo();
        }
    }

    private void DrawUnlockable(ResolvedUnlockable item)
    {
        DrawStatusBadge(item);
        ImGui.SameLine();

        var title = $"{item.Entry.Title}##{item.Entry.Id}";
        if (!ImGui.TreeNodeEx(title))
        {
            return;
        }

        DrawBadges(item);

        if (!string.IsNullOrWhiteSpace(item.Entry.UnlockName) && item.Entry.UnlockName != item.Entry.Title)
        {
            ImGui.TextWrapped($"Unlock: {item.Entry.UnlockName}");
        }

        if (item.Entry.QuestNames.Count > 0)
        {
            DrawQuestList("Quest", item.Entry.QuestNames);
        }

        var requirements = ExpandAlternativeRequirements(ExtractRequirements(item.Entry.Instructions), plugin.UnlockData.Items);
        if (requirements.Count > 0)
        {
            DrawQuestList("Requirement", requirements);
        }

        var locationText = item.MapLocation?.Text ?? item.Entry.Locations.FirstOrDefault()?.Text;
        if (!string.IsNullOrWhiteSpace(locationText))
        {
            ImGui.TextWrapped($"Location: {locationText}");
        }

        if (!string.IsNullOrWhiteSpace(item.Entry.Instructions))
        {
            ImGui.TextWrapped(item.Entry.Instructions);
        }

        DrawActions(item);
        ImGui.TreePop();
    }

    private void DrawBadges(ResolvedUnlockable item)
    {
        ImGui.TextDisabled(item.Entry.Category);

        if (!string.IsNullOrWhiteSpace(item.Entry.Subtype))
        {
            ImGui.SameLine();
            ImGui.TextDisabled(item.Entry.Subtype);
        }

        if (!string.IsNullOrWhiteSpace(item.Entry.Level))
        {
            ImGui.SameLine();
            ImGui.TextDisabled($"Lvl {item.Entry.Level}");
        }

        if (!string.IsNullOrWhiteSpace(item.Entry.Zone))
        {
            ImGui.SameLine();
            ImGui.TextDisabled(item.Entry.Zone);
        }

        if (item.QuestRowIds.Count > 0)
        {
            ImGui.SameLine();
            ImGui.TextDisabled(item.QuestRowIds.Count == 1
                ? $"Quest #{item.QuestRowIds[0]}"
                : $"Quests {string.Join("/", item.QuestRowIds.Take(3))}{(item.QuestRowIds.Count > 3 ? "+" : string.Empty)}");
        }

        if (item.AetherCurrentRowId is not null)
        {
            ImGui.SameLine();
            ImGui.TextDisabled($"Aether #{item.AetherCurrentRowId}");
        }

        if (item.TerritoryTypeId is not null && item.MapId is not null)
        {
            ImGui.SameLine();
            ImGui.TextDisabled($"Map {item.TerritoryTypeId}/{item.MapId}");
        }
    }

    private void DrawActions(ResolvedUnlockable item)
    {
        var manualComplete = plugin.Configuration.ManualCompletedIds.Contains(item.Entry.Id);
        if (ImGui.Checkbox($"Manual complete##{item.Entry.Id}", ref manualComplete))
        {
            plugin.UnlockData.SetManualComplete(item.Entry.Id, manualComplete);
            InvalidateResolvedCache();
        }

        ImGui.SameLine();
        if (!item.CanOpenMap)
        {
            ImGui.BeginDisabled();
        }

        if (ImGui.Button($"Open Map##{item.Entry.Id}"))
        {
            plugin.UnlockData.OpenMap(item);
        }

        if (!item.CanOpenMap)
        {
            ImGui.EndDisabled();
        }

        if (!item.CanOpenMap && item.Entry.Locations.Count > 0)
        {
            ImGui.SameLine();
            ImGui.TextDisabled("Map ID unresolved");
        }
    }

    private bool MatchesSearch(ResolvedUnlockable item)
    {
        if (!HasSearchText())
        {
            return true;
        }

        var haystack = string.Join(
            " ",
            item.Entry.Title,
            item.Entry.UnlockName,
            item.Entry.Category,
            item.Entry.Subtype,
            item.Entry.Section,
            item.Entry.Zone,
            item.Entry.Expansion,
            string.Join(" ", item.Entry.QuestNames),
            string.Join(" ", ExtractRequirements(item.Entry.Instructions)),
            string.Join(" ", item.Entry.Locations.Select(location => location.Text)),
            item.Entry.Instructions);

        return haystack.Contains(search, StringComparison.OrdinalIgnoreCase);
    }

    private bool HasSearchText()
    {
        return !string.IsNullOrWhiteSpace(search);
    }

    private bool MatchesCategoryFilter(ResolvedUnlockable item)
    {
        return string.IsNullOrWhiteSpace(plugin.Configuration.CategoryFilter)
            || string.Equals(item.Entry.Category, plugin.Configuration.CategoryFilter, StringComparison.OrdinalIgnoreCase);
    }

    private bool MatchesMapFilter(ResolvedUnlockable item)
    {
        if (string.IsNullOrWhiteSpace(plugin.Configuration.MapFilter))
        {
            return true;
        }

        var zone = string.IsNullOrWhiteSpace(item.Entry.Zone)
            ? item.Entry.Locations.FirstOrDefault()?.Place ?? string.Empty
            : item.Entry.Zone;

        return string.Equals(zone, plugin.Configuration.MapFilter, StringComparison.OrdinalIgnoreCase);
    }

    private bool MatchesStatusFilter(ResolvedUnlockable item)
    {
        return plugin.Configuration.StatusFilter switch
        {
            "Open" => !item.IsComplete && item.IsAutoTracked,
            "Complete" => item.IsComplete,
            "Manual" => plugin.Configuration.ManualCompletedIds.Contains(item.Entry.Id),
            "Needs Manual Check" => !item.IsAutoTracked,
            _ => true,
        };
    }

    private bool IsStatusFilter(string status)
    {
        return string.Equals(plugin.Configuration.StatusFilter, status, StringComparison.OrdinalIgnoreCase);
    }

    private static string StatusPrefix(ResolvedUnlockable item)
    {
        if (item.IsComplete)
        {
            return "Done";
        }

        return item.IsAutoTracked ? "Open" : "Needs Manual Check";
    }

    private static void DrawStatusBadge(ResolvedUnlockable item)
    {
        var label = StatusPrefix(item);
        var color = label switch
        {
            "Done" => new Vector4(0.35f, 0.95f, 0.55f, 1f),
            "Open" => new Vector4(0.35f, 0.68f, 1f, 1f),
            _ => new Vector4(1f, 0.76f, 0.32f, 1f),
        };

        ImGui.TextColored(color, $"[{label}]");
    }

    private static List<string> ExtractRequirements(string instructions)
    {
        var results = new List<string>();
        if (string.IsNullOrWhiteSpace(instructions))
        {
            return results;
        }

        foreach (var marker in new[] { "Requires ", "after " })
        {
            var start = instructions.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
            if (start < 0)
            {
                continue;
            }

            start += marker.Length;
            var end = instructions.IndexOf('.', start);
            if (end < 0)
            {
                end = instructions.Length;
            }

            var value = instructions[start..end].Trim();
            if (value.Length > 0 && value.Length < 80 && !results.Contains(value, StringComparer.OrdinalIgnoreCase))
            {
                results.Add(value);
            }
        }

        return results;
    }

    private IReadOnlyList<ResolvedUnlockable> GetResolvedCache(uint currentTerritory)
    {
        var now = DateTime.UtcNow;
        if (resolvedCache.Count > 0 && now < nextRefreshUtc)
        {
            return resolvedCache;
        }

        resolvedCache = plugin.UnlockData.ResolveAll(false, currentTerritory).ToList();
        nextRefreshUtc = now + RefreshInterval;
        return resolvedCache;
    }

    private void InvalidateResolvedCache()
    {
        nextRefreshUtc = DateTime.MinValue;
    }

    private static void DrawQuestList(string label, IReadOnlyList<string> values)
    {
        if (values.Count <= 1)
        {
            ImGui.TextWrapped($"{label}: {values.FirstOrDefault()}");
            return;
        }

        ImGui.TextWrapped($"{label}: One of these:");
        foreach (var value in values)
        {
            ImGui.BulletText(value);
        }
    }

    private static List<string> ExpandAlternativeRequirements(List<string> requirements, IReadOnlyList<UnlockableEntry> items)
    {
        var results = new List<string>();
        foreach (var requirement in requirements)
        {
            var alternatives = FindAlternativeRequirementGroup(requirement, items);
            foreach (var alternative in alternatives.Count > 0 ? alternatives : [requirement])
            {
                if (!results.Contains(alternative, StringComparer.OrdinalIgnoreCase))
                {
                    results.Add(alternative);
                }
            }
        }

        return results;
    }

    private static List<string> FindAlternativeRequirementGroup(string requirement, IReadOnlyList<UnlockableEntry> items)
    {
        foreach (var item in items)
        {
            if (item.QuestNames.Count <= 1)
            {
                continue;
            }

            if (item.QuestNames.Any(name => string.Equals(name, requirement, StringComparison.OrdinalIgnoreCase)))
            {
                return item.QuestNames;
            }
        }

        return requirement switch
        {
            "Leves of Bentbranch" or "Leves of Horizon" or "Leves of Swiftperch" =>
                ["Leves of Bentbranch", "Leves of Horizon", "Leves of Swiftperch"],
            _ => [],
        };
    }
}
