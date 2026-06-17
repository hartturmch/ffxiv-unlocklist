using System.Numerics;

namespace VaelarisUnlockList.Services;

public sealed record BellMapLocation(
    string Name,
    string ZoneName,
    uint TerritoryTypeId,
    uint MapId,
    float X,
    float Y,
    Vector3 WorldPosition);
