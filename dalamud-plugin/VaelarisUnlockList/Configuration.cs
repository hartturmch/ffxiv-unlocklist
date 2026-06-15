using System.Text.Json;
using Dalamud.Configuration;

namespace VaelarisUnlockList;

[Serializable]
public sealed class Configuration : IPluginConfiguration
{
    public int Version { get; set; } = 1;

    public bool ShowCompleted { get; set; }

    public bool CurrentZoneOnly { get; set; }

    public string CategoryFilter { get; set; } = string.Empty;

    public string MapFilter { get; set; } = string.Empty;

    public string StatusFilter { get; set; } = string.Empty;

    public bool ShowDevTools { get; set; }

    public HashSet<string> ManualCompletedIds { get; set; } = [];

    public Dictionary<string, Models.GameDataIds> ResolvedGameDataIds { get; set; } = [];

    public void LoadLocalManualCompletedIds()
    {
        try
        {
            var path = GetManualCompletedPath();
            if (!File.Exists(path))
            {
                return;
            }

            var state = JsonSerializer.Deserialize<ManualCompletedState>(File.ReadAllText(path));
            if (state?.ManualCompletedIds is null)
            {
                return;
            }

            foreach (var id in state.ManualCompletedIds.Where(id => !string.IsNullOrWhiteSpace(id)))
            {
                ManualCompletedIds.Add(id);
            }
        }
        catch (Exception ex)
        {
            Plugin.Log.Warning(ex, "Failed to load local manual completion state.");
        }
    }

    public void Save()
    {
        SaveLocalManualCompletedIds();
        Plugin.PluginInterface.SavePluginConfig(this);
    }

    private static string GetManualCompletedPath()
    {
        return Path.Combine(Plugin.PluginInterface.ConfigDirectory.FullName, "manual-completed.json");
    }

    private void SaveLocalManualCompletedIds()
    {
        try
        {
            var path = GetManualCompletedPath();
            Directory.CreateDirectory(Path.GetDirectoryName(path) ?? Plugin.PluginInterface.ConfigDirectory.FullName);
            var state = new ManualCompletedState
            {
                ManualCompletedIds = ManualCompletedIds.OrderBy(id => id, StringComparer.OrdinalIgnoreCase).ToList(),
            };
            File.WriteAllText(path, JsonSerializer.Serialize(state, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex)
        {
            Plugin.Log.Warning(ex, "Failed to save local manual completion state.");
        }
    }

    private sealed class ManualCompletedState
    {
        public int Version { get; set; } = 1;

        public List<string> ManualCompletedIds { get; set; } = [];
    }
}
