using System.Data;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace Soccer.Api.Datos;

/// <summary>Error de negocio lanzado por la base (THROW 50000 + código HTTP) o por validación de parámetros.</summary>
public sealed class ErrorNegocio(int estado, string mensaje) : Exception(mensaje)
{
    public int Estado { get; } = estado;
}

public sealed record Contexto(string? Token, string? Ip);

public sealed class Resultado
{
    public List<List<Dictionary<string, object?>>> Conjuntos { get; } = [];
    public Dictionary<string, object?> Salida { get; } = [];
    public string EfectoSesion { get; set; } = "";
    /// <summary>Token de sesión emitido por la base (columna "_token"); nunca se serializa al cliente.</summary>
    public string? TokenEmitido { get; set; }

    public Dictionary<string, object?>? PrimeraFila(int conjunto = 0) =>
        Conjuntos.Count > conjunto && Conjuntos[conjunto].Count > 0 ? Conjuntos[conjunto][0] : null;
}

/// <summary>
/// Único camino hacia la base de datos. No conoce ningún procedimiento:
///   1. meta.usp_Accion_Resolver valida acción, sesión y rol, y devuelve el procedimiento y sus parámetros.
///   2. Los parámetros se enlazan por nombre contra el JSON recibido, con el tipo que declara el procedimiento.
///   3. Los que empiezan con "@_" los pone el servidor (usuario, rol, IP, token) y el cliente no puede enviarlos.
/// </summary>
public sealed class EjecutorSp(IConfiguration config, ILogger<EjecutorSp> log)
{
    private readonly string _cadena = config.GetConnectionString("Soccer") is { Length: > 0 } c
        ? c : throw new InvalidOperationException("Falta ConnectionStrings:Soccer");

    private sealed record ParamMeta(string Nombre, string Tipo, short Longitud, byte Precision, byte Escala, bool EsSalida);

    public Task<Resultado> EjecutarAsync(string accion, JsonElement? parametros, Contexto ctx, CancellationToken ct) =>
        EjecutarAsync(accion, parametros, ctx, interna: false, ct);

    /// <summary>Acciones que solo invoca el servidor (archivos y cola de trabajos).</summary>
    public Task<Resultado> EjecutarInternaAsync(string accion, object? parametros, Contexto? ctx, CancellationToken ct)
    {
        JsonElement? json = parametros is null ? null : JsonSerializer.SerializeToElement(parametros);
        return EjecutarAsync(accion, json, ctx ?? new Contexto(null, null), interna: true, ct);
    }

