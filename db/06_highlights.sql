/* ============================================================
   06 · Jugadas (clips), puntaje y ranking de highlights
   ============================================================ */
CREATE OR ALTER VIEW cat.vw_Parametros AS
SELECT
  ESCALA_TECNICA       = CAST(MAX(IIF(Clave='ESCALA_TECNICA',       Valor, NULL)) AS float),
  BONO_DECISIVA        = CAST(MAX(IIF(Clave='BONO_DECISIVA',        Valor, NULL)) AS float),
  BONO_PIE_DEBIL       = CAST(MAX(IIF(Clave='BONO_PIE_DEBIL',       Valor, NULL)) AS float),
  BONO_TRAMO_FINAL     = CAST(MAX(IIF(Clave='BONO_TRAMO_FINAL',     Valor, NULL)) AS float),
  FACTOR_FALLIDA       = CAST(MAX(IIF(Clave='FACTOR_FALLIDA',       Valor, NULL)) AS float),
  PESO_GEN_TECNICO     = CAST(MAX(IIF(Clave='PESO_GEN_TECNICO',     Valor, NULL)) AS float),
  PESO_GEN_INTERACCION = CAST(MAX(IIF(Clave='PESO_GEN_INTERACCION', Valor, NULL)) AS float),
  PESO_GEN_AUDIO       = CAST(MAX(IIF(Clave='PESO_GEN_AUDIO',       Valor, NULL)) AS float),
  PESO_REC_TECNICO     = CAST(MAX(IIF(Clave='PESO_REC_TECNICO',     Valor, NULL)) AS float),
  PESO_REC_INTERACCION = CAST(MAX(IIF(Clave='PESO_REC_INTERACCION', Valor, NULL)) AS float),
  PESO_REC_AUDIO       = CAST(MAX(IIF(Clave='PESO_REC_AUDIO',       Valor, NULL)) AS float)
FROM cat.Parametro;
GO

/* Puntaje de cada jugada confirmada. Tres componentes en escala 0-100:
     Tecnico     = valor de la jugada × relevancia para la posición × calidad × nivel del rival × fase
                   × (1 + bonos: decisiva, pie no dominante, tramo final) ; ×factor si fue fallida ;
                   el valor bruto se lleva a 0-100 con 100·(1 − e^(−bruto/ESCALA_TECNICA))
     Interaccion = likes y repeticiones por vista (suavizado bayesiano) + volumen de vistas
     Audio       = pico de ruido ambiente dentro del clip (reacción de la grada/banca)
   y dos mezclas: PuntajeGeneral (galería) y PuntajeReclutamiento (pesa casi solo lo técnico). */
CREATE OR ALTER VIEW hl.vw_ClipPuntaje AS
SELECT c.ClipId, c.MedioId, c.JugadorId, c.TipoEventoId, m.TemporadaId, m.PartidoId,
       c.SegundoEvento, c.SegundoInicio, c.SegundoFin, DuracionSeg = c.SegundoFin - c.SegundoInicio,
       c.Minuto, c.Resultado, c.Pie, c.Calidad, c.EsDecisiva, c.MarcaX, c.MarcaY, c.Nota, c.CreadoEn,
       TipoEvento = te.Nombre, TipoEventoClave = te.Clave, te.Categoria,
       Jugador = CONCAT(j.Nombre, ' ', j.Apellidos), j.PosicionId,
       MultPosicion = ISNULL(ppe.Multiplicador, 1.00),
       EsPieDebil = b.EsPieDebil,
       Rival = CASE WHEN p.PartidoId IS NULL THEN NULL
                    WHEN j.EquipoId = p.EquipoVisitaId THEN el.Nombre ELSE ev.Nombre END,
       p.NivelRival, FechaPartido = p.Fecha, Fase = f.Nombre,
       Vistas = ISNULL(it.Vistas, 0), Repeticiones = ISNULL(it.Repeticiones, 0), MeGusta = ISNULL(mg.MeGusta, 0),
       Tecnico     = CAST(x.Tecnico AS decimal(6,2)),
       Interaccion = CAST(x.Interaccion AS decimal(6,2)),
       Audio       = CAST(x.Audio AS decimal(6,2)),
       PuntajeGeneral       = CAST(pr.PESO_GEN_TECNICO * x.Tecnico + pr.PESO_GEN_INTERACCION * x.Interaccion + pr.PESO_GEN_AUDIO * x.Audio AS decimal(6,2)),
       PuntajeReclutamiento = CAST(pr.PESO_REC_TECNICO * x.Tecnico + pr.PESO_REC_INTERACCION * x.Interaccion + pr.PESO_REC_AUDIO * x.Audio AS decimal(6,2))
