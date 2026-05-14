using System.Text.Json.Serialization;

namespace VaelarisUnlockList.Models;

public sealed class GameDataIds
{
    public GameDataIds Clone()
    {
        return new GameDataIds
        {
            QuestId = QuestId,
            TerritoryTypeId = TerritoryTypeId,
            MapId = MapId,
            AetherCurrentId = AetherCurrentId,
            UnlockLinkId = UnlockLinkId,
        };
    }

    [JsonPropertyName("questId")]
    public uint? QuestId { get; set; }

    [JsonPropertyName("territoryTypeId")]
    public uint? TerritoryTypeId { get; set; }

    [JsonPropertyName("mapId")]
    public uint? MapId { get; set; }

    [JsonPropertyName("aetherCurrentId")]
    public uint? AetherCurrentId { get; set; }

    [JsonPropertyName("unlockLinkId")]
    public uint? UnlockLinkId { get; set; }
}
