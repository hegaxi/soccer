using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Soccer.Api.Datos;

namespace Soccer.Api.Controllers;

public sealed record Peticion(string? Accion, JsonElement? Params);

/// <summary>
/// El único controlador. No contiene reglas de negocio ni conoce procedimientos:
/// "exec" despacha cualquier acción del catálogo; los endpoints de archivo solo mueven bytes
/// después de que la base autoriza y dice dónde.
/// </summary>
[ApiController]
[Route("api")]
public sealed class ApiController(EjecutorSp ejecutor, Almacen almacen, ILogger<ApiController> log) : ControllerBase
{
    private const string Cookie = "soccer_sesion";

    private Contexto Ctx => new(Request.Cookies[Cookie], HttpContext.Connection.RemoteIpAddress?.ToString());

    [HttpPost("exec")]
    public Task<IActionResult> Exec([FromBody] Peticion p, CancellationToken ct) => Manejar(async () =>
    {
        if (string.IsNullOrWhiteSpace(p.Accion)) throw new ErrorNegocio(400, "Falta la acción");
        var r = await ejecutor.EjecutarAsync(p.Accion, p.Params, Ctx, ct);

        if (r.EfectoSesion == "INICIA" && r.TokenEmitido is not null)
            Response.Cookies.Append(Cookie, r.TokenEmitido, new CookieOptions
            {
                HttpOnly = true, SameSite = SameSiteMode.Strict, Secure = Request.IsHttps, Path = "/",
                Expires = DateTimeOffset.UtcNow.AddDays(7)
            });
        else if (r.EfectoSesion == "CIERRA")
            Response.Cookies.Delete(Cookie, new CookieOptions { Path = "/" });

        return Ok(new { ok = true, resultados = r.Conjuntos, salida = r.Salida });
    });

    /// <summary>Sube el archivo de un medio ya registrado, por partes consecutivas (reanudable).</summary>
    [HttpPut("archivo/{medioId:int}")]
    public Task<IActionResult> Subir(int medioId, [FromQuery] long offset, CancellationToken ct) => Manejar(async () =>
    {
        var auth = await ejecutor.EjecutarInternaAsync("archivo.autorizarSubida", new { medioId }, Ctx, ct);
        var fila = auth.PrimeraFila() ?? throw new ErrorNegocio(404, "Medio no encontrado");
        var total = Convert.ToInt64(fila["tamanoBytes"]);
        var ruta = almacen.PrepararEscritura((string)fila["rutaArchivo"]!);

        if (Request.ContentLength is not > 0) throw new ErrorNegocio(400, "La parte está vacía");
        if (Request.ContentLength > almacen.MaxBytesPorParte) throw new ErrorNegocio(413, "La parte es demasiado grande");

        long recibido;
        await using (var fs = new FileStream(ruta, FileMode.OpenOrCreate, FileAccess.Write, FileShare.None, 1 << 16, useAsync: true))
        {
            // el desfase debe coincidir con lo ya escrito; si no, el cliente retoma desde "recibido"
            if (offset != fs.Length)
                return Conflict(new { ok = false, error = "Desfase incorrecto", recibido = fs.Length });
            if (offset + Request.ContentLength > total) throw new ErrorNegocio(400, "El archivo supera el tamaño declarado");
            fs.Seek(0, SeekOrigin.End);
            await Request.Body.CopyToAsync(fs, ct);
            recibido = fs.Length;
        }
        if (recibido > total)
        {
            System.IO.File.Delete(ruta);
            throw new ErrorNegocio(400, "El archivo supera el tamaño declarado");
        }
        if (recibido == total)
            await ejecutor.EjecutarInternaAsync("archivo.subidaCompleta", new { medioId }, Ctx, ct);

        return Ok(new { ok = true, recibido, completo = recibido == total });
    });

    /// <summary>Entrega un video o foto (con Range para poder adelantar). v = web | mini | orig.</summary>
    [HttpGet("archivo/{medioId:int}")]
    public Task<IActionResult> Leer(int medioId, [FromQuery] string v = "web", [FromQuery] string? k = null, CancellationToken ct = default) =>
        Manejar(async () =>
        {
            var r = await ejecutor.EjecutarInternaAsync("archivo.autorizarLectura", new { medioId, variante = v, tokenPublico = k }, Ctx, ct);
            return Entregar(r, v == "mini" ? 86400 : 3600);
        });

    /// <summary>Entrega el video renderizado de un reel; con ?k= lo puede ver un visor sin sesión.</summary>
    [HttpGet("archivo/reel/{reelId:int}")]
    public Task<IActionResult> LeerReel(int reelId, [FromQuery] string? k = null, CancellationToken ct = default) => Manejar(async () =>
    {
        var r = await ejecutor.EjecutarInternaAsync("archivo.autorizarReel", new { reelId, tokenPublico = k }, Ctx, ct);
        return Entregar(r, 0);
    });

    private IActionResult Entregar(Resultado r, int cacheSeg)
    {
        var fila = r.PrimeraFila() ?? throw new ErrorNegocio(404, "Archivo no disponible");
        var ruta = almacen.RutaFisica((string)fila["ruta"]!);
        if (!System.IO.File.Exists(ruta)) throw new ErrorNegocio(404, "Archivo no disponible");
        Response.Headers.CacheControl = cacheSeg > 0 ? $"private, max-age={cacheSeg}" : "private, no-cache";
        Response.Headers.XContentTypeOptions = "nosniff";
        return PhysicalFile(ruta, (string)fila["mime"]!, enableRangeProcessing: true);
    }

    private async Task<IActionResult> Manejar(Func<Task<IActionResult>> accion)
    {
        try { return await accion(); }
        catch (ErrorNegocio e) { return StatusCode(e.Estado, new { ok = false, error = e.Message }); }
        catch (OperationCanceledException) { return StatusCode(499); }
        catch (Exception e)
        {
            log.LogError(e, "Error no controlado en {Ruta}", Request.Path);
            return StatusCode(500, new { ok = false, error = "Ocurrió un error inesperado" });
        }
    }
}
