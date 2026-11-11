/* ============================================================
   03 · Seguridad, sesiones y resolución de acciones
   Convención de errores: THROW 50000 + código HTTP (50400, 50401, 50403, 50404, 50409, 50429)
   ============================================================ */
CREATE OR ALTER FUNCTION cat.fn_Param(@Clave varchar(60)) RETURNS decimal(18,4)
AS BEGIN RETURN (SELECT Valor FROM cat.Parametro WHERE Clave = @Clave) END
GO

/* Hash de contraseña con sal e iteraciones (SHA2-512 encadenado). */
CREATE OR ALTER FUNCTION seg.fn_HashClave(@Clave nvarchar(200), @Sal varbinary(32), @Iteraciones int)
RETURNS varbinary(64)
AS
BEGIN
  DECLARE @h varbinary(64) = HASHBYTES('SHA2_512', @Sal + CAST(@Clave AS varbinary(400)));
  DECLARE @i int = 1;
  WHILE @i < @Iteraciones
  BEGIN
    SET @h = HASHBYTES('SHA2_512', @h + @Sal);
    SET @i += 1;
  END
  RETURN @h;
END
GO

/* El controlador único llama aquí primero: valida la acción, la sesión y el rol,
   y devuelve el procedimiento a ejecutar junto con los metadatos de sus parámetros. */
CREATE OR ALTER PROCEDURE meta.usp_Accion_Resolver
  @Clave varchar(100), @Token varchar(64) = NULL, @Interna bit = 0
WITH EXECUTE AS OWNER
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @esq sysname, @proc sysname, @rolMin tinyint, @efecto varchar(10);
  SELECT @esq = Esquema, @proc = Procedimiento, @rolMin = RolMinimo, @efecto = EfectoSesion
  FROM meta.Accion WHERE Clave = @Clave AND Activa = 1 AND Interna = @Interna;
  IF @proc IS NULL THROW 50404, N'Acción no encontrada', 1;

  DECLARE @oid int = OBJECT_ID(QUOTENAME(@esq) + '.' + QUOTENAME(@proc), 'P');
  IF @oid IS NULL THROW 50404, N'El procedimiento de la acción no existe', 1;

  DECLARE @uid int, @rol tinyint = 0;
  IF @Token IS NOT NULL AND LEN(@Token) = 64
    SELECT @uid = u.UsuarioId, @rol = u.Rol
    FROM seg.Sesion s JOIN seg.Usuario u ON u.UsuarioId = s.UsuarioId
    WHERE s.HashToken = HASHBYTES('SHA2_256', @Token) AND s.ExpiraEn > SYSUTCDATETIME() AND u.Activo = 1;

  IF @rolMin > 0 AND @uid IS NULL THROW 50401, N'Inicia sesión para continuar', 1;
  IF @rol < @rolMin THROW 50403, N'No tienes permiso para esta acción', 1;

  SELECT Procedimiento = QUOTENAME(@esq) + '.' + QUOTENAME(@proc), UsuarioId = @uid, Rol = @rol, EfectoSesion = @efecto;

  SELECT Nombre = p.name, Tipo = TYPE_NAME(p.system_type_id), Longitud = p.max_length,
         Precision = p.precision, Escala = p.scale, EsSalida = p.is_output
  FROM sys.parameters p WHERE p.object_id = @oid ORDER BY p.parameter_id;
END
GO