FROM hl.Clip c
JOIN med.Medio m       ON m.MedioId = c.MedioId AND m.Eliminado = 0
JOIN fut.Jugador j     ON j.JugadorId = c.JugadorId
JOIN cat.TipoEvento te ON te.TipoEventoId = c.TipoEventoId
LEFT JOIN fut.Partido p     ON p.PartidoId = m.PartidoId
LEFT JOIN fut.Equipo el     ON el.EquipoId = p.EquipoLocalId
LEFT JOIN fut.Equipo ev     ON ev.EquipoId = p.EquipoVisitaId
LEFT JOIN cat.FasePartido f ON f.Clave = p.Fase
LEFT JOIN cat.PesoPosicionEvento ppe ON ppe.PosicionId = j.PosicionId AND ppe.TipoEventoId = c.TipoEventoId
CROSS JOIN cat.vw_Parametros pr
CROSS APPLY (SELECT EsPieDebil = CAST(IIF((j.PieDominante = 'D' AND c.Pie = 'I') OR (j.PieDominante = 'I' AND c.Pie = 'D'), 1, 0) AS bit)) b
OUTER APPLY (SELECT Vistas = SUM(IIF(i.Tipo = 'VISTA', 1, 0)), Repeticiones = SUM(IIF(i.Tipo = 'REPETICION', 1, 0))
             FROM hl.Interaccion i WHERE i.ClipId = c.ClipId) it
OUTER APPLY (SELECT MeGusta = COUNT(*) FROM hl.MeGusta g WHERE g.ClipId = c.ClipId) mg
OUTER APPLY (SELECT Pico = MAX(pa.Intensidad) FROM med.PicoAudio pa
             WHERE pa.MedioId = c.MedioId AND pa.Segundo BETWEEN c.SegundoInicio AND c.SegundoFin + 3) au
CROSS APPLY (SELECT
   Tecnico = 100.0 * (1.0 - EXP(-(
       CAST(te.PesoBase AS float) * ISNULL(ppe.Multiplicador, 1.0)
       * (0.55 + 0.15 * ISNULL(c.Calidad, 3))            -- 1★=0.70 … 3★=1.00 … 5★=1.30
       * (0.80 + 0.08 * ISNULL(p.NivelRival, 3))         -- rival débil 0.88 … élite 1.20
       * ISNULL(CAST(f.Factor AS float), 1.0)
       * IIF(c.Resultado = 'F', pr.FACTOR_FALLIDA, 1.0)
       * (1.0 + IIF(c.EsDecisiva = 1, pr.BONO_DECISIVA, 0.0)
              + IIF(b.EsPieDebil = 1, pr.BONO_PIE_DEBIL, 0.0)
              + IIF(c.Minuto >= 75, pr.BONO_TRAMO_FINAL, 0.0))
       ) / pr.ESCALA_TECNICA)),   -- curva saturante: ordena sin tope duro, las mejores se acercan a 100 sin empatar
   Interaccion = 100.0 * ( 0.60 * LEAST(1.0, ((ISNULL(mg.MeGusta, 0) + 1.0) / (ISNULL(it.Vistas, 0) + 20.0)) / 0.30)
                         + 0.25 * LEAST(1.0, ((ISNULL(it.Repeticiones, 0) + 1.0) / (ISNULL(it.Vistas, 0) + 20.0)) / 0.50)
                         + 0.15 * LEAST(1.0, LOG(1.0 + ISNULL(it.Vistas, 0)) / LOG(201.0)) ),
   Audio = LEAST(100.0, ISNULL(CAST(au.Pico AS float), 0.0) * 20.0)
) x
WHERE c.Estado = 'CONFIRMADO';
GO

