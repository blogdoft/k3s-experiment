using Microsoft.AspNetCore.Mvc.ApiExplorer;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi.Models;
using Swashbuckle.AspNetCore.SwaggerGen;

namespace RedisToggler.Api.Swagger
{
    internal class ConfigureSwaggerOptions : IConfigureOptions<SwaggerGenOptions>
    {
        private readonly IApiVersionDescriptionProvider _provider;

        public ConfigureSwaggerOptions(IApiVersionDescriptionProvider provider)
        {
            _provider = provider;
        }

        public void Configure(SwaggerGenOptions options)
        {
            options.LoadDocumentationFiles();
            // add a swagger document for each discovered API version
            foreach (var description in _provider.ApiVersionDescriptions)
            {
                var info = new OpenApiInfo()
                {
                    Title = $"RedisToggler API {description.GroupName}",
                    Version = description.ApiVersion.ToString()
                };

                options.SwaggerDoc(description.GroupName, info);
            }
        }
    }
}
