using System.Text.Json.Serialization;

namespace VaelarisUnlockList.Models;

public sealed class UnlockLocation
{
    [JsonPropertyName("place")]
    public string Place { get; set; } = string.Empty;

    [JsonPropertyName("text")]
    public string Text { get; set; } = string.Empty;

    [JsonPropertyName("x")]
    public float? X { get; set; }

    [JsonPropertyName("y")]
    public float? Y { get; set; }

    [JsonPropertyName("z")]
    public float? Z { get; set; }
}
