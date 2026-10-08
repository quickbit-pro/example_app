namespace NeoBanking.Api.OpenApi;

public static class ScalarEndpointExtensions
{
    public static IEndpointRouteBuilder MapScalarApiReference(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/scalar/v1", () => Results.Content(
            """
            <!doctype html>
            <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1">
              <title>NeoBanking API Reference</title>
            </head>
            <body>
              <script
                id="api-reference"
                data-url="/openapi/v1.json"
                data-theme="purple"
                src="https://cdn.jsdelivr.net/npm/@scalar/api-reference">
              </script>
            </body>
            </html>
            """,
            "text/html"))
            .AllowAnonymous()
            .ExcludeFromDescription();

        endpoints.MapGet("/swagger", () => Results.Redirect("/scalar/v1"))
            .AllowAnonymous()
            .ExcludeFromDescription();

        return endpoints;
    }
}
