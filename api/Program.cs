using Soccer.Api.Datos;
using Soccer.Api.Trabajos;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSingleton<EjecutorSp>();
builder.Services.AddSingleton<Almacen>();
builder.Services.AddHostedService<ProcesadorMedios>();

var app = builder.Build();

// La app React compilada se sirve desde wwwroot (un solo despliegue).
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapControllers();
app.MapFallbackToFile("index.html");

app.Run();