/* Crea o edita una jugada. Confirmar un candidato automático es editarlo con jugador y tipo. */
CREATE OR ALTER PROCEDURE api.usp_Clip_Guardar
  @ClipId int = NULL, @MedioId int = NULL, @JugadorId int, @TipoEventoId smallint, @SegundoEvento decimal(9,2),
  @SegundoInicio decimal(9,2) = NULL, @SegundoFin decimal(9,2) = NULL, @Minuto tinyint = NULL,
  @Resultado char(1) = 'E', @Pie char(1) = NULL, @Calidad tinyint = NULL, @EsDecisiva bit = 0,
  @MarcaX decimal(5,2) = NULL, @MarcaY decimal(5,2) = NULL, @Nota nvarchar(300) = NULL, @_UsuarioId int
AS
BEGIN
  SET NOCOUNT ON;
  IF @ClipId IS NOT NULL SELECT @MedioId = MedioId FROM hl.Clip WHERE ClipId = @ClipId;
  DECLARE @dur decimal(9,2), @ini decimal(9,2), @tipoMedio varchar(5);
  SELECT @dur = DuracionSeg, @ini = SegundoInicioPartido, @tipoMedio = Tipo FROM med.Medio WHERE MedioId = @MedioId AND Eliminado = 0;
  IF @tipoMedio IS NULL THROW 50404, N'Video no encontrado', 1;
  IF @tipoMedio <> 'VIDEO' THROW 50400, N'Solo se pueden marcar jugadas en videos', 1;
  IF NOT EXISTS (SELECT 1 FROM fut.Jugador WHERE JugadorId = @JugadorId) THROW 50400, N'Jugador inválido', 1;
  DECLARE @pre tinyint, @post tinyint;
  SELECT @pre = PreRollSeg, @post = PostRollSeg FROM cat.TipoEvento WHERE TipoEventoId = @TipoEventoId;
  IF @pre IS NULL THROW 50400, N'Tipo de jugada inválido', 1;
  IF @Resultado NOT IN ('E','F') THROW 50400, N'Resultado inválido', 1;
  IF @Pie IS NOT NULL AND @Pie NOT IN ('D','I','C') THROW 50400, N'Pie inválido', 1;
  IF @Calidad IS NOT NULL AND @Calidad NOT BETWEEN 1 AND 5 THROW 50400, N'La calidad va de 1 a 5', 1;
  IF @MarcaX NOT BETWEEN 0 AND 100 OR @MarcaY NOT BETWEEN 0 AND 100 THROW 50400, N'Marca fuera del cuadro', 1;
  IF @SegundoEvento < 0 OR (@dur IS NOT NULL AND @SegundoEvento > @dur) THROW 50400, N'El momento de la jugada está fuera del video', 1;

  -- Ventana por defecto: un reclutador necesita ver cómo se origina la jugada y cómo termina
  SET @SegundoInicio = GREATEST(0, ISNULL(@SegundoInicio, @SegundoEvento - @pre));
  SET @SegundoFin    = ISNULL(@SegundoFin, @SegundoEvento + @post);
  IF @dur IS NOT NULL SET @SegundoFin = LEAST(@SegundoFin, @dur);
  IF @SegundoFin - @SegundoInicio < 2 THROW 50400, N'El clip debe durar al menos 2 segundos', 1;
  IF @SegundoFin - @SegundoInicio > 45 THROW 50400, N'El clip no debe pasar de 45 segundos; recorta a lo esencial', 1;
  IF @SegundoEvento NOT BETWEEN @SegundoInicio AND @SegundoFin THROW 50400, N'El momento de la jugada debe quedar dentro del clip', 1;

  IF @Minuto IS NULL AND @ini IS NOT NULL AND @SegundoEvento >= @ini
    SET @Minuto = CAST(LEAST(130, FLOOR((@SegundoEvento - @ini) / 60) + 1) AS tinyint);

  IF @ClipId IS NULL
  BEGIN
    INSERT hl.Clip(MedioId, JugadorId, TipoEventoId, SegundoEvento, SegundoInicio, SegundoFin, Minuto, Resultado, Pie, Calidad,
                   EsDecisiva, MarcaX, MarcaY, Nota, Origen, Estado, CreadoPor)
    VALUES (@MedioId, @JugadorId, @TipoEventoId, @SegundoEvento, @SegundoInicio, @SegundoFin, @Minuto, @Resultado, @Pie, @Calidad,
            @EsDecisiva, @MarcaX, @MarcaY, @Nota, 'MANUAL', 'CONFIRMADO', @_UsuarioId);
    SET @ClipId = SCOPE_IDENTITY();
  END
  ELSE
  BEGIN
    UPDATE hl.Clip SET JugadorId=@JugadorId, TipoEventoId=@TipoEventoId, SegundoEvento=@SegundoEvento, SegundoInicio=@SegundoInicio,
           SegundoFin=@SegundoFin, Minuto=@Minuto, Resultado=@Resultado, Pie=@Pie, Calidad=@Calidad, EsDecisiva=@EsDecisiva,
           MarcaX=@MarcaX, MarcaY=@MarcaY, Nota=@Nota, Estado='CONFIRMADO'
    WHERE ClipId = @ClipId;
    -- un reel ya renderizado que incluye esta jugada queda desactualizado
    UPDATE r SET Estado = 'BORRADOR' FROM hl.Reel r
    WHERE r.Estado IN ('LISTO','ERROR') AND EXISTS (SELECT 1 FROM hl.ReelClip rc WHERE rc.ReelId = r.ReelId AND rc.ClipId = @ClipId);
  END
  -- un candidato automático que cae dentro de esta jugada ya quedó atendido
  UPDATE hl.Clip SET Estado = 'DESCARTADO'
  WHERE MedioId = @MedioId AND Estado = 'CANDIDATO' AND ClipId <> @ClipId AND SegundoEvento BETWEEN @SegundoInicio AND @SegundoFin;
  -- el jugador queda etiquetado en el video
  IF NOT EXISTS (SELECT 1 FROM med.MedioJugador WHERE MedioId = @MedioId AND JugadorId = @JugadorId)
    INSERT med.MedioJugador(MedioId, JugadorId) VALUES (@MedioId, @JugadorId);

  SELECT ClipId, Tecnico, Interaccion, Audio, PuntajeGeneral, PuntajeReclutamiento FROM hl.vw_ClipPuntaje WHERE ClipId = @ClipId;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Clip_Eliminar @ClipId int
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  IF NOT EXISTS (SELECT 1 FROM hl.Clip WHERE ClipId = @ClipId) THROW 50404, N'Jugada no encontrada', 1;
  BEGIN TRAN;
    UPDATE r SET Estado = 'BORRADOR' FROM hl.Reel r
    WHERE r.Estado <> 'EN_COLA' AND EXISTS (SELECT 1 FROM hl.ReelClip rc WHERE rc.ReelId = r.ReelId AND rc.ClipId = @ClipId);
    DELETE hl.ReelClip WHERE ClipId = @ClipId;
    UPDATE hl.Clip SET Estado = 'DESCARTADO' WHERE ClipId = @ClipId;   -- se conserva para no volver a proponerlo
  COMMIT;
  SELECT Eliminado = CAST(1 AS bit);
