namespace VaelarisUnlockList.Services;

public sealed class ValidationIssue
{
    public string Severity { get; init; } = "warning";

    public string Type { get; init; } = string.Empty;

    public string Id { get; init; } = string.Empty;

    public string Title { get; init; } = string.Empty;

    public string Expected { get; init; } = string.Empty;

    public string Actual { get; init; } = string.Empty;

    public string Suggestion { get; init; } = string.Empty;
}