    private async Task<Resultado> EjecutarAsync(string accion, JsonElement? parametros, Contexto ctx, bool interna, CancellationToken ct)
    {
        try
        {
            await using var cn = new SqlConnection(_cadena);
            await cn.OpenAsync(ct);

            // 1 · resolver la acción
            string procedimiento; int? usuarioId; byte rol; var resultado = new Resultado();
            var metas = new List<ParamMeta>();
            await using (var cmd = new SqlCommand("meta.usp_Accion_Resolver", cn) { CommandType = CommandType.StoredProcedure })
            {
                cmd.Parameters.Add("@Clave", SqlDbType.VarChar, 100).Value = accion;
                cmd.Parameters.Add("@Token", SqlDbType.VarChar, 64).Value = (object?)ctx.Token ?? DBNull.Value;
                cmd.Parameters.Add("@Interna", SqlDbType.Bit).Value = interna;
                await using var rd = await cmd.ExecuteReaderAsync(ct);
                if (!await rd.ReadAsync(ct)) throw new ErrorNegocio(404, "Acción no encontrada");
                procedimiento = rd.GetString(0);
                usuarioId = rd.IsDBNull(1) ? null : rd.GetInt32(1);
                rol = rd.GetByte(2);
                resultado.EfectoSesion = rd.GetString(3);
                await rd.NextResultAsync(ct);
                while (await rd.ReadAsync(ct))
                    metas.Add(new ParamMeta(rd.GetString(0), rd.GetString(1), rd.GetInt16(2), rd.GetByte(3), rd.GetByte(4), rd.GetBoolean(5)));
            }

            // 2 · enlazar parámetros
            var recibidos = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
            if (parametros is { ValueKind: JsonValueKind.Object } obj)
                foreach (var p in obj.EnumerateObject())
                {
                    if (p.Name.StartsWith('_')) throw new ErrorNegocio(400, $"Parámetro no permitido: {p.Name}");
                    recibidos[p.Name] = p.Value;
                }
            else if (parametros is { ValueKind: not (JsonValueKind.Null or JsonValueKind.Undefined) })
                throw new ErrorNegocio(400, "Los parámetros deben ser un objeto JSON");

            await using var sp = new SqlCommand(procedimiento, cn) { CommandType = CommandType.StoredProcedure, CommandTimeout = 60 };
            foreach (var m in metas)
            {
                var nombre = m.Nombre.TrimStart('@');
                var prm = CrearParametro(m);
                if (m.EsSalida) { prm.Direction = ParameterDirection.Output; sp.Parameters.Add(prm); continue; }

                if (nombre.StartsWith('_'))
                {
                    prm.Value = nombre.ToLowerInvariant() switch
                    {
                        "_usuarioid" => (object?)usuarioId ?? DBNull.Value,
                        "_rol" => rol,
                        "_ip" => (object?)ctx.Ip ?? DBNull.Value,
                        "_token" => (object?)ctx.Token ?? DBNull.Value,
                        _ => throw new InvalidOperationException($"Parámetro de sistema desconocido {m.Nombre} en {procedimiento}")
                    };
                    sp.Parameters.Add(prm);
                }
                else if (recibidos.Remove(nombre, out var valor))
                {
                    prm.Value = Convertir(valor, m, nombre);
                    sp.Parameters.Add(prm);
                }
                // si no llegó, no se envía: aplica el valor por defecto del procedimiento (o SQL avisa que es obligatorio)
            }
            if (recibidos.Count > 0)
                throw new ErrorNegocio(400, $"Parámetro desconocido: {string.Join(", ", recibidos.Keys)}");

            // 3 · ejecutar y leer todos los conjuntos de resultados
            await using (var rd = await sp.ExecuteReaderAsync(ct))
            {
                do
                {
                    if (rd.FieldCount == 0) continue;
                    var filas = new List<Dictionary<string, object?>>();
                    while (await rd.ReadAsync(ct))
                    {
                        var fila = new Dictionary<string, object?>(rd.FieldCount);
                        for (var i = 0; i < rd.FieldCount; i++)
                        {
                            var col = rd.GetName(i);
                            var v = rd.IsDBNull(i) ? null : rd.GetValue(i);
                            if (col == "_token") { resultado.TokenEmitido = v as string; continue; }
                            // Convención: una columna "XxxJson" trae JSON embebido y se entrega como "xxx"
                            if (col.EndsWith("Json", StringComparison.Ordinal) && col.Length > 4)
                            {
                                fila[Camel(col[..^4])] = v is string s && s.Length > 0 ? JsonSerializer.Deserialize<JsonElement>(s) : null;
                                continue;
                            }
                            fila[Camel(col)] = v switch
                            {
                                DateTime d when rd.GetDataTypeName(i) == "date" => d.ToString("yyyy-MM-dd"),
                                DateTime d => DateTime.SpecifyKind(d, DateTimeKind.Utc),
                                _ => v
                            };
                        }
                        filas.Add(fila);
                    }
                    resultado.Conjuntos.Add(filas);
                } while (await rd.NextResultAsync(ct));
            }
            foreach (SqlParameter p in sp.Parameters)
                if (p.Direction == ParameterDirection.Output)
                    resultado.Salida[Camel(p.ParameterName.TrimStart('@'))] = p.Value is DBNull ? null : p.Value;
            return resultado;
        }
        catch (SqlException ex) when (ex.Number is >= 50400 and <= 50599)
        {
            throw new ErrorNegocio(ex.Number - 50000, ex.Message);
        }
        catch (SqlException ex) when (ex.Number == 201)   // falta un parámetro obligatorio
        {
            var falta = ex.Message.Split('\'').Skip(3).FirstOrDefault()?.TrimStart('@');
            throw new ErrorNegocio(400, falta is null ? "Falta un parámetro obligatorio" : $"Falta el parámetro obligatorio: {Camel(falta)}");
        }
        catch (SqlException ex)
        {
            log.LogError(ex, "Error SQL {Numero} en la acción {Accion}", ex.Number, accion);
            throw;
        }
    }

    private static string Camel(string s) => s.Length == 0 || char.IsLower(s[0]) ? s : char.ToLowerInvariant(s[0]) + s[1..];