END
GO

CREATE OR ALTER PROCEDURE api.usp_Clip_Interaccion @ClipId int, @Tipo varchar(12), @_UsuarioId int
AS
BEGIN
  SET NOCOUNT ON;
  IF @Tipo NOT IN ('VISTA','REPETICION','COMPARTIR') THROW 50400, N'Tipo de interacción inválido', 1;
  DECLARE @medio int = (SELECT MedioId FROM hl.Clip WHERE ClipId = @ClipId AND Estado = 'CONFIRMADO');
  IF @medio IS NULL THROW 50404, N'Jugada no encontrada', 1;
  -- anti-inflado: una vista por usuario y clip cada 30 minutos; máximo 5 repeticiones por hora
  IF @Tipo = 'VISTA' AND EXISTS (SELECT 1 FROM hl.Interaccion WHERE ClipId = @ClipId AND UsuarioId = @_UsuarioId AND Tipo = 'VISTA'
                                 AND CreadoEn > DATEADD(minute, -30, SYSUTCDATETIME())) RETURN;
  IF @Tipo = 'REPETICION' AND (SELECT COUNT(*) FROM hl.Interaccion WHERE ClipId = @ClipId AND UsuarioId = @_UsuarioId AND Tipo = 'REPETICION'
                                 AND CreadoEn > DATEADD(hour, -1, SYSUTCDATETIME())) >= 5 RETURN;
  INSERT hl.Interaccion(MedioId, ClipId, UsuarioId, Tipo) VALUES (@medio, @ClipId, @_UsuarioId, @Tipo);
