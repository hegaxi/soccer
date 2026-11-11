/* ============================================================
   07 · Reclutamiento: diagnóstico del material y reel del jugador
   ============================================================ */

/* ---------- menores: consentimiento del tutor ---------- */
-- Sin fecha de nacimiento se trata como menor: es el lado seguro del error.
CREATE OR ALTER FUNCTION fut.fn_EsMenor(@JugadorId int) RETURNS bit
AS BEGIN
  RETURN (SELECT CAST(IIF(FechaNacimiento IS NULL OR DATEADD(year, 18, FechaNacimiento) > CAST(SYSUTCDATETIME() AS date), 1, 0) AS bit)
          FROM fut.Jugador WHERE JugadorId = @JugadorId)
END
GO

/* ¿Se puede compartir fuera del club? @Alcance: 'REEL' (el video y el perfil) o 'CONTACTO' (contacto personal o del tutor).
   Un mayor de edad decide por sí mismo; un menor necesita consentimiento vigente y no revocado con ese alcance. */
CREATE OR ALTER FUNCTION fut.fn_Permiso(@JugadorId int, @Alcance varchar(10)) RETURNS bit
AS BEGIN
  IF fut.fn_EsMenor(@JugadorId) = 0 RETURN 1;
  RETURN CAST(IIF(EXISTS (
    SELECT 1 FROM fut.Consentimiento c
    WHERE c.JugadorId = @JugadorId AND c.RevocadoEn IS NULL
      AND (c.VigenteHasta IS NULL OR c.VigenteHasta >= CAST(SYSUTCDATETIME() AS date))
      AND ((@Alcance = 'REEL' AND c.PermiteReelPublico = 1) OR (@Alcance = 'CONTACTO' AND c.PermiteContacto = 1))), 1, 0) AS bit);
END
GO

CREATE OR ALTER PROCEDURE api.usp_Consentimiento_Guardar
  @JugadorId int, @TutorNombre nvarchar(120), @Parentesco nvarchar(40), @Fecha date, @VigenteHasta date = NULL,
  @PermiteReelPublico bit = 1, @PermiteContacto bit = 0, @Referencia nvarchar(200) = NULL, @_UsuarioId int
AS
BEGIN
  SET NOCOUNT ON;
  SET @TutorNombre = LTRIM(RTRIM(@TutorNombre)); SET @Parentesco = LTRIM(RTRIM(@Parentesco));
  IF NOT EXISTS (SELECT 1 FROM fut.Jugador WHERE JugadorId = @JugadorId) THROW 50404, N'Jugador no encontrado', 1;
  IF @TutorNombre = '' OR @Parentesco = '' THROW 50400, N'Indica el nombre del tutor y su parentesco', 1;
  IF @Fecha > CAST(SYSUTCDATETIME() AS date) THROW 50400, N'La fecha de firma no puede ser futura', 1;
  IF @VigenteHasta < @Fecha THROW 50400, N'La vigencia no puede terminar antes de la firma', 1;
  IF @PermiteReelPublico = 0 AND @PermiteContacto = 0 THROW 50400, N'El consentimiento debe autorizar al menos una cosa', 1;
  INSERT fut.Consentimiento(JugadorId, TutorNombre, Parentesco, Fecha, VigenteHasta, PermiteReelPublico, PermiteContacto, Referencia, RegistradoPor)
  VALUES (@JugadorId, @TutorNombre, @Parentesco, @Fecha, @VigenteHasta, @PermiteReelPublico, @PermiteContacto, NULLIF(LTRIM(RTRIM(@Referencia)), ''), @_UsuarioId);
  SELECT ConsentimientoId = CAST(SCOPE_IDENTITY() AS int);
END
GO

-- Revocar surte efecto de inmediato: los enlaces dejan de abrir porque el permiso se comprueba en cada visita.
CREATE OR ALTER PROCEDURE api.usp_Consentimiento_Revocar @ConsentimientoId int
AS
BEGIN
  SET NOCOUNT ON;
  UPDATE fut.Consentimiento SET RevocadoEn = SYSUTCDATETIME() WHERE ConsentimientoId = @ConsentimientoId AND RevocadoEn IS NULL;
  IF @@ROWCOUNT = 0 THROW 50404, N'Consentimiento no encontrado o ya revocado', 1;
  SELECT Revocado = CAST(1 AS bit);
END
GO

/* ---------- enlaces para visores ---------- */
-- Devuelve el reel que abre un token, o NULL: el enlace debe estar vigente, el reel renderizado y el permiso en pie.
CREATE OR ALTER FUNCTION hl.fn_EnlaceReel(@Token varchar(40)) RETURNS int
AS BEGIN
  RETURN (SELECT r.ReelId FROM hl.ReelEnlace e JOIN hl.Reel r ON r.ReelId = e.ReelId
          WHERE e.Token = @Token AND e.RevocadoEn IS NULL AND e.ExpiraEn > SYSUTCDATETIME()
            AND r.Estado = 'LISTO' AND fut.fn_Permiso(r.JugadorId, 'REEL') = 1)
END
GO

