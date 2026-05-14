using System.Text.Json.Serialization;

namespace VaelarisUnlockList.Models;

public sealed class UnlockableEntry
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("source")]
    public string Source { get; set; } = string.Empty;

    [JsonPropertyName("section")]
    public string Section { get; set; } = string.Empty;

    [JsonPropertyName("category")]
    public string Category { get; set; } = string.Empty;

    [JsonPropertyName("subtype")]
    public string Subtype { get; set; } = string.Empty;

    [JsonPropertyName("title")]
    public string Title { get; set; } = string.Empty;

    [JsonPropertyName("unlockName")]
    public string UnlockName { get; set; } = string.Empty;

    [JsonPropertyName("questNames")]
    public List<string> QuestNames { get; set; } = [];

    [JsonPropertyName("level")]
    public string Level { get; set; } = string.Empty;

    [JsonPropertyName("itemLevel")]
    public string ItemLevel { get; set; } = string.Empty;

    [JsonPropertyName("expansion")]
    public string Expansion { get; set; } = string.Empty;

    [JsonPropertyName("zone")]
    public string Zone { get; set; } = string.Empty;

    [JsonPropertyName("locations")]
    public List<UnlockLocation> Locations { get; set; } = [];

    [JsonPropertyName("instructions")]
    public string Instructions { get; set; } = string.Empty;

    [JsonPropertyName("wikiUrls")]
    public List<string> WikiUrls { get; set; } = [];

    [JsonPropertyName("completion")]
    public CompletionProbe Completion { get; set; } = new();

    [JsonPropertyName("gameData")]
    public GameDataIds GameData { get; set; } = new();

    [JsonPropertyName("sortOrder")]
    public int SortOrder { get; set; }
}
