using System.Text.Json;
using NeoBanking.Domain.Entities;

namespace NeoBanking.Api.Onboarding;

/// <summary>
/// Composes the mobile onboarding status from the local application row and
/// the live Hoppa banking status. Shared by the onboarding endpoint and the
/// profile endpoint, which embeds the same block so Home needs one request.
/// </summary>
public static class MobileOnboardingStatus
{
    public static object Compose(
        Guid userId,
        string accountType,
        OnboardingApplication? application,
        string? liveBankingStatus)
    {
        var isLiveBankingComplete = IsCompletedStatus(liveBankingStatus);

        return new
        {
            userId,
            accountType,
            status = isLiveBankingComplete
                ? "completed"
                : liveBankingStatus ?? application?.Status ?? "not_started",
            currentStep = isLiveBankingComplete ? "complete" : application?.CurrentStep ?? "start",
            kind = accountType == "business" ? "business" : "individual",
            requiredActions = RequiredActions(
                application,
                accountType,
                liveBankingStatus,
                isLiveBankingComplete)
        };
    }

    public static string? NormalizeBankingStatus(JsonElement payload)
    {
        if (HasPendingEqualsMoneyAction(payload))
        {
            return GetNestedString(payload, "EqualsMoney", "RequiredAction") ??
                GetNestedString(payload, "equalsMoney", "requiredAction") ??
                "action_required";
        }

        if (HasEqualsMoneyAccount(payload) ||
            IsEqualsMoneyApproved(payload) == true)
        {
            return "completed";
        }

        var status = GetNestedString(payload, "EqualsMoney", "ApplicationStatus") ??
            GetNestedString(payload, "equalsMoney", "applicationStatus") ??
            GetNestedString(payload, "EqualsMoney", "Status") ??
            GetNestedString(payload, "equalsMoney", "status");

        return string.IsNullOrWhiteSpace(status) ? null : status;
    }

    private static string[] RequiredActions(
        OnboardingApplication? application,
        string accountType,
        string? liveBankingStatus,
        bool isLiveBankingComplete)
    {
        if (isLiveBankingComplete)
        {
            return Array.Empty<string>();
        }

        if (!string.IsNullOrWhiteSpace(liveBankingStatus) &&
            !IsPassiveReviewStatus(liveBankingStatus))
        {
            return [liveBankingStatus];
        }

        if (application is null)
        {
            return ["start_onboarding"];
        }

        var actions = application.Status switch
        {
            "completed" => Array.Empty<string>(),
            "submitted" => new[] { "wait_for_review" },
            _ => new[] { application.CurrentStep }
        };

        return accountType == "business"
            ? actions
            : actions
                .Where(action => !ContainsBusinessAction(action))
                .ToArray();
    }

    private static bool IsPassiveReviewStatus(string status)
    {
        var normalized = status.ToLowerInvariant().Replace("_", "-").Trim();
        return normalized is "submitted" or "pending" or "review" or "in-review" or "waiting" or "wait-for-review";
    }

    private static bool ContainsBusinessAction(string action)
    {
        return action.Contains("business", StringComparison.OrdinalIgnoreCase) ||
               action.Contains("kyb", StringComparison.OrdinalIgnoreCase);
    }

    private static bool HasEqualsMoneyAccount(JsonElement payload)
    {
        return !string.IsNullOrWhiteSpace(
            GetNestedString(payload, "EqualsMoney", "AccountId") ??
            GetNestedString(payload, "equalsMoney", "accountId"));
    }

    private static bool? IsEqualsMoneyApproved(JsonElement payload)
    {
        return GetNestedBoolean(payload, "EqualsMoney", "Approved") ??
            GetNestedBoolean(payload, "equalsMoney", "approved");
    }

    private static bool HasPendingEqualsMoneyAction(JsonElement payload)
    {
        if (!string.IsNullOrWhiteSpace(GetNestedString(payload, "EqualsMoney", "RequiredAction")) ||
            !string.IsNullOrWhiteSpace(GetNestedString(payload, "equalsMoney", "requiredAction")) ||
            !string.IsNullOrWhiteSpace(GetNestedString(payload, "EqualsMoney", "ActionUrl")) ||
            !string.IsNullOrWhiteSpace(GetNestedString(payload, "equalsMoney", "actionUrl")))
        {
            return true;
        }

        return HasNestedItems(payload, "EqualsMoney", "additionalDocumentsRequested") ||
            HasNestedItems(payload, "equalsMoney", "additionalDocumentsRequested");
    }

    private static bool IsCompletedStatus(string? status)
    {
        return string.Equals(status, "completed", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(status, "complete", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(status, "approved", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(status, "active", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(status, "ready", StringComparison.OrdinalIgnoreCase);
    }

    internal static bool? GetBoolean(JsonElement payload, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (payload.ValueKind == JsonValueKind.Object &&
                payload.TryGetProperty(propertyName, out var property))
            {
                if (property.ValueKind is JsonValueKind.True or JsonValueKind.False)
                {
                    return property.GetBoolean();
                }

                if (property.ValueKind == JsonValueKind.String &&
                    bool.TryParse(property.GetString(), out var value))
                {
                    return value;
                }
            }
        }

        return null;
    }

    internal static string? GetNestedString(JsonElement payload, string objectName, string propertyName)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty(objectName, out var nested))
        {
            return null;
        }

        return GetString(nested, propertyName);
    }

    internal static bool? GetNestedBoolean(JsonElement payload, string objectName, string propertyName)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty(objectName, out var nested))
        {
            return null;
        }

        return GetBoolean(nested, propertyName);
    }

    private static bool HasNestedItems(JsonElement payload, string objectName, string propertyName)
    {
        return payload.ValueKind == JsonValueKind.Object &&
            payload.TryGetProperty(objectName, out var nested) &&
            nested.ValueKind == JsonValueKind.Object &&
            nested.TryGetProperty(propertyName, out var items) &&
            items.ValueKind == JsonValueKind.Array &&
            items.GetArrayLength() > 0;
    }

    internal static string? GetString(JsonElement payload, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (payload.ValueKind == JsonValueKind.Object &&
                payload.TryGetProperty(propertyName, out var property) &&
                property.ValueKind == JsonValueKind.String)
            {
                return property.GetString();
            }
        }

        return null;
    }
}
