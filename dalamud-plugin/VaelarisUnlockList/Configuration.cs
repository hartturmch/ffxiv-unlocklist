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

    public void Save()
    {
        Plugin.PluginInterface.SavePluginConfig(this);
    }
}
