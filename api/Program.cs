using Soccer.Api.Datos;
using Soccer.Api.Trabajos;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSingleton<EjecutorSp>();
builder.Services.AddSingleton<Almacen>();
builder.Services.AddHostedService<ProcesadorMedios>();

var app = builder.Build();

// Las páginas de reels compartidos y los archivos no deben aparecer en buscadores.
app.Use((ctx, next) =>
{
    if (ctx.Request.Path.StartsWithSegments("/r") || ctx.Request.Path.StartsWithSegments("/api/archivo"))
        ctx.Response.Headers["X-Robots-Tag"] = "noindex, nofollow, noarchive";
    return next();
});

// La app React compilada se sirve desde wwwroot (un solo despliegue).
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapControllers();
app.MapFallbackToFile("index.html");

app.Run();
