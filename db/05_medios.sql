/* ============================================================
   05 · Medios: videos y fotos de la temporada
   ============================================================ */
CREATE OR ALTER PROCEDURE med.usp_Medio_AsignarJugadores @MedioId int, @JugadoresJson nvarchar(max)
AS
BEGIN
  SET NOCOUNT ON;
  IF @JugadoresJson IS NULL RETURN;
  IF ISJSON(@JugadoresJson) = 0 THROW 50400, N'Lista de jugadores inválida', 1;
  DECLARE @ids TABLE (JugadorId int PRIMARY KEY);
  INSERT @ids SELECT DISTINCT TRY_CAST(value AS int) FROM OPENJSON(@JugadoresJson) WHERE TRY_CAST(value AS int) IS NOT NULL;
  IF EXISTS (SELECT 1 FROM @ids i WHERE NOT EXISTS (SELECT 1 FROM fut.Jugador j WHERE j.JugadorId = i.JugadorId))
    THROW 50400, N'Uno de los jugadores no existe', 1;
  DELETE med.MedioJugador WHERE MedioId = @MedioId AND JugadorId NOT IN (SELECT JugadorId FROM @ids);
  INSERT med.MedioJugador(MedioId, JugadorId)
  SELECT @MedioId, i.JugadorId FROM @ids i
  WHERE NOT EXISTS (SELECT 1 FROM med.MedioJugador mj WHERE mj.MedioId = @MedioId AND mj.JugadorId = i.JugadorId);
END
GO

/* Registra el medio y decide dónde se guardará. El archivo se sube después por /api/archivo/{id}. */
CREATE OR ALTER PROCEDURE api.usp_Medio_Crear
  @Tipo varchar(5), @Titulo nvarchar(200), @Descripcion nvarchar(1000) = NULL, @TemporadaId int, @PartidoId int = NULL,
  @NombreOriginal nvarchar(260), @TipoMime varchar(100) = NULL, @TamanoBytes bigint,
  @JugadoresJson nvarchar(max) = NULL, @_UsuarioId int
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  SET @Titulo = LTRIM(RTRIM(@Titulo));
  IF @Tipo NOT IN ('VIDEO','FOTO') THROW 50400, N'Tipo de medio inválido', 1;
  IF @Titulo = '' THROW 50400, N'El título es obligatorio', 1;
  IF NOT EXISTS (SELECT 1 FROM fut.Temporada WHERE TemporadaId = @TemporadaId) THROW 50400, N'Temporada inválida', 1;
  IF @PartidoId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM fut.Partido WHERE PartidoId = @PartidoId AND TemporadaId = @TemporadaId)
    THROW 50400, N'El partido no pertenece a la temporada', 1;

  DECLARE @ext varchar(10) = IIF(CHARINDEX('.', @NombreOriginal) = 0, '',
                                 LOWER(RIGHT(@NombreOriginal, CHARINDEX('.', REVERSE(@NombreOriginal)))));
  IF @Tipo = 'VIDEO' AND @ext NOT IN ('.mp4','.mov','.m4v','.mkv','.webm','.avi')
    THROW 50400, N'Formato de video no permitido (mp4, mov, m4v, mkv, webm, avi)', 1;
  IF @Tipo = 'FOTO' AND @ext NOT IN ('.jpg','.jpeg','.png','.webp')
    THROW 50400, N'Formato de foto no permitido (jpg, png, webp)', 1;

  DECLARE @maxMb decimal(18,4) = cat.fn_Param(IIF(@Tipo = 'VIDEO', 'MAX_VIDEO_MB', 'MAX_FOTO_MB'));
  IF @TamanoBytes <= 0 THROW 50400, N'El archivo está vacío', 1;
  IF @TamanoBytes > @maxMb * 1048576
  BEGIN
    DECLARE @m nvarchar(200) = CONCAT(N'El archivo supera el máximo permitido (', CAST(@maxMb AS int), N' MB)');
    THROW 50400, @m, 1;
  END

  -- El tipo MIME se deriva de la extensión validada, no de lo que diga el cliente
  DECLARE @mime varchar(100) = CASE @ext
     WHEN '.mp4' THEN 'video/mp4' WHEN '.m4v' THEN 'video/mp4' WHEN '.mov' THEN 'video/quicktime'
     WHEN '.mkv' THEN 'video/x-matroska' WHEN '.webm' THEN 'video/webm' WHEN '.avi' THEN 'video/x-msvideo'
     WHEN '.png' THEN 'image/png' WHEN '.webp' THEN 'image/webp' ELSE 'image/jpeg' END;
  DECLARE @ruta varchar(300) = CONCAT(YEAR(SYSUTCDATETIME()), '/', LOWER(@Tipo), '/', LOWER(CONVERT(varchar(36), NEWID())), @ext);

  BEGIN TRAN;
    INSERT med.Medio(Tipo, Titulo, Descripcion, TemporadaId, PartidoId, NombreOriginal, TipoMime, TamanoBytes, RutaArchivo, SubidoPor)
    VALUES (@Tipo, @Titulo, @Descripcion, @TemporadaId, @PartidoId, @NombreOriginal, @mime, @TamanoBytes, @ruta, @_UsuarioId);
    DECLARE @id int = SCOPE_IDENTITY();
    EXEC med.usp_Medio_AsignarJugadores @id, @JugadoresJson;
  COMMIT;
  SELECT MedioId = @id;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Medio_Listar
  @TemporadaId int = NULL, @Tipo varchar(5) = NULL, @PartidoId int = NULL, @JugadorId int = NULL,
  @Busqueda nvarchar(100) = NULL, @Pagina int = 1, @Tamano int = 24
