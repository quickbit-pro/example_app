using NeoBanking.Api.Controllers;
using NeoBanking.Application.DTOs.Branding;
using Xunit;

namespace NeoBanking.Tests;

public sealed class MobileDesignValidationTests
{
    [Fact]
    public void ValidFlutterDesignIsAccepted()
    {
        var errors = AdminMobileDesignController.Validate(new UpdateMobileDesignRequestDto
        {
            AppName = "Acme Pay",
            PrimaryColor = "#2563EB",
            AccentColor = "B6FF6E",
            LoginBackgroundColor = "#123ABC",
            ThemeMode = "system",
            FontFamily = "Acme Sans",
            LogoAsset = "assets/brand/acme.png",
            SupportEmail = "help@acme.test",
            SupportPhone = "+386 1 555 0100",
            LegalEntity = "Acme Payments Ltd"
        });

        Assert.Empty(errors);
        Assert.Equal("2563EB", AdminMobileDesignController.NormalizeHex("#2563eb", "000000"));
    }

    [Fact]
    public void InvalidBuildValuesAreRejected()
    {
        var errors = AdminMobileDesignController.Validate(new UpdateMobileDesignRequestDto
        {
            AppName = " ",
            PrimaryColor = "blue",
            AccentColor = "#12345",
            LoginBackgroundColor = "violet",
            ThemeMode = "automatic",
            LogoAsset = "../../secret.png",
            SupportEmail = "not-an-email"
        });

        Assert.Contains("appName", errors.Keys, StringComparer.OrdinalIgnoreCase);
        Assert.Contains("primaryColor", errors.Keys, StringComparer.OrdinalIgnoreCase);
        Assert.Contains("accentColor", errors.Keys, StringComparer.OrdinalIgnoreCase);
        Assert.Contains("loginBackgroundColor", errors.Keys, StringComparer.OrdinalIgnoreCase);
        Assert.Contains("themeMode", errors.Keys, StringComparer.OrdinalIgnoreCase);
        Assert.Contains("logoAsset", errors.Keys, StringComparer.OrdinalIgnoreCase);
        Assert.Contains("supportEmail", errors.Keys, StringComparer.OrdinalIgnoreCase);
    }
}
