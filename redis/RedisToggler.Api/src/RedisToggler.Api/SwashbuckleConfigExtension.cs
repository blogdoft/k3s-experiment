using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using RedisToggler.Api.Swagger;
using Swashbuckle.AspNetCore.SwaggerGen;

namespace RedisToggler.Api;

public static class SwashbuckleConfigExtension
{
    public static IServiceCollection ConfigSwashbuckle(this IServiceCollection services) =>
        services
            .AddEndpointsApiExplorer()
            .AddApiVersioning(options =>
            {
                options.ReportApiVersions = true;
                options.AssumeDefaultVersionWhenUnspecified = true;
                options.DefaultApiVersion = new ApiVersion(1, 0);
            })
            .AddVersionedApiExplorer(options =>
            {
                options.GroupNameFormat = "'version - v'VVV";
                options.SubstituteApiVersionInUrl = true;
            })
            .AddTransient<IConfigureOptions<SwaggerGenOptions>, ConfigureSwaggerOptions>()
            .AddSwaggerGen(options =>
            {
                options.OperationFilter<SwaggerDefaultValues>();
                options.OperationFilter<ApplicationHeaders>();
            });

    public static void LoadDocumentationFiles(this SwaggerGenOptions options)
    {
        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            var xmlDocumentationFile = $"{assembly.GetName().Name}.xml";
            var xmlDocumentationPath = Path.Combine(AppContext.BaseDirectory, xmlDocumentationFile);
            if (File.Exists(xmlDocumentationPath))
            {
                options.IncludeXmlComments(xmlDocumentationPath, includeControllerXmlComments: true);
            }
        }
    }
}