CREATE OR ALTER PROCEDURE meta.usp_Accion_Registrar
  @Clave varchar(100), @Procedimiento varchar(260), @RolMinimo tinyint,
  @EfectoSesion varchar(10) = '', @Interna bit = 0, @Descripcion nvarchar(300) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @esq sysname = PARSENAME(@Procedimiento, 2), @proc sysname = PARSENAME(@Procedimiento, 1);
  IF OBJECT_ID(@Procedimiento, 'P') IS NULL
  BEGIN
    DECLARE @msg nvarchar(400) = CONCAT(N'No existe el procedimiento ', @Procedimiento);
    THROW 50000, @msg, 1;
  END
  MERGE meta.Accion t USING (SELECT @Clave AS Clave) s ON t.Clave = s.Clave
  WHEN MATCHED THEN UPDATE SET Esquema=@esq, Procedimiento=@proc, RolMinimo=@RolMinimo,
       EfectoSesion=@EfectoSesion, Interna=@Interna, Descripcion=@Descripcion, Activa=1
  WHEN NOT MATCHED THEN INSERT (Clave,Esquema,Procedimiento,RolMinimo,EfectoSesion,Interna,Descripcion)
       VALUES (@Clave,@esq,@proc,@RolMinimo,@EfectoSesion,@Interna,@Descripcion);
END
GO

/* ---------- sesión ---------- */
CREATE OR ALTER PROCEDURE api.usp_Sesion_Iniciar
  @Correo nvarchar(200), @Clave nvarchar(200), @_Ip varchar(64) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @uid int, @sal varbinary(32), @hash varbinary(64), @iter int, @bloq datetime2(0), @calc varbinary(64);
  SELECT @uid = UsuarioId, @sal = Sal, @hash = HashClave, @iter = Iteraciones, @bloq = BloqueadoHasta
  FROM seg.Usuario WHERE Correo = LTRIM(RTRIM(@Correo)) AND Activo = 1;

  IF @uid IS NULL
  BEGIN
    SET @calc = seg.fn_HashClave(@Clave, 0x00, cat.fn_Param('HASH_ITERACIONES')); -- mismo costo aunque no exista
    THROW 50401, N'Correo o contraseña incorrectos', 1;
  END
  IF @bloq > SYSUTCDATETIME() THROW 50429, N'Cuenta bloqueada por intentos fallidos. Intenta en unos minutos.', 1;

  IF seg.fn_HashClave(@Clave, @sal, @iter) <> @hash
  BEGIN
    UPDATE seg.Usuario
    SET IntentosFallidos = IIF(IntentosFallidos + 1 >= 5, 0, IntentosFallidos + 1),
        BloqueadoHasta   = IIF(IntentosFallidos + 1 >= 5, DATEADD(minute, 15, SYSUTCDATETIME()), NULL)
    WHERE UsuarioId = @uid;
    THROW 50401, N'Correo o contraseña incorrectos', 1;
  END

  UPDATE seg.Usuario SET IntentosFallidos = 0, BloqueadoHasta = NULL WHERE UsuarioId = @uid;
  DELETE seg.Sesion WHERE ExpiraEn < SYSUTCDATETIME();

  DECLARE @token varchar(64) = LOWER(CONVERT(varchar(64), CRYPT_GEN_RANDOM(32), 2));
  INSERT seg.Sesion(HashToken, UsuarioId, ExpiraEn, Ip)
  VALUES (HASHBYTES('SHA2_256', @token), @uid, DATEADD(hour, CAST(cat.fn_Param('SESION_HORAS') AS int), SYSUTCDATETIME()), @_Ip);

  -- "_token" lo consume el controlador (cookie HttpOnly) y no llega al navegador como dato
  SELECT _token = @token, UsuarioId, Nombre, Correo, Rol FROM seg.Usuario WHERE UsuarioId = @uid;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Sesion_Cerrar @_Token varchar(64) = NULL
AS
BEGIN
  SET NOCOUNT ON;
  IF @_Token IS NOT NULL DELETE seg.Sesion WHERE HashToken = HASHBYTES('SHA2_256', @_Token);
  SELECT Cerrada = CAST(1 AS bit);
END
GO

CREATE OR ALTER PROCEDURE api.usp_Sesion_Actual @_UsuarioId int = NULL
AS
BEGIN
  SET NOCOUNT ON;
  SELECT UsuarioId, Nombre, Correo, Rol FROM seg.Usuario WHERE UsuarioId = @_UsuarioId;