    private static SqlParameter CrearParametro(ParamMeta m)
    {
        var tipo = m.Tipo.ToLowerInvariant() switch
        {
            "int" => SqlDbType.Int, "bigint" => SqlDbType.BigInt, "smallint" => SqlDbType.SmallInt, "tinyint" => SqlDbType.TinyInt,
            "bit" => SqlDbType.Bit, "decimal" or "numeric" => SqlDbType.Decimal, "float" => SqlDbType.Float, "real" => SqlDbType.Real,
            "date" => SqlDbType.Date, "datetime2" => SqlDbType.DateTime2, "datetime" => SqlDbType.DateTime,
            "nvarchar" => SqlDbType.NVarChar, "varchar" => SqlDbType.VarChar, "nchar" => SqlDbType.NChar, "char" => SqlDbType.Char,
            "uniqueidentifier" => SqlDbType.UniqueIdentifier,
            var otro => throw new InvalidOperationException($"Tipo de parámetro no soportado: {otro}")
        };
        var p = new SqlParameter(m.Nombre, tipo);
        switch (tipo)
        {
            case SqlDbType.NVarChar or SqlDbType.NChar: p.Size = m.Longitud < 0 ? -1 : m.Longitud / 2; break;
            case SqlDbType.VarChar or SqlDbType.Char: p.Size = m.Longitud; break;
            case SqlDbType.Decimal: p.Precision = m.Precision; p.Scale = m.Escala; break;
        }
        return p;
    }

    private static object Convertir(JsonElement v, ParamMeta m, string nombre)
    {
        if (v.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return DBNull.Value;
        ErrorNegocio Invalido() => new(400, $"Valor inválido para {Camel(nombre)}");
        try
        {
            switch (m.Tipo.ToLowerInvariant())
            {
                case "int": return Numero(v, out var d) && d == Math.Truncate(d) ? checked((int)d) : throw Invalido();
                case "bigint": return Numero(v, out d) && d == Math.Truncate(d) ? checked((long)d) : throw Invalido();
                case "smallint": return Numero(v, out d) && d == Math.Truncate(d) ? checked((short)d) : throw Invalido();
                case "tinyint": return Numero(v, out d) && d == Math.Truncate(d) ? checked((byte)d) : throw Invalido();
                case "decimal" or "numeric" or "float" or "real": return Numero(v, out d) ? d : throw Invalido();
                case "bit":
                    return v.ValueKind switch
                    {
                        JsonValueKind.True => true, JsonValueKind.False => false,
                        JsonValueKind.Number => v.GetDecimal() != 0,
                        JsonValueKind.String when bool.TryParse(v.GetString(), out var b) => b,
                        _ => throw Invalido()
                    };
                case "date" or "datetime2" or "datetime":
                    return v.ValueKind == JsonValueKind.String && DateTime.TryParse(v.GetString(),
                        System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.AdjustToUniversal, out var f)
                        ? f : throw Invalido();
                case "uniqueidentifier":
                    return v.ValueKind == JsonValueKind.String && Guid.TryParse(v.GetString(), out var g) ? g : throw Invalido();
                default:
                    // texto: los objetos y arreglos viajan como JSON para que el procedimiento los abra con OPENJSON
                    var s = v.ValueKind switch
                    {
                        JsonValueKind.String => v.GetString()!,
                        JsonValueKind.Object or JsonValueKind.Array => v.GetRawText(),
                        JsonValueKind.True => "1", JsonValueKind.False => "0",
                        _ => v.GetRawText()
                    };
                    var max = m.Longitud < 0 ? int.MaxValue : m.Tipo.StartsWith('n') ? m.Longitud / 2 : m.Longitud;
                    if (s.Length > max) throw new ErrorNegocio(400, $"{Camel(nombre)} supera los {max} caracteres");
                    return s;
            }
        }
        catch (OverflowException) { throw Invalido(); }
    }

    private static bool Numero(JsonElement v, out decimal d)
    {
        d = 0;
        return v.ValueKind switch
        {
            JsonValueKind.Number => v.TryGetDecimal(out d),
            JsonValueKind.String => decimal.TryParse(v.GetString(), System.Globalization.NumberStyles.Number,
                System.Globalization.CultureInfo.InvariantCulture, out d),
            _ => false
        };
    }
}