END
GO

CREATE OR ALTER PROCEDURE api.usp_Clip_MeGusta @ClipId int, @_UsuarioId int
AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS (SELECT 1 FROM hl.Clip WHERE ClipId = @ClipId AND Estado = 'CONFIRMADO') THROW 50404, N'Jugada no encontrada', 1;
  DELETE hl.MeGusta WHERE ClipId = @ClipId AND UsuarioId = @_UsuarioId;
  IF @@ROWCOUNT = 0 INSERT hl.MeGusta(ClipId, UsuarioId) VALUES (@ClipId, @_UsuarioId);
  SELECT MeGusta = (SELECT COUNT(*) FROM hl.MeGusta WHERE ClipId = @ClipId),
         Mio = CAST(IIF(EXISTS (SELECT 1 FROM hl.MeGusta WHERE ClipId = @ClipId AND UsuarioId = @_UsuarioId), 1, 0) AS bit);
END
GO

/* Ranking de highlights. Modo GENERAL (galería) o RECLUTAMIENTO (lo que valora un visor). */
CREATE OR ALTER PROCEDURE api.usp_Highlight_Top
  @TemporadaId int = NULL, @JugadorId int = NULL, @TipoEventoId smallint = NULL, @Categoria varchar(12) = NULL,
  @PartidoId int = NULL, @Modo varchar(15) = 'GENERAL', @Top int = 30, @_UsuarioId int = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @Modo NOT IN ('GENERAL','RECLUTAMIENTO') THROW 50400, N'Modo inválido', 1;
  IF @Top NOT BETWEEN 1 AND 200 SET @Top = 30;
  SELECT TOP (@Top)
         Posicion = ROW_NUMBER() OVER (ORDER BY IIF(@Modo = 'GENERAL', v.PuntajeGeneral, v.PuntajeReclutamiento) DESC, v.ClipId),
         Puntaje = IIF(@Modo = 'GENERAL', v.PuntajeGeneral, v.PuntajeReclutamiento),
         v.ClipId, v.MedioId, v.JugadorId, v.Jugador, v.TipoEventoId, v.TipoEvento, v.Categoria,
         v.SegundoInicio, v.SegundoFin, v.SegundoEvento, v.Minuto, v.Resultado, v.Pie, v.Calidad, v.EsDecisiva, v.EsPieDebil,
         v.MarcaX, v.MarcaY, v.Nota, v.Rival, v.NivelRival, v.FechaPartido, v.Fase,
         v.Tecnico, v.Interaccion, v.Audio, v.Vistas, v.MeGusta,
         MiMeGusta = CAST(IIF(EXISTS (SELECT 1 FROM hl.MeGusta g WHERE g.ClipId = v.ClipId AND g.UsuarioId = @_UsuarioId), 1, 0) AS bit)
  FROM hl.vw_ClipPuntaje v
  JOIN med.Medio m ON m.MedioId = v.MedioId AND m.Estado = 'LISTO'
  WHERE (@TemporadaId IS NULL OR v.TemporadaId = @TemporadaId)
    AND (@JugadorId IS NULL OR v.JugadorId = @JugadorId)
    AND (@TipoEventoId IS NULL OR v.TipoEventoId = @TipoEventoId)
    AND (@Categoria IS NULL OR v.Categoria = @Categoria)
    AND (@PartidoId IS NULL OR v.PartidoId = @PartidoId)
  ORDER BY Puntaje DESC, v.ClipId;
