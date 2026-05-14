using System.Text.Json.Serialization;

namespace VaelarisUnlockList.Models;

public sealed class UnlockDataset
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; }

    [JsonPropertyName("generatedAt")]
    public string GeneratedAt { get; set; } = string.Empty;

    [JsonPropertyName("sourceFiles")]
    public List<string> SourceFiles { get; set; } = [];

    [JsonPropertyName("items")]
    public List<UnlockableEntry> Items { get; set; } = [];
}
