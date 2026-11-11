/* ============================================================
   04 · Temporadas, equipos, partidos y jugadores
   ============================================================ */
CREATE OR ALTER PROCEDURE api.usp_Catalogo_Inicial
AS
BEGIN
  SET NOCOUNT ON;
  SELECT TemporadaId, Nombre, FechaInicio, FechaFin, Activa FROM fut.Temporada ORDER BY FechaInicio DESC;
  SELECT PosicionId, Clave, Nombre, Linea FROM cat.Posicion ORDER BY PosicionId;
  SELECT TipoEventoId, Clave, Nombre, Categoria, PesoBase, PreRollSeg, PostRollSeg FROM cat.TipoEvento ORDER BY TipoEventoId;
  SELECT Clave, Nombre, Factor FROM cat.FasePartido ORDER BY Orden;
  SELECT EquipoId, Nombre, Categoria, EsPropio, ContactoNombre, ContactoCargo, ContactoCorreo, ContactoTelefono
  FROM fut.Equipo ORDER BY EsPropio DESC, Nombre;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Temporada_Guardar
  @TemporadaId int = NULL, @Nombre nvarchar(60), @FechaInicio date, @FechaFin date, @Activa bit = 0
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;
  SET @Nombre = LTRIM(RTRIM(@Nombre));
  IF @Nombre = '' THROW 50400, N'El nombre de la temporada es obligatorio', 1;
  IF @FechaFin < @FechaInicio THROW 50400, N'La fecha de fin no puede ser anterior al inicio', 1;
  IF EXISTS (SELECT 1 FROM fut.Temporada WHERE Nombre = @Nombre AND TemporadaId <> ISNULL(@TemporadaId, 0))
    THROW 50409, N'Ya existe una temporada con ese nombre', 1;
  BEGIN TRAN;
    IF @Activa = 1 UPDATE fut.Temporada SET Activa = 0 WHERE Activa = 1;
    IF @TemporadaId IS NULL
    BEGIN
      INSERT fut.Temporada(Nombre, FechaInicio, FechaFin, Activa) VALUES (@Nombre, @FechaInicio, @FechaFin, @Activa);
      SET @TemporadaId = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
      UPDATE fut.Temporada SET Nombre=@Nombre, FechaInicio=@FechaInicio, FechaFin=@FechaFin, Activa=@Activa
      WHERE TemporadaId = @TemporadaId;
      IF @@ROWCOUNT = 0 THROW 50404, N'Temporada no encontrada', 1;
    END
  COMMIT;
  SELECT TemporadaId, Nombre, FechaInicio, FechaFin, Activa FROM fut.Temporada WHERE TemporadaId = @TemporadaId;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Equipo_Guardar
  @EquipoId int = NULL, @Nombre nvarchar(100), @Categoria nvarchar(40) = NULL, @EsPropio bit = 0,
  @ContactoNombre nvarchar(120) = NULL, @ContactoCargo nvarchar(80) = NULL,
  @ContactoCorreo nvarchar(200) = NULL, @ContactoTelefono nvarchar(40) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  SET @Nombre = LTRIM(RTRIM(@Nombre));
  IF @Nombre = '' THROW 50400, N'El nombre del equipo es obligatorio', 1;
  IF @ContactoCorreo IS NOT NULL AND @ContactoCorreo NOT LIKE '%_@_%._%' THROW 50400, N'Correo de contacto inválido', 1;
  IF EXISTS (SELECT 1 FROM fut.Equipo WHERE Nombre = @Nombre AND EquipoId <> ISNULL(@EquipoId, 0))
    THROW 50409, N'Ya existe un equipo con ese nombre', 1;
  IF @EquipoId IS NULL
  BEGIN
    INSERT fut.Equipo(Nombre, Categoria, EsPropio, ContactoNombre, ContactoCargo, ContactoCorreo, ContactoTelefono)
    VALUES (@Nombre, @Categoria, @EsPropio, @ContactoNombre, @ContactoCargo, @ContactoCorreo, @ContactoTelefono);
    SET @EquipoId = SCOPE_IDENTITY();
  END
  ELSE
  BEGIN
    UPDATE fut.Equipo SET Nombre=@Nombre, Categoria=@Categoria, EsPropio=@EsPropio, ContactoNombre=@ContactoNombre,
           ContactoCargo=@ContactoCargo, ContactoCorreo=@ContactoCorreo, ContactoTelefono=@ContactoTelefono WHERE EquipoId = @EquipoId;
    IF @@ROWCOUNT = 0 THROW 50404, N'Equipo no encontrado', 1;
  END
  SELECT EquipoId = @EquipoId;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Partido_Listar @TemporadaId int = NULL