CREATE OR ALTER PROCEDURE api.usp_Reel_EnlaceCrear
  @ReelId int, @Destinatario nvarchar(120), @Dias int = NULL, @IncluyePartidos bit = 0, @_UsuarioId int
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @estado varchar(10), @jug int;
  SELECT @estado = Estado, @jug = JugadorId FROM hl.Reel WHERE ReelId = @ReelId;
  IF @estado IS NULL THROW 50404, N'Reel no encontrado', 1;
  SET @Destinatario = LTRIM(RTRIM(@Destinatario));
  IF @Destinatario = '' THROW 50400, N'Indica a quién le vas a dar el enlace (visor, club o universidad)', 1;
  IF @estado <> 'LISTO' THROW 50409, N'Renderiza el reel antes de compartirlo', 1;
  IF fut.fn_Permiso(@jug, 'REEL') = 0
    THROW 50409, N'El jugador es menor de edad (o no tiene fecha de nacimiento) y no hay consentimiento vigente del tutor para compartir su reel. Regístralo en su ficha.', 1;
  SET @Dias = ISNULL(@Dias, CAST(cat.fn_Param('ENLACE_DIAS') AS int));
  IF @Dias NOT BETWEEN 1 AND 180 THROW 50400, N'La vigencia del enlace va de 1 a 180 días', 1;
  DECLARE @token varchar(40) = LOWER(CONVERT(varchar(40), CRYPT_GEN_RANDOM(16), 2));
  INSERT hl.ReelEnlace(ReelId, Token, Destinatario, ExpiraEn, IncluyePartidos, CreadoPor)
  VALUES (@ReelId, @token, @Destinatario, DATEADD(day, @Dias, SYSUTCDATETIME()), @IncluyePartidos, @_UsuarioId);
  SELECT EnlaceId = CAST(SCOPE_IDENTITY() AS int), Token = @token;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Reel_EnlaceRevocar @EnlaceId int
AS
BEGIN
  SET NOCOUNT ON;
  UPDATE hl.ReelEnlace SET RevocadoEn = SYSUTCDATETIME() WHERE EnlaceId = @EnlaceId AND RevocadoEn IS NULL;
  IF @@ROWCOUNT = 0 THROW 50404, N'Enlace no encontrado o ya revocado', 1;
  SELECT Revocado = CAST(1 AS bit);
END
GO

/* Revisa el material de un jugador con ojos de visor y dice qué falta. */
CREATE OR ALTER FUNCTION hl.fn_Diagnostico(@JugadorId int, @TemporadaId int)
RETURNS @r TABLE (Orden int IDENTITY, Severidad varchar(5), Mensaje nvarchar(400))
AS
BEGIN
  DECLARE @pos tinyint, @posNombre nvarchar(60), @linea varchar(12), @est smallint, @nac date,
          @contactoClub bit, @foto int, @pie char(1);
  SELECT @pos = j.PosicionId, @posNombre = LOWER(p.Nombre), @linea = p.Linea, @est = j.EstaturaCm, @nac = j.FechaNacimiento,
         @contactoClub = CAST(IIF(e.ContactoCorreo IS NOT NULL OR e.ContactoTelefono IS NOT NULL, 1, 0) AS bit),
         @foto = j.FotoMedioId, @pie = j.PieDominante
  FROM fut.Jugador j JOIN cat.Posicion p ON p.PosicionId = j.PosicionId
  LEFT JOIN fut.Equipo e ON e.EquipoId = j.EquipoId WHERE j.JugadorId = @JugadorId;
  IF @pos IS NULL RETURN;

  DECLARE @n int, @partidos int, @altos int, @debil int, @sinMarca int, @sinCalif int, @defensa int, @fallidas int;
  SELECT @n = COUNT(*), @partidos = COUNT(DISTINCT v.PartidoId), @altos = SUM(IIF(v.NivelRival >= 4, 1, 0)),
         @debil = SUM(IIF(v.EsPieDebil = 1, 1, 0)), @sinMarca = SUM(IIF(v.MarcaX IS NULL, 1, 0)),
         @sinCalif = SUM(IIF(v.Calidad IS NULL, 1, 0)), @defensa = SUM(IIF(v.Categoria = 'DEFENSA', 1, 0)),
         @fallidas = SUM(IIF(v.Resultado = 'F', 1, 0))
  FROM hl.vw_ClipPuntaje v
  WHERE v.JugadorId = @JugadorId AND (@TemporadaId IS NULL OR v.TemporadaId = @TemporadaId);

  DECLARE @minRec int = cat.fn_Param('REEL_MIN_CLIPS_RECOM');

  IF @n = 0
    INSERT @r VALUES ('ALTA', N'Aún no hay jugadas confirmadas de este jugador. Marca sus jugadas en los videos de partido para poder armar el reel.');
  ELSE
  BEGIN
    IF @n < @minRec
      INSERT @r VALUES ('ALTA', CONCAT(N'Solo hay ', @n, N' jugadas. Un reel creíble muestra entre ', @minRec,
                        N' y 25: con menos, el visor no puede juzgar consistencia.'));

    -- jugadas clave de la posición sin evidencia (las 4 más importantes)
    INSERT @r (Severidad, Mensaje)
    SELECT TOP 4 'MEDIA', CONCAT(N'Falta evidencia de «', te.Nombre, N'», de lo primero que se evalúa en un ', @posNombre, N'.')
    FROM cat.PesoPosicionEvento ppe JOIN cat.TipoEvento te ON te.TipoEventoId = ppe.TipoEventoId
    WHERE ppe.PosicionId = @pos AND ppe.EsClave = 1
      AND NOT EXISTS (SELECT 1 FROM hl.vw_ClipPuntaje v WHERE v.JugadorId = @JugadorId AND v.TipoEventoId = ppe.TipoEventoId
                      AND v.Resultado = 'E' AND (@TemporadaId IS NULL OR v.TemporadaId = @TemporadaId))
    ORDER BY ppe.Multiplicador DESC, te.PesoBase DESC;

    IF @linea <> 'PORTERIA' AND @pie <> 'A' AND @debil = 0
      INSERT @r VALUES ('MEDIA', N'Ninguna jugada con el pie no dominante. Es de lo que más buscan los visores para descartar jugadores de un solo perfil.');
    IF @partidos <= 1 AND @n >= 4
      INSERT @r VALUES ('MEDIA', N'Todas las jugadas salen de un solo partido. Muestra consistencia con jugadas de al menos 3 partidos.');
    IF ISNULL(@altos, 0) = 0
      INSERT @r VALUES ('MEDIA', N'Ninguna jugada ante rivales de nivel alto (4-5). Lo hecho contra rivales débiles pesa poco en una evaluación.');
    IF @linea IN ('MEDIO','ATAQUE') AND @defensa = 0
      INSERT @r VALUES ('MEDIA', N'No hay trabajo sin balón (presión, recuperación). También se evalúa en mediocampistas y atacantes.');
    IF @sinMarca > 0
      INSERT @r VALUES ('MEDIA', CONCAT(@sinMarca, N' jugada(s) sin marca de identificación. Si el visor no sabe a quién mirar en los primeros segundos, pasa al siguiente video.'));
    IF @fallidas * 4 > @n
      INSERT @r VALUES ('INFO', CONCAT(@fallidas, N' de ', @n, N' jugadas están marcadas como fallidas; el reel las deja fuera salvo que la ejecución sea sobresaliente.'));
    IF @sinCalif > 0
      INSERT @r VALUES ('INFO', CONCAT(@sinCalif, N' jugada(s) sin valoración técnica; se toman como 3 de 5 y pueden estar mal ordenadas.'));
  END

  IF fut.fn_Permiso(@JugadorId, 'REEL') = 0
    INSERT @r VALUES ('ALTA', IIF(@nac IS NULL,
      N'Falta la fecha de nacimiento: sin ella se le trata como menor y su reel no se puede compartir sin consentimiento del tutor.',
      N'Es menor de edad y no hay consentimiento vigente del tutor: su reel no se puede compartir fuera del club.'));
  IF @contactoClub = 0
    INSERT @r VALUES ('ALTA', N'Su equipo no tiene contacto para visores (coordinador o entrenador). Regístralo en Administración → Equipos: es el contacto que verán, no el del jugador.');
  DECLARE @faltan nvarchar(200) = CONCAT_WS(N', ', IIF(@est IS NULL, N'estatura', NULL), IIF(@nac IS NULL, N'fecha de nacimiento', NULL),
                                            IIF(@foto IS NULL, N'foto de perfil', NULL));
  IF @faltan <> ''
    INSERT @r VALUES ('INFO', CONCAT(N'Completa el perfil (', @faltan, N'): son los datos de la tarjeta inicial del reel.'));
  IF NOT EXISTS (SELECT 1 FROM @r)
    INSERT @r VALUES ('OK', N'El material cubre lo que se evalúa en la posición. Listo para generar y compartir el reel.');
  RETURN;
