using Microsoft.AspNetCore.Mvc.ApiExplorer;

namespace RedisToggler.Api;

internal static class ApiSwashbuckleConfig
{
    private const string ForwardedHost = "X-Forwarded-Host";

    public static IApplicationBuilder ConfigureSwagger(this IApplicationBuilder app, string pathBase) =>
        app
            .UseSwagger(c =>
            {
                c.PreSerializeFilters.Add((swaggerDoc, httpReq) =>
                {
                    var host = GetForwardedHost(httpReq);

                    swaggerDoc.Servers =
                    [
                        new()
                        {
                            Url = $"http://{host}{pathBase}",
                        },
                        new()
                        {
                            Url = $"https://{host}{pathBase}",
                        },
                    ];
                });
            })
            .UseSwaggerUI(options =>
            {
                var provider = app.ApplicationServices.GetRequiredService<IApiVersionDescriptionProvider>();
                // Geração de um endpoint do Swagger para cada versão descoberta
                foreach (var description in provider.ApiVersionDescriptions)
                {
                    options.SwaggerEndpoint($"{pathBase}/swagger/{description.GroupName}/swagger.json",
                        description.GroupName.ToUpperInvariant());
                }
            });

    private static string GetForwardedHost(HttpRequest httpRequest)
    {
        var host = httpRequest.Headers[ForwardedHost];
        if (string.IsNullOrWhiteSpace(host))
        {
            host = httpRequest.Host.Value;
        }

        return host!;
    }
}
