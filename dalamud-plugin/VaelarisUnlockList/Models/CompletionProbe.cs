using System.Text.Json.Serialization;

namespace VaelarisUnlockList.Models;

public sealed class CompletionProbe
{
    [JsonPropertyName("kind")]
    public string Kind { get; set; } = "Manual";

    [JsonPropertyName("questNames")]
    public List<string> QuestNames { get; set; } = [];
}