END
GO

/* Arma un reel de un jugador. Dos modos:
   MEJORES — highlights de reclutamiento:
     (1) solo jugadas donde luce — las fallidas entran solo con ejecución de 4-5★;
     (2) selección voraz por PuntajeReclutamiento con rendimientos decrecientes por tipo de jugada y por partido,
         para mostrar un perfil completo y consistente en vez de diez goles iguales;
     (3) lo mejor al principio (el visor decide en los primeros 30 s) y una jugada fuerte reservada para el cierre.
     La duración objetivo incluye la tarjeta inicial y los cuadros congelados.
   PARTIDO — todas sus acciones marcadas en un partido, en orden cronológico e incluidas las fallidas:
     es el contexto honesto que un visor pide después de ver los highlights. */
CREATE OR ALTER PROCEDURE api.usp_Reel_Generar
  @JugadorId int, @TemporadaId int = NULL, @DuracionObjetivoSeg int = 240, @Titulo nvarchar(200) = NULL,
  @Modo varchar(10) = 'MEJORES', @PartidoId int = NULL, @_UsuarioId int
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  DECLARE @nombre nvarchar(200), @posicion nvarchar(60);
  SELECT @nombre = CONCAT(j.Nombre, ' ', j.Apellidos), @posicion = p.Nombre
  FROM fut.Jugador j JOIN cat.Posicion p ON p.PosicionId = j.PosicionId WHERE j.JugadorId = @JugadorId;
  IF @nombre IS NULL THROW 50404, N'Jugador no encontrado', 1;
  IF @Modo NOT IN ('MEJORES','PARTIDO') THROW 50400, N'Modo de reel inválido', 1;
  IF @Modo = 'MEJORES' SET @PartidoId = NULL;
  IF @Modo = 'PARTIDO' AND NOT EXISTS (SELECT 1 FROM fut.Partido WHERE PartidoId = @PartidoId) THROW 50400, N'Elige el partido', 1;
  IF @DuracionObjetivoSeg NOT BETWEEN 30 AND 600 THROW 50400, N'La duración objetivo va de 30 segundos a 10 minutos', 1;

  DECLARE @maxClips int = cat.fn_Param('REEL_MAX_CLIPS'), @penTipo float = cat.fn_Param('REEL_PENAL_MISMO_TIPO'),
          @penPartido float = cat.fn_Param('REEL_PENAL_MISMO_PARTIDO'), @apertura int = cat.fn_Param('REEL_APERTURA'),
          @tarjeta float = cat.fn_Param('REEL_TARJETA_SEG'), @congelado float = cat.fn_Param('REEL_CONGELADO_SEG');

  SELECT v.ClipId, v.MedioId, v.TipoEventoId, v.PartidoId, v.SegundoEvento, v.Resultado,
         Dur = CAST(v.DuracionSeg AS float) + IIF(v.MarcaX IS NULL, 0, @congelado),   -- lo que ocupa en el video final
         Puntaje = CAST(v.PuntajeReclutamiento AS float),
         v.TipoEvento, v.Rival, v.NivelRival, v.EsDecisiva, v.EsPieDebil, v.Calidad, v.Minuto, v.FechaPartido,
         Pick = CAST(NULL AS int)
  INTO #c
  FROM hl.vw_ClipPuntaje v
  JOIN med.Medio m ON m.MedioId = v.MedioId AND m.Estado = 'LISTO'
  WHERE v.JugadorId = @JugadorId
    AND ((@Modo = 'MEJORES' AND (@TemporadaId IS NULL OR v.TemporadaId = @TemporadaId) AND (v.Resultado = 'E' OR v.Calidad >= 4))
      OR (@Modo = 'PARTIDO' AND v.PartidoId = @PartidoId));

  IF NOT EXISTS (SELECT 1 FROM #c)
  BEGIN
    DECLARE @sin nvarchar(200) = IIF(@Modo = 'PARTIDO', N'El jugador no tiene jugadas marcadas en ese partido',
                                     N'El jugador no tiene jugadas confirmadas en videos listos para armar un reel');
    THROW 50409, @sin, 1;
  END

  DECLARE @n int = 0, @rival nvarchar(100), @fechaP date;
  IF @Modo = 'PARTIDO'
  BEGIN
    -- orden del partido: por video (primer tiempo, segundo tiempo) y momento; tope de 60 para que el render sea manejable
    ;WITH o AS (SELECT Pick, n = ROW_NUMBER() OVER (ORDER BY MedioId, SegundoEvento) FROM #c)
    UPDATE o SET Pick = IIF(n <= 60, n, NULL);
    SELECT @n = COUNT(*), @rival = MAX(Rival), @fechaP = MAX(FechaPartido) FROM #c WHERE Pick IS NOT NULL;
    SET @TemporadaId = (SELECT TemporadaId FROM fut.Partido WHERE PartidoId = @PartidoId);
  END
  ELSE
  BEGIN
    -- el nivel actual importa: lo de hace más de 4 meses (respecto a su última jugada) pesa un poco menos
    DECLARE @ultima date = (SELECT MAX(FechaPartido) FROM #c);
    UPDATE #c SET Puntaje = Puntaje * 0.93 WHERE FechaPartido IS NOT NULL AND DATEDIFF(day, FechaPartido, @ultima) > 120;

    DECLARE @restante float = @DuracionObjetivoSeg - @tarjeta, @id int, @dur float;
    WHILE @n < @maxClips AND @restante > 0
    BEGIN
      SET @id = NULL;
      SELECT TOP 1 @id = c.ClipId, @dur = c.Dur
      FROM #c c
      WHERE c.Pick IS NULL AND c.Dur <= @restante + 6
      ORDER BY c.Puntaje
               * POWER(@penTipo,    (SELECT COUNT(*) FROM #c x WHERE x.Pick IS NOT NULL AND x.TipoEventoId = c.TipoEventoId))
               * POWER(@penPartido, (SELECT COUNT(*) FROM #c x WHERE x.Pick IS NOT NULL AND x.PartidoId = c.PartidoId)) DESC,
               c.ClipId;
      IF @id IS NULL BREAK;
      SET @n += 1; SET @restante -= @dur;
      UPDATE #c SET Pick = @n WHERE ClipId = @id;
    END

    -- cierre fuerte: la primera jugada elegida después de la apertura se reserva para el final
    IF @n >= @apertura + 3 UPDATE #c SET Pick = @n + 1 WHERE Pick = @apertura + 1;
  END

  DECLARE @temp nvarchar(60) = (SELECT Nombre FROM fut.Temporada WHERE TemporadaId = @TemporadaId);
  SET @Titulo = ISNULL(NULLIF(LTRIM(RTRIM(@Titulo)), ''),
       IIF(@Modo = 'PARTIDO', CONCAT_WS(N' · ', @nombre, N'Todas sus acciones vs ' + @rival, CONVERT(nvarchar(10), @fechaP, 103)),
                              CONCAT_WS(N' · ', @nombre, @posicion, ISNULL(@temp, N'Trayectoria'))));

  BEGIN TRAN;
    INSERT hl.Reel(JugadorId, TemporadaId, Titulo, DuracionObjetivoSeg, Modo, PartidoId, CreadoPor)
    VALUES (@JugadorId, @TemporadaId, @Titulo, @DuracionObjetivoSeg, @Modo, @PartidoId, @_UsuarioId);
    DECLARE @reel int = SCOPE_IDENTITY();
    INSERT hl.ReelClip(ReelId, Orden, ClipId, Motivo)
    SELECT @reel, ROW_NUMBER() OVER (ORDER BY c.Pick), c.ClipId,
           IIF(@Modo = 'PARTIDO',
             CONCAT_WS(N' · ', N'min ' + CAST(c.Minuto AS nvarchar(3)), IIF(c.Resultado = 'F', N'fallida', NULL), IIF(c.EsDecisiva = 1, N'jugada decisiva', NULL)),
             CONCAT_WS(N' · ',
               CASE WHEN c.Pick <= @apertura THEN N'Apertura' WHEN c.Pick = @n + 1 THEN N'Cierre' END,
               N'vs ' + c.Rival + IIF(c.NivelRival >= 4, N' (rival de nivel alto)', N''),
               IIF(c.EsDecisiva = 1, N'jugada decisiva', NULL),
               IIF(c.EsPieDebil = 1, N'pie no dominante', NULL),
               IIF(c.Calidad = 5, N'ejecución 5/5', NULL),
               IIF(c.Minuto >= 75, N'tramo final', NULL)))
    FROM #c c WHERE c.Pick IS NOT NULL;
  COMMIT;
  SELECT ReelId = @reel, Clips = @n;
END
GO

CREATE OR ALTER PROCEDURE hl.usp_Reel_Datos @ReelId int, @Publico bit, @ExpiraEn datetime2(0) = NULL, @IncluyePartidos bit = 0
AS
BEGIN
  SET NOCOUNT ON;
  IF @Publico = 1
    -- Lo que recibe un visor sin cuenta: solo año de nacimiento y, por defecto, el contacto del club.
    -- El contacto personal o del tutor aparece únicamente si es mayor de edad o el tutor lo autorizó.
    SELECT r.ReelId, r.Titulo, r.DuracionSeg, r.Modo, ExpiraEn = @ExpiraEn, IncluyePartidos = @IncluyePartidos,
           TarjetaSeg = cat.fn_Param('REEL_TARJETA_SEG'), CongeladoSeg = cat.fn_Param('REEL_CONGELADO_SEG'),
           Jugador = CONCAT(j.Nombre, ' ', j.Apellidos), j.Dorsal, Posicion = p.Nombre, PosicionSecundaria = p2.Nombre,
           j.PieDominante, j.EstaturaCm, j.PesoKg, AnioNacimiento = YEAR(j.FechaNacimiento), j.AnioGraduacion, j.PromedioAcademico,
           Equipo = e.Nombre, j.Bio, j.FotoMedioId,
           e.ContactoNombre, e.ContactoCargo, e.ContactoCorreo, e.ContactoTelefono,
           CorreoPersonal   = IIF(pc.Permite = 1, j.CorreoContacto, NULL),
           TelefonoPersonal = IIF(pc.Permite = 1, j.TelefonoContacto, NULL)
    FROM hl.Reel r
    JOIN fut.Jugador j ON j.JugadorId = r.JugadorId
    JOIN cat.Posicion p ON p.PosicionId = j.PosicionId
    LEFT JOIN cat.Posicion p2 ON p2.PosicionId = j.PosicionSecundariaId
    LEFT JOIN fut.Equipo e ON e.EquipoId = j.EquipoId
    CROSS APPLY (SELECT Permite = fut.fn_Permiso(j.JugadorId, 'CONTACTO')) pc
    WHERE r.ReelId = @ReelId;
  ELSE
    SELECT r.ReelId, r.Titulo, r.Estado, r.DuracionSeg, r.DuracionObjetivoSeg, r.ErrorProceso, r.CreadoEn, r.TemporadaId, r.Modo,
           TarjetaSeg = cat.fn_Param('REEL_TARJETA_SEG'), CongeladoSeg = cat.fn_Param('REEL_CONGELADO_SEG'),
           j.JugadorId, Jugador = CONCAT(j.Nombre, ' ', j.Apellidos), j.Dorsal, Posicion = p.Nombre, PosicionSecundaria = p2.Nombre,
           Equipo = e.Nombre, EsMenor = fut.fn_EsMenor(j.JugadorId), PuedeCompartir = fut.fn_Permiso(j.JugadorId, 'REEL'),
           DuracionEstimada = (SELECT SUM(c.SegundoFin - c.SegundoInicio) FROM hl.ReelClip rc JOIN hl.Clip c ON c.ClipId = rc.ClipId WHERE rc.ReelId = r.ReelId)
    FROM hl.Reel r
    JOIN fut.Jugador j ON j.JugadorId = r.JugadorId
    JOIN cat.Posicion p ON p.PosicionId = j.PosicionId
    LEFT JOIN cat.Posicion p2 ON p2.PosicionId = j.PosicionSecundariaId
    LEFT JOIN fut.Equipo e ON e.EquipoId = j.EquipoId
    WHERE r.ReelId = @ReelId;

  -- los videos fuente solo se identifican si el enlace incluye los partidos completos
  SELECT rc.Orden, rc.ClipId, MedioId = IIF(@Publico = 1 AND @IncluyePartidos = 0, NULL, v.MedioId), v.TipoEvento, v.Categoria,
         v.SegundoInicio, v.SegundoFin, v.DuracionSeg, v.Minuto, v.Rival, v.NivelRival, v.FechaPartido, v.ColorUniforme, v.Resultado,
         v.MarcaX, v.MarcaY, v.MarcaTamano, v.MarcaSegundo, v.Calidad, v.EsDecisiva, v.EsPieDebil, rc.Motivo, Puntaje = v.PuntajeReclutamiento
  FROM hl.ReelClip rc JOIN hl.vw_ClipPuntaje v ON v.ClipId = rc.ClipId
  WHERE rc.ReelId = @ReelId ORDER BY rc.Orden;

  IF @Publico = 1
  BEGIN
    -- partidos completos de donde salen las jugadas: el visor los pide para ver lo que no entra en un highlight
    IF @IncluyePartidos = 1
      SELECT DISTINCT m.MedioId, m.Titulo, m.DuracionSeg, FechaPartido = p.Fecha, p.ColorUniforme, p.Competencia,
             Partido = IIF(p.PartidoId IS NULL, NULL, CONCAT(el.Nombre, ' ', p.GolesLocal, ' - ', p.GolesVisita, ' ', ev.Nombre))
      FROM hl.ReelClip rc JOIN hl.Clip c ON c.ClipId = rc.ClipId
      JOIN med.Medio m ON m.MedioId = c.MedioId AND m.Eliminado = 0 AND m.Estado = 'LISTO'
      LEFT JOIN fut.Partido p ON p.PartidoId = m.PartidoId
      LEFT JOIN fut.Equipo el ON el.EquipoId = p.EquipoLocalId
      LEFT JOIN fut.Equipo ev ON ev.EquipoId = p.EquipoVisitaId
      WHERE rc.ReelId = @ReelId ORDER BY FechaPartido, m.MedioId;
    RETURN;
  END

  -- observaciones sobre el montaje + diagnóstico del material del jugador
  DECLARE @jug int, @temp int, @durTotal decimal(9,2), @primero int, @mejorNoIncluida nvarchar(200), @modo varchar(10);
  SELECT @jug = JugadorId, @temp = TemporadaId, @modo = Modo FROM hl.Reel WHERE ReelId = @ReelId;
  SELECT @durTotal = SUM(c.SegundoFin - c.SegundoInicio) FROM hl.ReelClip rc JOIN hl.Clip c ON c.ClipId = rc.ClipId WHERE rc.ReelId = @ReelId;
  SELECT @primero = ClipId FROM hl.ReelClip WHERE ReelId = @ReelId AND Orden = 1;

  DECLARE @o TABLE (Orden int IDENTITY, Severidad varchar(5), Mensaje nvarchar(400));
  IF @modo = 'PARTIDO'
    INSERT @o VALUES ('INFO', N'Reel de partido: muestra todas las acciones marcadas, en orden y con las fallidas. Vale tanto como completo sea el marcado de ese partido.');
  IF @modo = 'MEJORES' AND @durTotal > 330
    INSERT @o VALUES ('MEDIA', CONCAT(N'El reel dura ', CAST(@durTotal / 60 AS decimal(4,1)), N' min. Pocos visores pasan del minuto 4: recorta a tus mejores jugadas.'));
  IF @durTotal < 60
    INSERT @o VALUES ('MEDIA', N'El reel dura menos de un minuto; es poco para evaluar a un jugador.');
  IF @modo = 'MEJORES' AND @primero IS NOT NULL AND @primero NOT IN (
       SELECT TOP 3 rc.ClipId FROM hl.ReelClip rc JOIN hl.vw_ClipPuntaje v ON v.ClipId = rc.ClipId
       WHERE rc.ReelId = @ReelId ORDER BY v.PuntajeReclutamiento DESC)
    INSERT @o VALUES ('MEDIA', N'El reel no abre con una de sus tres mejores jugadas. La decisión de seguir viendo se toma en los primeros 30 segundos.');
  SELECT TOP 1 @mejorNoIncluida = CONCAT(v.TipoEvento, N' vs ', ISNULL(v.Rival, N'—'), N' (', v.PuntajeReclutamiento, N' pts)')
  FROM hl.vw_ClipPuntaje v JOIN med.Medio m ON m.MedioId = v.MedioId AND m.Estado = 'LISTO'
  WHERE v.JugadorId = @jug AND (@temp IS NULL OR v.TemporadaId = @temp) AND v.Resultado = 'E'
    AND NOT EXISTS (SELECT 1 FROM hl.ReelClip rc WHERE rc.ReelId = @ReelId AND rc.ClipId = v.ClipId)
    AND v.PuntajeReclutamiento > (SELECT MIN(v2.PuntajeReclutamiento) FROM hl.ReelClip rc JOIN hl.vw_ClipPuntaje v2 ON v2.ClipId = rc.ClipId WHERE rc.ReelId = @ReelId) + 10
  ORDER BY v.PuntajeReclutamiento DESC;
  IF @modo = 'MEJORES' AND @mejorNoIncluida IS NOT NULL
    INSERT @o VALUES ('INFO', CONCAT(N'Hay una jugada fuera del reel con mejor puntaje que la más débil incluida: ', @mejorNoIncluida,
                      N'. Puede haberse omitido por variedad; valora cambiarla.'));

  SELECT Severidad, Mensaje FROM (
    SELECT Bloque = 1, Orden, Severidad, Mensaje FROM @o
    UNION ALL
    SELECT 2, Orden, Severidad, Mensaje FROM hl.fn_Diagnostico(@jug, @temp)) d
  ORDER BY Bloque, Orden;

  -- enlaces entregados: a quién, hasta cuándo y cuántas veces se abrió
  SELECT e.EnlaceId, e.Token, e.Destinatario, e.IncluyePartidos, e.ExpiraEn, e.RevocadoEn, e.Vistas, e.UltimaVistaEn, e.CreadoEn,
         Estado = CASE WHEN e.RevocadoEn IS NOT NULL THEN 'REVOCADO' WHEN e.ExpiraEn <= SYSUTCDATETIME() THEN 'VENCIDO' ELSE 'VIGENTE' END
  FROM hl.ReelEnlace e WHERE e.ReelId = @ReelId ORDER BY e.CreadoEn DESC, e.EnlaceId DESC;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Reel_Obtener @ReelId int
AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS (SELECT 1 FROM hl.Reel WHERE ReelId = @ReelId) THROW 50404, N'Reel no encontrado', 1;
  EXEC hl.usp_Reel_Datos @ReelId, 0;
END
GO

/* Lo que ve un visor con su enlace: sin sesión. Cada apertura queda contada en el enlace. */
CREATE OR ALTER PROCEDURE api.usp_Reel_Publico @Token varchar(40)
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @id int = hl.fn_EnlaceReel(@Token), @expira datetime2(0);
  IF @id IS NULL THROW 50404, N'Este enlace no existe, venció o fue retirado. Pide uno nuevo al club.', 1;
  DECLARE @partidos bit;
  UPDATE hl.ReelEnlace SET Vistas += 1, UltimaVistaEn = SYSUTCDATETIME(), @expira = ExpiraEn, @partidos = IncluyePartidos WHERE Token = @Token;
  EXEC hl.usp_Reel_Datos @id, 1, @expira, @partidos;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Reel_Listar @JugadorId int = NULL
AS
BEGIN
  SET NOCOUNT ON;
  SELECT r.ReelId, r.Titulo, r.Estado, r.Modo, r.DuracionSeg, r.CreadoEn, r.JugadorId, Jugador = CONCAT(j.Nombre, ' ', j.Apellidos),
         Posicion = p.Nombre, Publicado = CAST(IIF(EXISTS (SELECT 1 FROM hl.ReelEnlace e WHERE e.ReelId = r.ReelId AND e.RevocadoEn IS NULL AND e.ExpiraEn > SYSUTCDATETIME()), 1, 0) AS bit),
         Clips = (SELECT COUNT(*) FROM hl.ReelClip rc WHERE rc.ReelId = r.ReelId)
  FROM hl.Reel r JOIN fut.Jugador j ON j.JugadorId = r.JugadorId JOIN cat.Posicion p ON p.PosicionId = j.PosicionId
  WHERE @JugadorId IS NULL OR r.JugadorId = @JugadorId
  ORDER BY r.CreadoEn DESC, r.ReelId DESC;
END
GO

/* Reemplaza la lista de jugadas del reel (reordenar, quitar o agregar a mano). */
CREATE OR ALTER PROCEDURE api.usp_Reel_Ordenar @ReelId int, @ClipsJson nvarchar(max), @Titulo nvarchar(200) = NULL
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  DECLARE @jug int, @estado varchar(10);
  SELECT @jug = JugadorId, @estado = Estado FROM hl.Reel WHERE ReelId = @ReelId;
  IF @jug IS NULL THROW 50404, N'Reel no encontrado', 1;
  IF @estado = 'EN_COLA' THROW 50409, N'El reel se está renderizando; espera a que termine', 1;
  IF ISJSON(@ClipsJson) = 0 THROW 50400, N'Lista de jugadas inválida', 1;

  DECLARE @t TABLE (Orden int PRIMARY KEY, ClipId int);
  INSERT @t SELECT CAST([key] AS int) + 1, TRY_CAST(value AS int) FROM OPENJSON(@ClipsJson);
  IF EXISTS (SELECT 1 FROM @t WHERE ClipId IS NULL) OR (SELECT COUNT(DISTINCT ClipId) FROM @t) <> (SELECT COUNT(*) FROM @t)
    THROW 50400, N'La lista tiene jugadas repetidas o inválidas', 1;
  IF EXISTS (SELECT 1 FROM @t t WHERE NOT EXISTS (SELECT 1 FROM hl.vw_ClipPuntaje v WHERE v.ClipId = t.ClipId AND v.JugadorId = @jug))
    THROW 50400, N'Todas las jugadas deben estar confirmadas y ser del jugador del reel', 1;
  IF (SELECT COUNT(*) FROM @t) > 60 THROW 50400, N'Un reel admite como máximo 60 jugadas', 1;

  SELECT ClipId, Motivo INTO #m FROM hl.ReelClip WHERE ReelId = @ReelId;
  BEGIN TRAN;
    DELETE hl.ReelClip WHERE ReelId = @ReelId;
    INSERT hl.ReelClip(ReelId, Orden, ClipId, Motivo)
    SELECT @ReelId, t.Orden, t.ClipId, ISNULL(m.Motivo, N'Agregada a mano')
    FROM @t t LEFT JOIN #m m ON m.ClipId = t.ClipId;
    UPDATE hl.Reel SET Estado = 'BORRADOR', Titulo = ISNULL(NULLIF(LTRIM(RTRIM(@Titulo)), ''), Titulo) WHERE ReelId = @ReelId;
  COMMIT;
  SELECT ReelId = @ReelId;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Reel_Renderizar @ReelId int
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  DECLARE @estado varchar(10) = (SELECT Estado FROM hl.Reel WHERE ReelId = @ReelId);
  IF @estado IS NULL THROW 50404, N'Reel no encontrado', 1;
  IF @estado = 'EN_COLA' THROW 50409, N'El reel ya está en cola de renderizado', 1;
  IF NOT EXISTS (SELECT 1 FROM hl.ReelClip WHERE ReelId = @ReelId) THROW 50409, N'El reel no tiene jugadas', 1;
  IF EXISTS (SELECT 1 FROM hl.ReelClip rc JOIN hl.Clip c ON c.ClipId = rc.ClipId JOIN med.Medio m ON m.MedioId = c.MedioId
             WHERE rc.ReelId = @ReelId AND (m.Estado <> 'LISTO' OR m.Eliminado = 1 OR c.Estado <> 'CONFIRMADO'))
    THROW 50409, N'Alguna jugada del reel ya no está disponible; quítala o regenera el reel', 1;
  BEGIN TRAN;
    UPDATE hl.Reel SET Estado = 'EN_COLA', ErrorProceso = NULL WHERE ReelId = @ReelId;
    INSERT med.Trabajo(Tipo, ReelId) VALUES ('RENDER_REEL', @ReelId);
  COMMIT;
  SELECT ReelId = @ReelId, Estado = 'EN_COLA';
END
GO

CREATE OR ALTER PROCEDURE api.usp_Reel_Eliminar @ReelId int
AS
BEGIN
  SET NOCOUNT ON;
  DELETE hl.Reel WHERE ReelId = @ReelId;
  IF @@ROWCOUNT = 0 THROW 50404, N'Reel no encontrado', 1;
  SELECT Eliminado = CAST(1 AS bit);
END
GO

/* Ficha del jugador: perfil, cobertura por tipo de jugada, mejores jugadas, diagnóstico, fotos y reels. */
CREATE OR ALTER PROCEDURE api.usp_Jugador_Obtener @JugadorId int, @TemporadaId int = NULL
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @pos tinyint = (SELECT PosicionId FROM fut.Jugador WHERE JugadorId = @JugadorId);
  IF @pos IS NULL THROW 50404, N'Jugador no encontrado', 1;

  SELECT j.JugadorId, j.Nombre, j.Apellidos, j.FechaNacimiento, j.PosicionId, Posicion = p.Nombre, j.PosicionSecundariaId,
         PosicionSecundaria = p2.Nombre, j.PieDominante, j.EstaturaCm, j.PesoKg, j.Dorsal, j.EquipoId, Equipo = e.Nombre,
         j.AnioGraduacion, j.PromedioAcademico, j.CorreoContacto, j.TelefonoContacto, j.Bio, j.FotoMedioId, j.Activo,
         EsMenor = fut.fn_EsMenor(j.JugadorId), PuedeCompartir = fut.fn_Permiso(j.JugadorId, 'REEL'),
         ContactoClub = CONCAT_WS(N' · ', e.ContactoNombre, e.ContactoCargo, e.ContactoCorreo, e.ContactoTelefono)
  FROM fut.Jugador j JOIN cat.Posicion p ON p.PosicionId = j.PosicionId
  LEFT JOIN cat.Posicion p2 ON p2.PosicionId = j.PosicionSecundariaId
  LEFT JOIN fut.Equipo e ON e.EquipoId = j.EquipoId
  WHERE j.JugadorId = @JugadorId;

  -- cobertura: lo que tiene y lo que la posición exige
  SELECT te.TipoEventoId, te.Nombre, te.Categoria, Multiplicador = ISNULL(ppe.Multiplicador, 1.00),
         EsClave = ISNULL(ppe.EsClave, CAST(0 AS bit)),
         Jugadas = COUNT(v.ClipId), MejorPuntaje = MAX(v.PuntajeReclutamiento), Promedio = CAST(AVG(v.PuntajeReclutamiento) AS decimal(6,2))
  FROM cat.TipoEvento te
  LEFT JOIN cat.PesoPosicionEvento ppe ON ppe.TipoEventoId = te.TipoEventoId AND ppe.PosicionId = @pos
  LEFT JOIN hl.vw_ClipPuntaje v ON v.TipoEventoId = te.TipoEventoId AND v.JugadorId = @JugadorId
        AND (@TemporadaId IS NULL OR v.TemporadaId = @TemporadaId)
  GROUP BY te.TipoEventoId, te.Nombre, te.Categoria, ppe.Multiplicador, ppe.EsClave
  HAVING COUNT(v.ClipId) > 0 OR ISNULL(ppe.EsClave, 0) = 1
  ORDER BY ISNULL(ppe.Multiplicador, 1) DESC, COUNT(v.ClipId) DESC;

  SELECT TOP 30 v.ClipId, v.MedioId, v.PartidoId, v.TipoEvento, v.Categoria, v.SegundoInicio, v.SegundoFin, v.SegundoEvento, v.Minuto, v.Rival,
         v.NivelRival, v.FechaPartido, v.Calidad, v.EsDecisiva, v.EsPieDebil, v.Resultado, v.MarcaX, v.MarcaY, v.MarcaTamano, v.MarcaSegundo,
         v.Tecnico, v.Interaccion, v.Audio, Puntaje = v.PuntajeReclutamiento, v.MeGusta, v.Vistas,
         MedioListo = CAST(IIF(m.Estado = 'LISTO', 1, 0) AS bit)
  FROM hl.vw_ClipPuntaje v JOIN med.Medio m ON m.MedioId = v.MedioId
  WHERE v.JugadorId = @JugadorId AND (@TemporadaId IS NULL OR v.TemporadaId = @TemporadaId)
  ORDER BY v.PuntajeReclutamiento DESC;

  SELECT Severidad, Mensaje FROM hl.fn_Diagnostico(@JugadorId, @TemporadaId) ORDER BY Orden;

  SELECT m.MedioId, m.Titulo, m.CreadoEn, m.Ancho, m.Alto
  FROM med.MedioJugador mj JOIN med.Medio m ON m.MedioId = mj.MedioId
  WHERE mj.JugadorId = @JugadorId AND m.Tipo = 'FOTO' AND m.Eliminado = 0 AND m.Estado = 'LISTO'
    AND (@TemporadaId IS NULL OR m.TemporadaId = @TemporadaId)
  ORDER BY m.CreadoEn DESC;

  SELECT r.ReelId, r.Titulo, r.Estado, r.Modo, r.DuracionSeg, r.CreadoEn, Publicado = CAST(IIF(EXISTS (SELECT 1 FROM hl.ReelEnlace e WHERE e.ReelId = r.ReelId AND e.RevocadoEn IS NULL AND e.ExpiraEn > SYSUTCDATETIME()), 1, 0) AS bit),
         Clips = (SELECT COUNT(*) FROM hl.ReelClip rc WHERE rc.ReelId = r.ReelId)
  FROM hl.Reel r WHERE r.JugadorId = @JugadorId ORDER BY r.CreadoEn DESC, r.ReelId DESC;

  SELECT c.ConsentimientoId, c.TutorNombre, c.Parentesco, c.Fecha, c.VigenteHasta, c.PermiteReelPublico, c.PermiteContacto,
         c.Referencia, c.RevocadoEn, RegistradoPor = u.Nombre,
         Estado = CASE WHEN c.RevocadoEn IS NOT NULL THEN 'REVOCADO'
                       WHEN c.VigenteHasta < CAST(SYSUTCDATETIME() AS date) THEN 'VENCIDO' ELSE 'VIGENTE' END
  FROM fut.Consentimiento c JOIN seg.Usuario u ON u.UsuarioId = c.RegistradoPor
  WHERE c.JugadorId = @JugadorId ORDER BY c.CreadoEn DESC, c.ConsentimientoId DESC;
END
GO
