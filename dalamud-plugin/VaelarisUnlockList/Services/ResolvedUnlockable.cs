using VaelarisUnlockList.Models;

namespace VaelarisUnlockList.Services;

public sealed class ResolvedUnlockable
{
    public required UnlockableEntry Entry { get; init; }

    public uint? QuestRowId { get; init; }

    public IReadOnlyList<uint> QuestRowIds { get; init; } = [];

    public uint? AetherCurrentRowId { get; init; }

    public uint? TerritoryTypeId { get; init; }

    public uint? MapId { get; init; }

    public UnlockLocation? MapLocation { get; init; }

    public bool IsComplete { get; init; }

    public bool IsAutoTracked { get; init; }

    public bool IsAvailable { get; init; } = true;

    public IReadOnlyList<string> RequiredQuestNames { get; init; } = [];

    public IReadOnlyList<string> AvailabilityRequirements { get; init; } = [];

    public IReadOnlyList<string> MissingRequirementNames { get; init; } = [];

    public string StatusLabel => IsComplete ? "Complete" : IsAutoTracked ? "Open" : "Manual";

    public bool CanOpenMap => TerritoryTypeId is not null && MapId is not null && MapLocation?.X is not null && MapLocation.Y is not null;
}
