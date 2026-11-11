using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json;
using Soccer.Api.Datos;

namespace Soccer.Api.Trabajos;

/// <summary>
/// Procesa en segundo plano lo que SQL no puede hacer: leer el archivo con ffmpeg.
/// La cola, el estado y lo que se hace con el resultado viven en la base (trabajo.tomar / trabajo.completar).
///   PROCESAR_MEDIO: duración y tamaño, miniatura, versión para navegador y picos de audio.
///   RENDER_REEL:    tarjeta inicial + jugadas recortadas y unidas en un solo mp4.
/// </summary>
public sealed class ProcesadorMedios(EjecutorSp ejecutor, Almacen almacen, IConfiguration config, ILogger<ProcesadorMedios> log)
    : BackgroundService
{
    private readonly string _ffmpeg = config["Procesador:Ffmpeg"] ?? "ffmpeg";
    private readonly string _ffprobe = config["Procesador:Ffprobe"] ?? "ffprobe";
    private readonly string _fuente = config["Procesador:Fuente"] ?? "";
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        if (!config.GetValue("Procesador:Activo", true)) return;
        var espera = TimeSpan.FromSeconds(config.GetValue("Procesador:IntervaloSegundos", 3));
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var r = await ejecutor.EjecutarInternaAsync("trabajo.tomar", null, null, ct);
                var trabajo = r.PrimeraFila();
                if (trabajo is null) { await Task.Delay(espera, ct); continue; }

                var id = (int)trabajo["trabajoId"]!;
                try
                {
                    var resultado = (string)trabajo["tipo"]! == "RENDER_REEL"
                        ? await RenderizarReel(trabajo, r.Conjuntos[1], r.Conjuntos[2], ct)
                        : await ProcesarMedio(trabajo, ct);
                    await ejecutor.EjecutarInternaAsync("trabajo.completar",
                        new { trabajoId = id, exito = true, resultadoJson = JsonSerializer.Serialize(resultado) }, null, ct);
                    log.LogInformation("Trabajo {Id} ({Tipo}) terminado", id, trabajo["tipo"]);
                }
                catch (Exception e) when (e is not OperationCanceledException)
                {
                    log.LogError(e, "Trabajo {Id} falló", id);
                    var msg = e.Message.Length > 480 ? e.Message[..480] : e.Message;
                    await ejecutor.EjecutarInternaAsync("trabajo.completar", new { trabajoId = id, exito = false, error = msg }, null, ct);
                }
            }
            catch (OperationCanceledException) { break; }
            catch (Exception e)
            {
                log.LogError(e, "Error en el procesador de medios");
                await Task.Delay(TimeSpan.FromSeconds(10), ct);
            }
        }
    }

    // ---------------------------------------------------------------- PROCESAR_MEDIO

    private async Task<object> ProcesarMedio(Dictionary<string, object?> t, CancellationToken ct)
    {
        var rel = (string)t["rutaArchivo"]!;
        var origen = almacen.RutaFisica(rel);
        var baseRel = Path.ChangeExtension(rel, null);
        var info = await Sondear(origen, ct);
        if (info.Ancho == 0) throw new InvalidOperationException("El archivo no contiene imagen o video legible");

        var miniRel = baseRel + "_mini.jpg";
        if ((string)t["tipoMedio"]! == "FOTO")
        {
            var webRel = baseRel + "_web.jpg";
            await Ffmpeg(ct, "-i", origen, "-vf", "scale='min(480,iw)':-2", "-frames:v", "1", "-q:v", "4", almacen.RutaFisica(miniRel));
            await Ffmpeg(ct, "-i", origen, "-vf", "scale='min(1920,iw)':-2", "-frames:v", "1", "-q:v", "3", almacen.RutaFisica(webRel));
            return new { duracionSeg = (double?)null, ancho = info.Ancho, alto = info.Alto, rutaWeb = webRel, rutaMiniatura = miniRel };
        }

        if (info.Duracion <= 0) throw new InvalidOperationException("No se pudo leer la duración del video");
        await Ffmpeg(ct, "-ss", (info.Duracion * 0.1).ToString("0.###", Inv), "-i", origen, "-frames:v", "1",
            "-vf", "scale=640:-2", "-q:v", "4", almacen.RutaFisica(miniRel));

        // Versión para navegador: H.264/AAC en mp4 con el índice al inicio (permite saltar sin descargar todo)
        var webVideo = baseRel + "_web.mp4";
        var compatible = info.CodecVideo == "h264" && info.PixFmt == "yuv420p" && info.CodecAudio is null or "aac" && info.Alto <= 1080;
        if (compatible)
            await Ffmpeg(ct, "-i", origen, "-map", "0:v:0", "-map", "0:a:0?", "-c", "copy", "-movflags", "+faststart", almacen.RutaFisica(webVideo));
        else
            await Ffmpeg(ct, "-i", origen, "-map", "0:v:0", "-map", "0:a:0?", "-vf", "scale=-2:'min(720,ih)'", "-c:v", "libx264",
                "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
                almacen.RutaFisica(webVideo));

        var picos = info.CodecAudio is null ? [] : await PicosDeAudio(origen, ct);
        return new
        {
            duracionSeg = Math.Round(info.Duracion, 2), ancho = info.Ancho, alto = info.Alto,
            rutaWeb = webVideo, rutaMiniatura = miniRel, picos
        };
    }

    private sealed record Sonda(double Duracion, int Ancho, int Alto, string? CodecVideo, string? PixFmt, string? CodecAudio);

    private async Task<Sonda> Sondear(string ruta, CancellationToken ct)
    {
        var (salida, _) = await Correr(_ffprobe, ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", ruta], ct);
        using var doc = JsonDocument.Parse(salida);
        double dur = 0; int w = 0, h = 0; string? cv = null, pf = null, ca = null;
        if (doc.RootElement.TryGetProperty("format", out var f) && f.TryGetProperty("duration", out var d))
            double.TryParse(d.GetString(), NumberStyles.Float, Inv, out dur);
        if (doc.RootElement.TryGetProperty("streams", out var ss))
            foreach (var s in ss.EnumerateArray())
            {
                var tipo = s.GetProperty("codec_type").GetString();
                if (tipo == "video" && cv is null)
                {
                    cv = s.GetProperty("codec_name").GetString();
                    w = s.GetProperty("width").GetInt32(); h = s.GetProperty("height").GetInt32();
                    pf = s.TryGetProperty("pix_fmt", out var p) ? p.GetString() : null;
                }
                else if (tipo == "audio" && ca is null) ca = s.GetProperty("codec_name").GetString();
            }
        return new Sonda(dur, w, h, cv, pf, ca);
    }

    /// <summary>
    /// Energía del audio por segundo; un pico es un segundo muy por encima del nivel normal del video
    /// (grito de gol, reacción de la banca). Devuelve segundo e intensidad en desviaciones estándar.
    /// </summary>
    private async Task<List<object>> PicosDeAudio(string ruta, CancellationToken ct)
    {
        const int frec = 8000;
        var psi = Psi(_ffmpeg, ["-v", "error", "-i", ruta, "-vn", "-ac", "1", "-ar", frec.ToString(), "-f", "s16le", "-"]);
        using var p = Process.Start(psi)!;
        var errores = p.StandardError.ReadToEndAsync(ct);
        var energia = new List<double>();
        var buf = new byte[frec * 2]; // un segundo
        var s = p.StandardOutput.BaseStream;
        while (true)
        {
            var leidos = 0;
            while (leidos < buf.Length)
            {
                var n = await s.ReadAsync(buf.AsMemory(leidos, buf.Length - leidos), ct);
                if (n == 0) break;
                leidos += n;
            }
            if (leidos < 2) break;
            double suma = 0; var muestras = leidos / 2;
            for (var i = 0; i < muestras; i++) { double v = BitConverter.ToInt16(buf, i * 2); suma += v * v; }
            energia.Add(10 * Math.Log10(suma / muestras + 1)); // dB: la percepción del volumen es logarítmica
            if (leidos < buf.Length) break;
        }
        await p.WaitForExitAsync(ct);
        await errores;
        if (energia.Count < 20) return [];

        var media = energia.Average();
        var desv = Math.Sqrt(energia.Sum(e => (e - media) * (e - media)) / energia.Count);
        if (desv < 0.5) return [];

        var picos = new List<(int s, double z)>();
        for (var i = 1; i < energia.Count - 1; i++)
        {
            var z = (energia[i] - media) / desv;
            if (z >= 2.0 && energia[i] >= energia[i - 1] && energia[i] >= energia[i + 1]) picos.Add((i, z));
        }
        // separados al menos 15 s, quedándose con el más fuerte de cada zona; máximo 40 por video
        var elegidos = new List<(int s, double z)>();
        foreach (var c in picos.OrderByDescending(x => x.z))
            if (elegidos.All(e => Math.Abs(e.s - c.s) >= 15)) elegidos.Add(c);
        return elegidos.Take(40).OrderBy(e => e.s).Select(e => (object)new { s = e.s, i = Math.Round(e.z, 2) }).ToList();
    }

    // ---------------------------------------------------------------- RENDER_REEL

    private async Task<object> RenderizarReel(Dictionary<string, object?> t, List<Dictionary<string, object?>> clips,
        List<Dictionary<string, object?>> tarjeta, CancellationToken ct)
    {
        if (clips.Count == 0) throw new InvalidOperationException("El reel no tiene jugadas");
        var salidaRel = (string)t["rutaSalida"]!;
        var salida = almacen.PrepararEscritura(salidaRel);
        var tmp = Directory.CreateTempSubdirectory("reel_").FullName;
        try
        {
            const string norma = "-c:v libx264 -preset veryfast -crf 21 -pix_fmt yuv420p -r 30 -an -video_track_timescale 15360";
            var partes = new List<string>();

            var tarjetaSeg = Convert.ToDouble(t["tarjetaSeg"] ?? 4.0);
            var congelado = Convert.ToDouble(t["congeladoSeg"] ?? 1.0);
            string N(double v) => v.ToString("0.###", Inv);

            // 1 · tarjeta inicial con los datos del jugador
            var intro = Path.Combine(tmp, "000.mp4");
            var filtros = new List<string>();
            var y = 250 - tarjeta.Count * 18;
            for (var i = 0; i < tarjeta.Count; i++)
            {
                var txt = Path.Combine(tmp, $"t{i}.txt");
                await File.WriteAllTextAsync(txt, (string)tarjeta[i]["texto"]!, new UTF8Encoding(false), ct);
                var tam = Convert.ToInt32(tarjeta[i]["tamano"]);
                filtros.Add($"drawtext=fontfile='{Esc(_fuente)}':textfile='{Esc(txt)}':fontsize={tam}:" +
                            $"fontcolor={(i == 0 ? "white" : "0xcbd5e1")}:x=(w-text_w)/2:y={y}");
                y += tam + (i == 0 ? 34 : 20);
            }
            var argsIntro = new List<string> { "-f", "lavfi", "-i", $"color=c=0x0b1220:s=1280x720:d={N(tarjetaSeg)}:r=30" };
            if (filtros.Count > 0) { argsIntro.Add("-vf"); argsIntro.Add(string.Join(",", filtros)); }
            argsIntro.AddRange(norma.Split(' ')); argsIntro.Add(intro);
            await Ffmpeg(ct, [.. argsIntro]);
            partes.Add(intro);

            // 2 · cada jugada, a 1280x720. Si tiene marca, el cuadro se congela en el momento indicado
            //     (cuando el jugador entra a la jugada) con un recuadro del tamaño elegido.
            var n = 1;
            foreach (var c in clips)
            {
                var origen = almacen.RutaFisica((string)c["ruta"]!);
                var ini = Convert.ToDouble(c["segundoInicio"]); var fin = Convert.ToDouble(c["segundoFin"]);
                var conMarca = c["marcaX"] is not null && c["marcaY"] is not null;
                var marcaSeg = conMarca && c["marcaSegundo"] is not null ? Math.Clamp(Convert.ToDouble(c["marcaSegundo"]), ini, fin - 0.5) : ini;
                string? etiqueta = null;
                if (c["etiqueta"] is string et && et.Length > 0 && _fuente.Length > 0)
                {
                    etiqueta = Path.Combine(tmp, $"e{n}.txt");
                    await File.WriteAllTextAsync(etiqueta, et, new UTF8Encoding(false), ct);
                }

                // tramos: [inicio, marca) normal y [marca, fin) con el cuadro congelado al principio
                var tramos = new List<(double desde, double hasta, bool marca)>();
                if (conMarca && marcaSeg - ini >= 0.4) { tramos.Add((ini, marcaSeg, false)); tramos.Add((marcaSeg, fin, true)); }
                else tramos.Add((ini, fin, conMarca));

                var k = 0;
                foreach (var (desde, hasta, marca) in tramos)
                {
                    var vf = new List<string> { "scale=1280:720:force_original_aspect_ratio=decrease:force_divisible_by=2", "fps=30" };
                    if (marca)
                    {
                        var mx = N(Convert.ToDouble(c["marcaX"]) / 100); var my = N(Convert.ToDouble(c["marcaY"]) / 100);
                        var alto = Convert.ToDouble(c["marcaTamano"] ?? 12.0) / 100;          // fracción del alto del cuadro
                        var h = N(alto); var w = N(alto * 0.55); var h2 = N(alto / 2); var w2 = N(alto * 0.275);
                        var cuando = $"enable='lt(t,{N(congelado)})'";
                        vf.Add($"tpad=start_mode=clone:start_duration={N(congelado)}");
                        // recuadro amarillo con borde negro para que se distinga sobre cualquier fondo
                        vf.Add($"drawbox=x=iw*{mx}-ih*{w2}-3:y=ih*{my}-ih*{h2}-3:w=ih*{w}+6:h=ih*{h}+6:color=black@0.9:t=10:{cuando}");
                        vf.Add($"drawbox=x=iw*{mx}-ih*{w2}:y=ih*{my}-ih*{h2}:w=ih*{w}:h=ih*{h}:color=yellow:t=4:{cuando}");
                    }
                    vf.Add("pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black");
                    if (etiqueta is not null && k == 0)
                        vf.Add($"drawtext=fontfile='{Esc(_fuente)}':textfile='{Esc(etiqueta)}':fontsize=24:fontcolor=white:" +
                               "box=1:boxcolor=black@0.55:boxborderw=10:x=32:y=h-64:enable='lt(t,4)'");
                    var parte = Path.Combine(tmp, $"{n:000}_{k}.mp4");
                    var args = new List<string> { "-ss", N(desde), "-t", N(hasta - desde), "-i", origen, "-vf", string.Join(",", vf) };
                    args.AddRange(norma.Split(' ')); args.Add(parte);
                    await Ffmpeg(ct, [.. args]);
                    partes.Add(parte); k++;
                }
                n++;
            }

            // 3 · unir sin recodificar
            var lista = Path.Combine(tmp, "lista.txt");
            await File.WriteAllLinesAsync(lista, partes.Select(p => $"file '{p}'"), ct);
            await Ffmpeg(ct, "-f", "concat", "-safe", "0", "-i", lista, "-c", "copy", "-movflags", "+faststart", salida);

            var info = await Sondear(salida, ct);
            return new { rutaVideo = salidaRel, duracionSeg = Math.Round(info.Duracion, 2) };
        }
        finally
        {
            try { Directory.Delete(tmp, true); } catch { /* temporal */ }
        }
    }

    // ---------------------------------------------------------------- utilidades

    /// <summary>Escapa una ruta para usarla como valor entre comillas dentro de un filtro de ffmpeg.</summary>
    private static string Esc(string s) => s.Replace("\\", "/").Replace(":", "\\:").Replace("'", "\\'");

    private static ProcessStartInfo Psi(string exe, IEnumerable<string> args)
    {
        var psi = new ProcessStartInfo(exe) { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
        foreach (var a in args) psi.ArgumentList.Add(a);   // sin shell: los nombres de archivo no se interpretan
        return psi;
    }

    private Task Ffmpeg(CancellationToken ct, params string[] args) =>
        Correr(_ffmpeg, ["-y", "-hide_banner", "-loglevel", "error", "-nostdin", .. args], ct);

    private static async Task<(string salida, string error)> Correr(string exe, IEnumerable<string> args, CancellationToken ct)
    {
        using var p = Process.Start(Psi(exe, args)) ?? throw new InvalidOperationException($"No se pudo iniciar {exe}");
        try
        {
            var so = p.StandardOutput.ReadToEndAsync(ct);
            var se = p.StandardError.ReadToEndAsync(ct);
            await p.WaitForExitAsync(ct);
            var (o, e) = (await so, await se);
            if (p.ExitCode != 0)
                throw new InvalidOperationException($"{Path.GetFileName(exe)} terminó con código {p.ExitCode}: {e.Trim().Split('\n').LastOrDefault()}");
            return (o, e);
        }
        catch (OperationCanceledException)
        {
            try { p.Kill(true); } catch { /* ya terminó */ }
            throw;
        }
    }
}
