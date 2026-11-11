/* ============================================================
   08 · Procedimientos internos: los invoca el servidor, nunca el navegador
   (autorización de archivos y cola de trabajos de ffmpeg)
   ============================================================ */
CREATE OR ALTER PROCEDURE sis.usp_Archivo_AutorizarSubida @MedioId int, @_UsuarioId int, @_Rol tinyint
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @estado varchar(12), @dueno int;
  SELECT @estado = Estado, @dueno = SubidoPor FROM med.Medio WHERE MedioId = @MedioId AND Eliminado = 0;
  IF @estado IS NULL THROW 50404, N'Medio no encontrado', 1;
  IF @dueno <> @_UsuarioId AND @_Rol < 3 THROW 50403, N'Solo quien registró el medio puede subir su archivo', 1;
  IF @estado <> 'PENDIENTE' THROW 50409, N'El archivo de este medio ya fue subido', 1;
  SELECT RutaArchivo, TamanoBytes FROM med.Medio WHERE MedioId = @MedioId;
END
GO

CREATE OR ALTER PROCEDURE sis.usp_Archivo_SubidaCompleta @MedioId int
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  BEGIN TRAN;
    UPDATE med.Medio SET Estado = 'SUBIDO' WHERE MedioId = @MedioId AND Estado = 'PENDIENTE';
    IF @@ROWCOUNT = 1 INSERT med.Trabajo(Tipo, MedioId) VALUES ('PROCESAR_MEDIO', @MedioId);
  COMMIT;
  SELECT MedioId, Estado FROM med.Medio WHERE MedioId = @MedioId;
END
GO

/* Variante: 'orig' archivo original · 'web' versión reproducible · 'mini' miniatura.
   Sin sesión solo se entrega, con un enlace vigente, la foto de perfil del jugador del reel y,
   si el enlace los incluye, los partidos completos de donde salen sus jugadas. */
CREATE OR ALTER PROCEDURE sis.usp_Archivo_AutorizarLectura
  @MedioId int, @Variante varchar(5) = 'web', @TokenPublico varchar(40) = NULL, @_UsuarioId int = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @Variante NOT IN ('orig','web','mini') THROW 50400, N'Variante inválida', 1;
  IF @_UsuarioId IS NULL
  BEGIN
    DECLARE @reelEnlace int = hl.fn_EnlaceReel(@TokenPublico);
    IF NOT EXISTS (SELECT 1 FROM hl.Reel r JOIN fut.Jugador j ON j.JugadorId = r.JugadorId
                   WHERE r.ReelId = @reelEnlace AND j.FotoMedioId = @MedioId)
       -- o un partido completo de donde sale una jugada del reel, si el enlace los incluye
       AND NOT EXISTS (SELECT 1 FROM hl.ReelEnlace e JOIN hl.ReelClip rc ON rc.ReelId = e.ReelId JOIN hl.Clip c ON c.ClipId = rc.ClipId
                       WHERE e.Token = @TokenPublico AND e.ReelId = @reelEnlace AND e.IncluyePartidos = 1 AND c.MedioId = @MedioId)
      THROW 50401, N'Inicia sesión para continuar', 1;
    IF @Variante = 'orig' SET @Variante = 'web';
  END
  DECLARE @ruta varchar(300), @mime varchar(100);
  SELECT @ruta = CASE @Variante WHEN 'orig' THEN RutaArchivo WHEN 'web' THEN ISNULL(RutaWeb, RutaArchivo) ELSE RutaMiniatura END,
         @mime = CASE WHEN @Variante = 'orig' OR (@Variante = 'web' AND RutaWeb IS NULL) THEN TipoMime
                      WHEN @Variante = 'web' AND Tipo = 'VIDEO' THEN 'video/mp4' ELSE 'image/jpeg' END
  FROM med.Medio WHERE MedioId = @MedioId AND Eliminado = 0 AND Estado NOT IN ('PENDIENTE');
  IF @ruta IS NULL THROW 50404, N'Archivo no disponible', 1;
  SELECT Ruta = @ruta, Mime = @mime;
END
GO

CREATE OR ALTER PROCEDURE sis.usp_Archivo_AutorizarReel @ReelId int, @TokenPublico varchar(40) = NULL, @_UsuarioId int = NULL
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @ruta varchar(300) = (SELECT RutaVideo FROM hl.Reel WHERE ReelId = @ReelId AND Estado = 'LISTO');
  IF @ruta IS NULL THROW 50404, N'El video del reel no está disponible', 1;
  IF @_UsuarioId IS NULL AND ISNULL(hl.fn_EnlaceReel(@TokenPublico), 0) <> @ReelId
    THROW 50401, N'Inicia sesión para continuar', 1;
  SELECT Ruta = @ruta, Mime = 'video/mp4';
