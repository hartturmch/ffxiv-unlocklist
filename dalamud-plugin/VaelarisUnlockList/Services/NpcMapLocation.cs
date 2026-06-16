namespace VaelarisUnlockList.Services;

public sealed record NpcMapLocation(
    string Name,
    string ZoneName,
    string MapName,
    uint TerritoryTypeId,
    uint MapId,
    float X,
    float Y,
    bool IsImportant);