AS
BEGIN
  SET NOCOUNT ON;
  SELECT p.PartidoId, p.TemporadaId, p.Fecha, p.Jornada, p.Competencia, p.Fase, FaseNombre = f.Nombre,
         p.EquipoLocalId, Local = el.Nombre, p.EquipoVisitaId, Visita = ev.Nombre,
         p.GolesLocal, p.GolesVisita, p.NivelRival, p.ColorUniforme,
         Videos = (SELECT COUNT(*) FROM med.Medio m WHERE m.PartidoId = p.PartidoId AND m.Tipo='VIDEO' AND m.Eliminado=0),
         Fotos  = (SELECT COUNT(*) FROM med.Medio m WHERE m.PartidoId = p.PartidoId AND m.Tipo='FOTO'  AND m.Eliminado=0)
  FROM fut.Partido p
  JOIN fut.Equipo el ON el.EquipoId = p.EquipoLocalId
  JOIN fut.Equipo ev ON ev.EquipoId = p.EquipoVisitaId
  JOIN cat.FasePartido f ON f.Clave = p.Fase
  WHERE @TemporadaId IS NULL OR p.TemporadaId = @TemporadaId
  ORDER BY p.Fecha DESC, p.PartidoId DESC;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Partido_Guardar
  @PartidoId int = NULL, @TemporadaId int, @Fecha date, @Jornada smallint = NULL, @Competencia nvarchar(80) = NULL,
  @Fase varchar(12) = 'LIGA', @EquipoLocalId int, @EquipoVisitaId int,
  @GolesLocal tinyint = NULL, @GolesVisita tinyint = NULL, @NivelRival tinyint = 3, @ColorUniforme nvarchar(30) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF NOT EXISTS (SELECT 1 FROM fut.Temporada WHERE TemporadaId = @TemporadaId) THROW 50400, N'Temporada inválida', 1;
  IF NOT EXISTS (SELECT 1 FROM cat.FasePartido WHERE Clave = @Fase) THROW 50400, N'Fase inválida', 1;
  IF @EquipoLocalId = @EquipoVisitaId THROW 50400, N'Local y visitante deben ser equipos distintos', 1;
  IF (SELECT COUNT(*) FROM fut.Equipo WHERE EquipoId IN (@EquipoLocalId, @EquipoVisitaId)) <> 2 THROW 50400, N'Equipo inválido', 1;
  IF @NivelRival NOT BETWEEN 1 AND 5 THROW 50400, N'El nivel del rival va de 1 a 5', 1;
  IF @PartidoId IS NULL
  BEGIN
    INSERT fut.Partido(TemporadaId, Fecha, Jornada, Competencia, Fase, EquipoLocalId, EquipoVisitaId, GolesLocal, GolesVisita, NivelRival, ColorUniforme)
    VALUES (@TemporadaId, @Fecha, @Jornada, @Competencia, @Fase, @EquipoLocalId, @EquipoVisitaId, @GolesLocal, @GolesVisita, @NivelRival, NULLIF(LTRIM(RTRIM(@ColorUniforme)), ''));
    SET @PartidoId = SCOPE_IDENTITY();
  END
  ELSE
  BEGIN
    UPDATE fut.Partido SET TemporadaId=@TemporadaId, Fecha=@Fecha, Jornada=@Jornada, Competencia=@Competencia, Fase=@Fase,
           EquipoLocalId=@EquipoLocalId, EquipoVisitaId=@EquipoVisitaId, GolesLocal=@GolesLocal, GolesVisita=@GolesVisita, NivelRival=@NivelRival,
           ColorUniforme=NULLIF(LTRIM(RTRIM(@ColorUniforme)), '')
    WHERE PartidoId = @PartidoId;
    IF @@ROWCOUNT = 0 THROW 50404, N'Partido no encontrado', 1;
  END
  SELECT PartidoId = @PartidoId;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Jugador_Listar @Busqueda nvarchar(80) = NULL, @SoloActivos bit = 1
