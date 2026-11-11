using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using NeoBanking.Api.Company;
using NeoBanking.Api.Controllers;
using NeoBanking.Application.Common;
using NeoBanking.Application.UseCases.Hoppa;
using Xunit;

namespace NeoBanking.Api.Tests;

public sealed class MobileBusinessWorkflowTests
{
    [Fact]
    public async Task WorkflowUsesTheSignedInUserAndStagesKybBeforeQueuingAssessment()
    {
        using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        var proxy = new RecordingProxy("business");
        var controller = new MobileBusinessOnboardingController(proxy, db, Options.Create(new CompanyOptions()))
        {
            ControllerContext = MobileIdentityTestSupport.ControllerContext(user.Id)
        };
        controller.Request.QueryString = new QueryString("?userId=999&companyId=999");

        var paymentId = Guid.NewGuid();
        var draft = JsonSerializer.SerializeToElement(new
        {
            RegisteredName = "Fictional Ltd",
            AssociatedPeople = new[] { new { AssociationType = "APPLICANT" } }
        });

        await controller.GetWorkflow(default);
        await controller.SelectTier(new(12), default);
        await controller.Checkout(paymentId, new(true), default);
        await controller.SaveDraft(draft, default);
        var formationDocument = new BusinessOnboardingDocumentFormDto { Purpose = "PROOF_OF_FORMATION" };
        await controller.SubmitDocument(formationDocument, default);
        var document = new BusinessOnboardingDocumentFormDto { Purpose = "PROOF_OF_IDENTITY" };
        await controller.SubmitAssociatedPersonDocument("42", document, default);
        controller.Request.Path = "/api/v1/mobile/business-onboarding/compliance";
        await controller.SaveCompliance(JsonSerializer.SerializeToElement(new { }), default);
        var assessment = Assert.IsType<AcceptedResult>((await controller.SubmitApplication(default)).Result);
        Assert.Equal("ASSESSMENT_PENDING", Assert.IsType<JsonElement>(assessment.Value).GetProperty("status").GetString());
        await controller.GetWorkflow(default);
        await controller.GetApplication(default);

        var requests = proxy.Requests;
        Assert.Equal(new[]
        {
            (HttpMethod.Get, "/api/v2/business-onboarding"),
            (HttpMethod.Post, "/api/v2/business-onboarding/tier"),
            (HttpMethod.Post, $"/api/v2/business-onboarding/payments/{paymentId:D}/checkout"),
            (HttpMethod.Post, "/api/v2/dashboard/kyb/submit"),
            (HttpMethod.Post, "/api/v2/dashboard/kyb/documents"),
            (HttpMethod.Post, "/api/v2/dashboard/kyb/documents"),
            (HttpMethod.Post, "/api/v2/business/onboarding/compliance"),
            (HttpMethod.Post, "/api/v2/business-onboarding/assess"),
            (HttpMethod.Get, "/api/v2/business-onboarding"),
            (HttpMethod.Get, "/api/v2/business/onboarding/application")
        }, requests.Select(request => (request.Method, request.Path)));
        Assert.All(requests, request =>
        {
            Assert.Single(request.Query);
            Assert.Equal("10466", request.Query["userId"]);
            Assert.True(request.SuppressLogging);
        });
        Assert.Equal(12, requests[1].Body.GetProperty("TierId").GetInt32());
        Assert.True(requests[2].Body.GetProperty("TermsAccepted").GetBoolean());
        Assert.Single(requests[3].Body.GetProperty("AssociatedPeople").EnumerateArray());
        Assert.Equal("PROOF_OF_FORMATION", requests[4].Body.GetProperty("Purpose").GetString());
        Assert.False(requests[4].Body.TryGetProperty("AssociatedPersonId", out _));
        Assert.Equal("42", requests[5].Body.GetProperty("AssociatedPersonId").GetString());
    }

    [Fact]
    public async Task PersonalAccountsCannotUseTheWorkflow()
    {
        using var db = MobileIdentityTestSupport.CreateDatabase();
        var user = await MobileIdentityTestSupport.SeedUserAsync(db);
        var proxy = new RecordingProxy("personal");
        var controller = new MobileBusinessOnboardingController(proxy, db, Options.Create(new CompanyOptions()))
        {
            ControllerContext = MobileIdentityTestSupport.ControllerContext(user.Id)
        };

        var response = Assert.IsType<ObjectResult>((await controller.GetWorkflow(default)).Result);

        Assert.Equal(StatusCodes.Status403Forbidden, response.StatusCode);
        Assert.Empty(proxy.Requests);
    }

    private sealed class RecordingProxy(string accountType) : IProxyHoppaRequestUseCase
    {
        public List<(HttpMethod Method, string Path, IReadOnlyDictionary<string, string?> Query, JsonElement Body, bool SuppressLogging)> Requests { get; } = [];

        public async Task<ApplicationResult<JsonElement?>> ExecuteAsync<TRequest>(
            ProxyHoppaRequestCommand<TRequest> command,
            CancellationToken cancellationToken)
        {
            if (command.UpstreamPath.StartsWith("/api/v2/users/", StringComparison.Ordinal))
            {
                return ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new { accountType }));
            }

            JsonElement body;
            if (command.Request is MultipartFormDataContent form)
            {
                var parts = new Dictionary<string, string>();
                foreach (var part in form)
                {
                    parts[part.Headers.ContentDisposition!.Name!.Trim('"')] = await part.ReadAsStringAsync(cancellationToken);
                }
                body = JsonSerializer.SerializeToElement(parts);
            }
            else
            {
                body = JsonSerializer.SerializeToElement(command.Request);
            }

            Requests.Add((command.Method, command.UpstreamPath, command.Query, body, command.SuppressPayloadLogging));
            var status = command.UpstreamPath.EndsWith("/assess", StringComparison.Ordinal) ? "ASSESSMENT_PENDING" : "DRAFT";
            return ApplicationResult<JsonElement?>.Success(JsonSerializer.SerializeToElement(new { status }));
        }
    }
}
