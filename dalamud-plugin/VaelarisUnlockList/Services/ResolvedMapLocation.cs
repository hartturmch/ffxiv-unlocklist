using VaelarisUnlockList.Models;

namespace VaelarisUnlockList.Services;

public sealed record ResolvedMapLocation(uint TerritoryTypeId, uint MapId, UnlockLocation Location);