END
GO

/* Candidatos automáticos: momentos sin jugada marcada que merecen revisión del editor. */
CREATE OR ALTER PROCEDURE hl.usp_Candidatos_Generar @MedioId int
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @pre int = cat.fn_Param('CAND_PRE_SEG'), @post int = cat.fn_Param('CAND_POST_SEG'),
          @minUsr int = cat.fn_Param('CAND_MIN_USUARIOS_REP'),
          @dur decimal(9,2) = (SELECT DuracionSeg FROM med.Medio WHERE MedioId = @MedioId);
  DECLARE @n int = 0;

  -- (a) picos de audio: la grada/banca reacciona justo después de la jugada
  INSERT hl.Clip(MedioId, SegundoEvento, SegundoInicio, SegundoFin, Origen, Estado, Nota)
  SELECT @MedioId, pa.Segundo, GREATEST(0, pa.Segundo - @pre), LEAST(ISNULL(@dur, pa.Segundo + @post), pa.Segundo + @post),
         'AUDIO', 'CANDIDATO', CONCAT(N'Pico de audio (', pa.Intensidad, N'σ sobre la media)')
  FROM med.PicoAudio pa
  WHERE pa.MedioId = @MedioId AND pa.Segundo >= 2
    AND NOT EXISTS (SELECT 1 FROM hl.Clip c WHERE c.MedioId = @MedioId
                    AND pa.Segundo BETWEEN c.SegundoInicio - 5 AND c.SegundoFin + 8);
  SET @n += @@ROWCOUNT;

  -- (b) tramos que varios usuarios regresaron a ver
  ;WITH tramos AS (
    SELECT Tramo = i.Segundo / 10, Usuarios = COUNT(DISTINCT i.UsuarioId)
    FROM hl.Interaccion i
    WHERE i.MedioId = @MedioId AND i.ClipId IS NULL AND i.Tipo = 'REPETICION' AND i.Segundo IS NOT NULL
    GROUP BY i.Segundo / 10 HAVING COUNT(DISTINCT i.UsuarioId) >= @minUsr)
  INSERT hl.Clip(MedioId, SegundoEvento, SegundoInicio, SegundoFin, Origen, Estado, Nota)
  SELECT @MedioId, t.Tramo * 10 + 5, GREATEST(0, t.Tramo * 10 - 3), LEAST(ISNULL(@dur, t.Tramo * 10 + 13), t.Tramo * 10 + 13),
         'REPETICION', 'CANDIDATO', CONCAT(t.Usuarios, N' usuarios repitieron este tramo')
  FROM tramos t
  WHERE NOT EXISTS (SELECT 1 FROM hl.Clip c WHERE c.MedioId = @MedioId
                    AND t.Tramo * 10 + 5 BETWEEN c.SegundoInicio - 5 AND c.SegundoFin + 5);
  SET @n += @@ROWCOUNT;
  RETURN @n;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Medio_Candidatos @MedioId int
AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS (SELECT 1 FROM med.Medio WHERE MedioId = @MedioId AND Tipo = 'VIDEO' AND Eliminado = 0) THROW 50404, N'Video no encontrado', 1;
  DECLARE @n int; EXEC @n = hl.usp_Candidatos_Generar @MedioId;
  SELECT Nuevos = @n;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Medio_Obtener @MedioId int, @_UsuarioId int = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS (SELECT 1 FROM med.Medio WHERE MedioId = @MedioId AND Eliminado = 0) THROW 50404, N'Medio no encontrado', 1;

  SELECT m.MedioId, m.Tipo, m.Titulo, m.Descripcion, m.TemporadaId, Temporada = t.Nombre, m.PartidoId, m.Estado, m.ErrorProceso,
         m.DuracionSeg, m.Ancho, m.Alto, m.SegundoInicioPartido, m.NombreOriginal, m.TamanoBytes, m.CreadoEn,
         SubidoPor = u.Nombre, TieneMiniatura = CAST(IIF(m.RutaMiniatura IS NULL, 0, 1) AS bit),
         Partido = IIF(p.PartidoId IS NULL, NULL, CONCAT(el.Nombre, ' ', p.GolesLocal, ' - ', p.GolesVisita, ' ', ev.Nombre)),
         FechaPartido = p.Fecha, p.NivelRival, Fase = f.Nombre
  FROM med.Medio m
  JOIN fut.Temporada t ON t.TemporadaId = m.TemporadaId
  JOIN seg.Usuario u ON u.UsuarioId = m.SubidoPor
  LEFT JOIN fut.Partido p ON p.PartidoId = m.PartidoId
  LEFT JOIN fut.Equipo el ON el.EquipoId = p.EquipoLocalId
  LEFT JOIN fut.Equipo ev ON ev.EquipoId = p.EquipoVisitaId
  LEFT JOIN cat.FasePartido f ON f.Clave = p.Fase
  WHERE m.MedioId = @MedioId;

  SELECT c.ClipId, c.Estado, c.Origen, c.JugadorId, Jugador = CONCAT(j.Nombre, ' ', j.Apellidos), c.TipoEventoId, TipoEvento = te.Nombre,
         te.Categoria, c.SegundoEvento, c.SegundoInicio, c.SegundoFin, c.Minuto, c.Resultado, c.Pie, c.Calidad, c.EsDecisiva,
         c.MarcaX, c.MarcaY, c.Nota, v.Tecnico, v.Interaccion, v.Audio, v.PuntajeGeneral, v.PuntajeReclutamiento,
         MeGusta = ISNULL(v.MeGusta, 0), Vistas = ISNULL(v.Vistas, 0),
         MiMeGusta = CAST(IIF(EXISTS (SELECT 1 FROM hl.MeGusta g WHERE g.ClipId = c.ClipId AND g.UsuarioId = @_UsuarioId), 1, 0) AS bit)
  FROM hl.Clip c
  LEFT JOIN fut.Jugador j ON j.JugadorId = c.JugadorId
  LEFT JOIN cat.TipoEvento te ON te.TipoEventoId = c.TipoEventoId
  LEFT JOIN hl.vw_ClipPuntaje v ON v.ClipId = c.ClipId
  WHERE c.MedioId = @MedioId AND c.Estado <> 'DESCARTADO'
  ORDER BY c.SegundoEvento;

  SELECT j.JugadorId, Nombre = CONCAT(j.Nombre, ' ', j.Apellidos), j.Dorsal
  FROM med.MedioJugador mj JOIN fut.Jugador j ON j.JugadorId = mj.JugadorId
  WHERE mj.MedioId = @MedioId ORDER BY j.Apellidos;
END
GO