END
GO

/* ---------- usuarios ---------- */
CREATE OR ALTER PROCEDURE seg.usp_Usuario_Guardar
  @UsuarioId int = NULL, @Correo nvarchar(200), @Nombre nvarchar(120), @Rol tinyint,
  @Clave nvarchar(200) = NULL, @Activo bit = 1
AS
BEGIN
  SET NOCOUNT ON;
  SET @Correo = LOWER(LTRIM(RTRIM(@Correo))); SET @Nombre = LTRIM(RTRIM(@Nombre));
  IF @Correo NOT LIKE '%_@_%._%' THROW 50400, N'Correo inválido', 1;
  IF @Nombre = '' THROW 50400, N'El nombre es obligatorio', 1;
  IF @Rol NOT IN (1,2,3) THROW 50400, N'Rol inválido', 1;
  IF @UsuarioId IS NULL AND @Clave IS NULL THROW 50400, N'La contraseña es obligatoria', 1;
  IF @Clave IS NOT NULL AND LEN(@Clave) < 8 THROW 50400, N'La contraseña debe tener al menos 8 caracteres', 1;
  IF EXISTS (SELECT 1 FROM seg.Usuario WHERE Correo = @Correo AND UsuarioId <> ISNULL(@UsuarioId, 0))
    THROW 50409, N'Ya existe un usuario con ese correo', 1;

  DECLARE @sal varbinary(32) = CRYPT_GEN_RANDOM(32), @iter int = cat.fn_Param('HASH_ITERACIONES');
  IF @UsuarioId IS NULL
  BEGIN
    INSERT seg.Usuario(Correo, Nombre, Rol, Sal, HashClave, Iteraciones, Activo)
    VALUES (@Correo, @Nombre, @Rol, @sal, seg.fn_HashClave(@Clave, @sal, @iter), @iter, @Activo);
    SET @UsuarioId = SCOPE_IDENTITY();
  END
  ELSE
  BEGIN
    IF (@Activo = 0 OR @Rol < 3)
       AND NOT EXISTS (SELECT 1 FROM seg.Usuario WHERE Rol = 3 AND Activo = 1 AND UsuarioId <> @UsuarioId)
      THROW 50409, N'Debe quedar al menos un administrador activo', 1;
    UPDATE seg.Usuario SET Correo = @Correo, Nombre = @Nombre, Rol = @Rol, Activo = @Activo WHERE UsuarioId = @UsuarioId;
    IF @@ROWCOUNT = 0 THROW 50404, N'Usuario no encontrado', 1;
    IF @Clave IS NOT NULL
      UPDATE seg.Usuario SET Sal = @sal, HashClave = seg.fn_HashClave(@Clave, @sal, @iter), Iteraciones = @iter,
             IntentosFallidos = 0, BloqueadoHasta = NULL WHERE UsuarioId = @UsuarioId;
    IF @Activo = 0 OR @Clave IS NOT NULL DELETE seg.Sesion WHERE UsuarioId = @UsuarioId;
  END
  SELECT UsuarioId, Correo, Nombre, Rol, Activo FROM seg.Usuario WHERE UsuarioId = @UsuarioId;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Usuario_Guardar
  @UsuarioId int = NULL, @Correo nvarchar(200), @Nombre nvarchar(120), @Rol tinyint,
  @Clave nvarchar(200) = NULL, @Activo bit = 1
AS
BEGIN
  SET NOCOUNT ON;
  EXEC seg.usp_Usuario_Guardar @UsuarioId, @Correo, @Nombre, @Rol, @Clave, @Activo;
END
GO

CREATE OR ALTER PROCEDURE api.usp_Usuario_Listar
AS
BEGIN
  SET NOCOUNT ON;
  SELECT UsuarioId, Correo, Nombre, Rol, Activo, CreadoEn FROM seg.Usuario ORDER BY Nombre;
END
GO
