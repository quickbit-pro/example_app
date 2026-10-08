#nullable enable

namespace NeoBanking.Domain.Entities;

public sealed class OnboardingApplication : CompanyScopedEntity
{
    public Guid? ApplicantUserId { get; set; }

    public ApplicationUser? ApplicantUser { get; set; }

    public string Kind { get; set; } = "individual";

    public string Status { get; set; } = "draft";

    public int WorkflowVersion { get; set; } = 1;

    public string CurrentStep { get; set; } = "start";

    public DateTimeOffset? SubmittedAt { get; set; }

    public DateTimeOffset? CompletedAt { get; set; }

    public string FormDataJson { get; set; } = "{}";

    public string DecisionJson { get; set; } = "{}";

    public string MetadataJson { get; set; } = "{}";

    public ICollection<KycVerification> KycVerifications { get; set; } = new List<KycVerification>();

    public ICollection<KybVerification> KybVerifications { get; set; } = new List<KybVerification>();
}