AS
BEGIN
  SET NOCOUNT ON;
  IF @Pagina < 1 SET @Pagina = 1;
  IF @Tamano NOT BETWEEN 1 AND 100 SET @Tamano = 24;

  SELECT m.MedioId INTO #f
  FROM med.Medio m
  WHERE m.Eliminado = 0 AND m.Estado <> 'PENDIENTE'
    AND (@TemporadaId IS NULL OR m.TemporadaId = @TemporadaId)
    AND (@Tipo IS NULL OR m.Tipo = @Tipo)
    AND (@PartidoId IS NULL OR m.PartidoId = @PartidoId)
    AND (@Busqueda IS NULL OR m.Titulo LIKE '%' + @Busqueda + '%' OR m.Descripcion LIKE '%' + @Busqueda + '%')
    AND (@JugadorId IS NULL
         OR EXISTS (SELECT 1 FROM med.MedioJugador mj WHERE mj.MedioId = m.MedioId AND mj.JugadorId = @JugadorId)
         OR EXISTS (SELECT 1 FROM hl.Clip c WHERE c.MedioId = m.MedioId AND c.JugadorId = @JugadorId AND c.Estado = 'CONFIRMADO'));

  SELECT m.MedioId, m.Tipo, m.Titulo, m.Descripcion, m.TemporadaId, m.PartidoId, m.Estado, m.DuracionSeg, m.Ancho, m.Alto,
         m.CreadoEn, TieneMiniatura = CAST(IIF(m.RutaMiniatura IS NULL, 0, 1) AS bit),
         Partido = IIF(p.PartidoId IS NULL, NULL, CONCAT(el.Nombre, ' vs ', ev.Nombre)), FechaPartido = p.Fecha,
         Clips = (SELECT COUNT(*) FROM hl.Clip c WHERE c.MedioId = m.MedioId AND c.Estado = 'CONFIRMADO'),
         Candidatos = (SELECT COUNT(*) FROM hl.Clip c WHERE c.MedioId = m.MedioId AND c.Estado = 'CANDIDATO'),
         JugadoresJson = (SELECT j.JugadorId AS id, CONCAT(j.Nombre, ' ', j.Apellidos) AS nombre
                          FROM med.MedioJugador mj JOIN fut.Jugador j ON j.JugadorId = mj.JugadorId
                          WHERE mj.MedioId = m.MedioId FOR JSON PATH)
  FROM #f f
  JOIN med.Medio m ON m.MedioId = f.MedioId
  LEFT JOIN fut.Partido p ON p.PartidoId = m.PartidoId
  LEFT JOIN fut.Equipo el ON el.EquipoId = p.EquipoLocalId
  LEFT JOIN fut.Equipo ev ON ev.EquipoId = p.EquipoVisitaId
  ORDER BY ISNULL(p.Fecha, CAST(m.CreadoEn AS date)) DESC, m.MedioId DESC
  OFFSET (@Pagina - 1) * @Tamano ROWS FETCH NEXT @Tamano ROWS ONLY;

  SELECT Total = COUNT(*), Pagina = @Pagina, Tamano = @Tamano FROM #f;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Medio_Actualizar
  @MedioId int, @Titulo nvarchar(200), @Descripcion nvarchar(1000) = NULL, @PartidoId int = NULL,
  @SegundoInicioPartido decimal(9,2) = NULL, @JugadoresJson nvarchar(max) = NULL
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  SET @Titulo = LTRIM(RTRIM(@Titulo));
  IF @Titulo = '' THROW 50400, N'El título es obligatorio', 1;
  DECLARE @temp int = (SELECT TemporadaId FROM med.Medio WHERE MedioId = @MedioId AND Eliminado = 0);
  IF @temp IS NULL THROW 50404, N'Medio no encontrado', 1;
  IF @PartidoId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM fut.Partido WHERE PartidoId = @PartidoId AND TemporadaId = @temp)
    THROW 50400, N'El partido no pertenece a la temporada del medio', 1;
  IF @SegundoInicioPartido < 0 THROW 50400, N'El inicio del partido no puede ser negativo', 1;
  BEGIN TRAN;
    UPDATE med.Medio SET Titulo=@Titulo, Descripcion=@Descripcion, PartidoId=@PartidoId, SegundoInicioPartido=@SegundoInicioPartido
    WHERE MedioId = @MedioId;
    EXEC med.usp_Medio_AsignarJugadores @MedioId, @JugadoresJson;
    -- Con el arranque del partido se puede calcular el minuto de las jugadas que no lo tengan
    IF @SegundoInicioPartido IS NOT NULL
      UPDATE hl.Clip SET Minuto = CAST(LEAST(130, FLOOR((SegundoEvento - @SegundoInicioPartido) / 60) + 1) AS tinyint)
      WHERE MedioId = @MedioId AND Minuto IS NULL AND SegundoEvento >= @SegundoInicioPartido;
  COMMIT;
  SELECT MedioId = @MedioId;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Medio_Eliminar @MedioId int
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF NOT EXISTS (SELECT 1 FROM med.Medio WHERE MedioId = @MedioId AND Eliminado = 0) THROW 50404, N'Medio no encontrado', 1;
  BEGIN TRAN;
    UPDATE med.Medio SET Eliminado = 1 WHERE MedioId = @MedioId;
    UPDATE fut.Jugador SET FotoMedioId = NULL WHERE FotoMedioId = @MedioId;
    -- Los reels que usaban jugadas de este video dejan de ser válidos hasta regenerarse
    UPDATE r SET Estado = 'BORRADOR', TokenPublico = NULL
    FROM hl.Reel r WHERE EXISTS (SELECT 1 FROM hl.ReelClip rc JOIN hl.Clip c ON c.ClipId = rc.ClipId
                                 WHERE rc.ReelId = r.ReelId AND c.MedioId = @MedioId);
    DELETE rc FROM hl.ReelClip rc JOIN hl.Clip c ON c.ClipId = rc.ClipId WHERE c.MedioId = @MedioId;
  COMMIT;
  SELECT Eliminado = CAST(1 AS bit);