END
GO

/* Resultado de un trabajo. @ResultadoJson:
     PROCESAR_MEDIO: {duracionSeg, ancho, alto, rutaWeb, rutaMiniatura, picos:[{s,i}]}
     RENDER_REEL:    {rutaVideo, duracionSeg} */
CREATE OR ALTER PROCEDURE sis.usp_Trabajo_Completar
  @TrabajoId int, @Exito bit, @Error nvarchar(500) = NULL, @ResultadoJson nvarchar(max) = NULL
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  DECLARE @tipo varchar(15), @medio int, @reel int;
  SELECT @tipo = Tipo, @medio = MedioId, @reel = ReelId FROM med.Trabajo WHERE TrabajoId = @TrabajoId AND Estado = 'EN_PROCESO';
  IF @tipo IS NULL THROW 50404, N'Trabajo no encontrado o ya terminado', 1;

  BEGIN TRAN;
    UPDATE med.Trabajo SET Estado = IIF(@Exito = 1, 'TERMINADO', 'ERROR'), Error = @Error, TerminadoEn = SYSUTCDATETIME()
    WHERE TrabajoId = @TrabajoId;

    IF @tipo = 'PROCESAR_MEDIO'
    BEGIN
      IF @Exito = 1
      BEGIN
        UPDATE med.Medio SET Estado = 'LISTO', ErrorProceso = NULL,
               DuracionSeg   = TRY_CAST(JSON_VALUE(@ResultadoJson, '$.duracionSeg') AS decimal(9,2)),
               Ancho         = TRY_CAST(JSON_VALUE(@ResultadoJson, '$.ancho') AS int),
               Alto          = TRY_CAST(JSON_VALUE(@ResultadoJson, '$.alto') AS int),
               RutaWeb       = JSON_VALUE(@ResultadoJson, '$.rutaWeb'),
               RutaMiniatura = JSON_VALUE(@ResultadoJson, '$.rutaMiniatura')
        WHERE MedioId = @medio;
        DELETE med.PicoAudio WHERE MedioId = @medio;
        INSERT med.PicoAudio(MedioId, Segundo, Intensidad)
        SELECT @medio, p.s, MAX(p.i) FROM OPENJSON(@ResultadoJson, '$.picos') WITH (s int '$.s', i decimal(6,2) '$.i') p
        WHERE p.s IS NOT NULL AND p.i IS NOT NULL GROUP BY p.s;
        IF EXISTS (SELECT 1 FROM med.Medio WHERE MedioId = @medio AND Tipo = 'VIDEO')
          EXEC hl.usp_Candidatos_Generar @medio;
      END
      ELSE UPDATE med.Medio SET Estado = 'ERROR', ErrorProceso = @Error WHERE MedioId = @medio;
    END
    ELSE IF @tipo = 'RENDER_REEL'
    BEGIN
      -- si el montaje cambió mientras se renderizaba, el reel ya volvió a BORRADOR y este resultado se descarta
      IF @Exito = 1
        UPDATE hl.Reel SET Estado = 'LISTO', ErrorProceso = NULL, RutaVideo = JSON_VALUE(@ResultadoJson, '$.rutaVideo'),
               DuracionSeg = TRY_CAST(JSON_VALUE(@ResultadoJson, '$.duracionSeg') AS decimal(9,2))
        WHERE ReelId = @reel AND Estado = 'EN_COLA';
      ELSE UPDATE hl.Reel SET Estado = 'ERROR', ErrorProceso = @Error WHERE ReelId = @reel AND Estado = 'EN_COLA';
    END
  COMMIT;
