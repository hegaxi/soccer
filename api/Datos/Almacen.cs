namespace Soccer.Api.Datos;

/// <summary>
/// Almacén de archivos en disco. Las rutas relativas las decide la base de datos;
/// aquí solo se resuelven dentro de la raíz. Para pasar a Azure Blob o S3 se reemplaza esta clase.
/// </summary>
public sealed class Almacen
{
    public string Raiz { get; }
    public long MaxBytesPorParte { get; }

    public Almacen(IConfiguration config, IWebHostEnvironment env)
    {
        var raiz = config["Almacenamiento:Raiz"] ?? "almacen";
        Raiz = Path.GetFullPath(Path.IsPathRooted(raiz) ? raiz : Path.Combine(env.ContentRootPath, raiz));
        MaxBytesPorParte = config.GetValue<long?>("Almacenamiento:MaxBytesPorParte") ?? 16 * 1024 * 1024;
        Directory.CreateDirectory(Raiz);
    }

    public string RutaFisica(string relativa)
    {
        var completa = Path.GetFullPath(Path.Combine(Raiz, relativa));
        if (!completa.StartsWith(Raiz + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            throw new InvalidOperationException("Ruta fuera del almacén");
        return completa;
    }

    public string PrepararEscritura(string relativa)
    {
        var completa = RutaFisica(relativa);
        Directory.CreateDirectory(Path.GetDirectoryName(completa)!);
        return completa;
    }
}