END
GO

/* Señal de comportamiento sobre el video completo: el usuario regresó a ver un tramo. */
CREATE OR ALTER PROCEDURE api.usp_Medio_Interaccion @MedioId int, @Tipo varchar(12), @Segundo int = NULL, @_UsuarioId int
AS
BEGIN
  SET NOCOUNT ON;
  IF @Tipo NOT IN ('VISTA','REPETICION') THROW 50400, N'Tipo de interacción inválido', 1;
  IF NOT EXISTS (SELECT 1 FROM med.Medio WHERE MedioId = @MedioId AND Eliminado = 0) THROW 50404, N'Medio no encontrado', 1;
  -- una vista por usuario cada 30 min; una repetición por usuario y tramo de 10 s
  IF @Tipo = 'VISTA' AND EXISTS (SELECT 1 FROM hl.Interaccion WHERE MedioId = @MedioId AND ClipId IS NULL AND UsuarioId = @_UsuarioId
                                 AND Tipo = 'VISTA' AND CreadoEn > DATEADD(minute, -30, SYSUTCDATETIME())) RETURN;
  IF @Tipo = 'REPETICION' AND (@Segundo IS NULL OR EXISTS (SELECT 1 FROM hl.Interaccion WHERE MedioId = @MedioId AND ClipId IS NULL
                                 AND UsuarioId = @_UsuarioId AND Tipo = 'REPETICION' AND Segundo / 10 = @Segundo / 10)) RETURN;
  INSERT hl.Interaccion(MedioId, UsuarioId, Tipo, Segundo) VALUES (@MedioId, @_UsuarioId, @Tipo, @Segundo);
END
GO