END
GO
/* Toma el siguiente trabajo de la cola (seguro con varios procesadores en paralelo). */
CREATE OR ALTER PROCEDURE sis.usp_Trabajo_Tomar
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  DECLARE @t TABLE (TrabajoId int, Tipo varchar(15), MedioId int, ReelId int, Intentos tinyint);
  BEGIN TRAN;
    ;WITH q AS (
      SELECT TOP (1) * FROM med.Trabajo WITH (UPDLOCK, READPAST, ROWLOCK)
      WHERE Estado = 'PENDIENTE' OR (Estado = 'EN_PROCESO' AND TomadoEn < DATEADD(hour, -3, SYSUTCDATETIME()))
      ORDER BY TrabajoId)
    UPDATE q SET Estado = 'EN_PROCESO', TomadoEn = SYSUTCDATETIME(), Intentos += 1
    OUTPUT inserted.TrabajoId, inserted.Tipo, inserted.MedioId, inserted.ReelId, inserted.Intentos INTO @t;
    UPDATE m SET Estado = 'PROCESANDO' FROM med.Medio m JOIN @t t ON t.MedioId = m.MedioId;
  COMMIT;

  DECLARE @id int, @reel int, @intentos tinyint;
  SELECT @id = TrabajoId, @reel = ReelId, @intentos = Intentos FROM @t;
  IF @id IS NULL RETURN;
  IF @intentos > 3
  BEGIN
    EXEC sis.usp_Trabajo_Completar @id, 0, N'Se agotaron los reintentos', NULL;
    RETURN;
  END

  SELECT t.TrabajoId, t.Tipo, t.MedioId, t.ReelId, TipoMedio = m.Tipo, m.RutaArchivo,
         TarjetaSeg = cat.fn_Param('REEL_TARJETA_SEG'), CongeladoSeg = cat.fn_Param('REEL_CONGELADO_SEG'),
         RutaSalida = IIF(t.ReelId IS NULL, NULL, CONCAT('reels/', t.ReelId, '_', LOWER(CONVERT(varchar(36), NEWID())), '.mp4'))
  FROM @t t LEFT JOIN med.Medio m ON m.MedioId = t.MedioId;

  IF @reel IS NULL RETURN;

  -- jugadas a montar, en orden
  -- la etiqueta dice a quién mirar: color del uniforme y dorsal, además de rival y fecha
  SELECT rc.Orden, Ruta = ISNULL(m.RutaWeb, m.RutaArchivo), v.SegundoInicio, v.SegundoFin, v.MarcaX, v.MarcaY, v.MarcaTamano, v.MarcaSegundo,
         Etiqueta = CONCAT_WS(N'  |  ', UPPER(v.TipoEvento) + IIF(v.Resultado = 'F', N' (fallida)', N''),
                              N'vs ' + v.Rival, CONVERT(nvarchar(10), v.FechaPartido, 103), N'min ' + CAST(v.Minuto AS nvarchar(3)),
                              NULLIF(CONCAT_WS(N' ', N'de ' + LOWER(v.ColorUniforme), N'#' + CAST(v.Dorsal AS nvarchar(3))), N''))
  FROM hl.ReelClip rc JOIN hl.vw_ClipPuntaje v ON v.ClipId = rc.ClipId JOIN med.Medio m ON m.MedioId = v.MedioId
  WHERE rc.ReelId = @reel ORDER BY rc.Orden;

  -- tarjeta inicial: lo que un visor necesita saber antes de la primera jugada.
  -- El video se puede descargar y ya no se puede retirar: por eso no lleva contacto ni fecha de nacimiento completa
  -- (el contacto está en la página del enlace, que sí caduca y se revoca).
  SELECT x.Orden, x.Texto, x.Tamano
  FROM hl.Reel r
  JOIN fut.Jugador j ON j.JugadorId = r.JugadorId
  JOIN cat.Posicion p ON p.PosicionId = j.PosicionId
  LEFT JOIN cat.Posicion p2 ON p2.PosicionId = j.PosicionSecundariaId
  LEFT JOIN fut.Equipo e ON e.EquipoId = j.EquipoId
  CROSS APPLY (VALUES
    (1, UPPER(CONCAT(j.Nombre, ' ', j.Apellidos)), 68),
    (2, CONCAT_WS(N'  |  ', p.Nombre + ISNULL(N' / ' + p2.Nombre, N''), N'#' + CAST(j.Dorsal AS nvarchar(3)), e.Nombre), 38),
    (3, CONCAT_WS(N'  |  ', N'Categoría ' + CAST(YEAR(j.FechaNacimiento) AS nvarchar(4)),
                  CAST(CAST(j.EstaturaCm / 100.0 AS decimal(3,2)) AS nvarchar(5)) + N' m',
                  CAST(j.PesoKg AS nvarchar(3)) + N' kg',
                  CASE j.PieDominante WHEN 'D' THEN N'Pie derecho' WHEN 'I' THEN N'Pie izquierdo' ELSE N'Ambidiestro' END,
                  N'Class of ' + CAST(j.AnioGraduacion AS nvarchar(4))), 30),
    (4, r.Titulo, 22)
  ) x(Orden, Texto, Tamano)
  WHERE r.ReelId = @reel AND NULLIF(x.Texto, N'') IS NOT NULL
  ORDER BY x.Orden;
END
GO