AS
BEGIN
  SET NOCOUNT ON;
  SELECT j.JugadorId, j.Nombre, j.Apellidos, j.Dorsal, j.PosicionId, Posicion = p.Nombre, PosicionClave = p.Clave,
         j.PieDominante, j.EstaturaCm, j.AnioGraduacion, AnioNacimiento = YEAR(j.FechaNacimiento), j.EquipoId, Equipo = e.Nombre, j.FotoMedioId, j.Activo,
         Clips = (SELECT COUNT(*) FROM hl.Clip c JOIN med.Medio m ON m.MedioId = c.MedioId AND m.Eliminado = 0
                  WHERE c.JugadorId = j.JugadorId AND c.Estado = 'CONFIRMADO'),
         Reels = (SELECT COUNT(*) FROM hl.Reel r WHERE r.JugadorId = j.JugadorId)
  FROM fut.Jugador j
  JOIN cat.Posicion p ON p.PosicionId = j.PosicionId
  LEFT JOIN fut.Equipo e ON e.EquipoId = j.EquipoId
  WHERE (@SoloActivos = 0 OR j.Activo = 1)
    AND (@Busqueda IS NULL OR CONCAT(j.Nombre, ' ', j.Apellidos) LIKE '%' + @Busqueda + '%')
  ORDER BY j.Apellidos, j.Nombre;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Jugador_Guardar
  @JugadorId int = NULL, @Nombre nvarchar(80), @Apellidos nvarchar(80), @FechaNacimiento date = NULL,
  @PosicionId tinyint, @PosicionSecundariaId tinyint = NULL, @PieDominante char(1) = 'D',
  @EstaturaCm smallint = NULL, @PesoKg smallint = NULL, @Dorsal tinyint = NULL, @EquipoId int = NULL,
  @AnioGraduacion smallint = NULL, @PromedioAcademico decimal(4,2) = NULL,
  @CorreoContacto nvarchar(200) = NULL, @TelefonoContacto nvarchar(40) = NULL, @Bio nvarchar(1000) = NULL,
  @FotoMedioId int = NULL, @Activo bit = 1
AS
BEGIN
  SET NOCOUNT ON;
  SET @Nombre = LTRIM(RTRIM(@Nombre)); SET @Apellidos = LTRIM(RTRIM(@Apellidos));
  IF @Nombre = '' OR @Apellidos = '' THROW 50400, N'Nombre y apellidos son obligatorios', 1;
  IF NOT EXISTS (SELECT 1 FROM cat.Posicion WHERE PosicionId = @PosicionId) THROW 50400, N'Posición inválida', 1;
  IF @PieDominante NOT IN ('D','I','A') THROW 50400, N'Pie dominante inválido', 1;
  IF @EstaturaCm IS NOT NULL AND @EstaturaCm NOT BETWEEN 100 AND 230 THROW 50400, N'Estatura fuera de rango (cm)', 1;
  IF @FotoMedioId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM med.Medio WHERE MedioId = @FotoMedioId AND Tipo = 'FOTO' AND Eliminado = 0)
    THROW 50400, N'La foto de perfil no existe', 1;
  IF @JugadorId IS NULL
  BEGIN
    INSERT fut.Jugador(Nombre, Apellidos, FechaNacimiento, PosicionId, PosicionSecundariaId, PieDominante, EstaturaCm, PesoKg,
                       Dorsal, EquipoId, AnioGraduacion, PromedioAcademico, CorreoContacto, TelefonoContacto, Bio, FotoMedioId, Activo)
    VALUES (@Nombre, @Apellidos, @FechaNacimiento, @PosicionId, @PosicionSecundariaId, @PieDominante, @EstaturaCm, @PesoKg,
            @Dorsal, @EquipoId, @AnioGraduacion, @PromedioAcademico, @CorreoContacto, @TelefonoContacto, @Bio, @FotoMedioId, @Activo);
    SET @JugadorId = SCOPE_IDENTITY();
  END
  ELSE
  BEGIN
    UPDATE fut.Jugador SET Nombre=@Nombre, Apellidos=@Apellidos, FechaNacimiento=@FechaNacimiento, PosicionId=@PosicionId,
           PosicionSecundariaId=@PosicionSecundariaId, PieDominante=@PieDominante, EstaturaCm=@EstaturaCm, PesoKg=@PesoKg,
           Dorsal=@Dorsal, EquipoId=@EquipoId, AnioGraduacion=@AnioGraduacion, PromedioAcademico=@PromedioAcademico,
           CorreoContacto=@CorreoContacto, TelefonoContacto=@TelefonoContacto, Bio=@Bio, FotoMedioId=@FotoMedioId, Activo=@Activo
    WHERE JugadorId = @JugadorId;
    IF @@ROWCOUNT = 0 THROW 50404, N'Jugador no encontrado', 1;
  END
  SELECT JugadorId = @JugadorId;
END
GO
