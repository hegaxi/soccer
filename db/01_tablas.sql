/* ============================================================
   01 · Esquemas y tablas
   seg  = seguridad          cat = catálogos y pesos
   fut  = dominio futbol     med = medios (videos y fotos)
   hl   = highlights/reels   meta = catálogo de acciones
   api  = procedimientos expuestos al cliente
   sis  = procedimientos internos del servidor (archivos, trabajos)
   ============================================================ */
IF SCHEMA_ID('seg')  IS NULL EXEC('CREATE SCHEMA seg');
IF SCHEMA_ID('cat')  IS NULL EXEC('CREATE SCHEMA cat');
IF SCHEMA_ID('fut')  IS NULL EXEC('CREATE SCHEMA fut');
IF SCHEMA_ID('med')  IS NULL EXEC('CREATE SCHEMA med');
IF SCHEMA_ID('hl')   IS NULL EXEC('CREATE SCHEMA hl');
IF SCHEMA_ID('meta') IS NULL EXEC('CREATE SCHEMA meta');
IF SCHEMA_ID('api')  IS NULL EXEC('CREATE SCHEMA api');
IF SCHEMA_ID('sis')  IS NULL EXEC('CREATE SCHEMA sis');
GO

/* ---------- seguridad ---------- */
IF OBJECT_ID('seg.Usuario') IS NULL
CREATE TABLE seg.Usuario(
  UsuarioId        int IDENTITY CONSTRAINT PK_Usuario PRIMARY KEY,
  Correo           nvarchar(200) NOT NULL CONSTRAINT UQ_Usuario_Correo UNIQUE,
  Nombre           nvarchar(120) NOT NULL,
  Rol              tinyint NOT NULL CONSTRAINT CK_Usuario_Rol CHECK (Rol IN (1,2,3)), -- 1 espectador, 2 editor, 3 admin
  Sal              varbinary(32) NOT NULL,
  HashClave        varbinary(64) NOT NULL,
  Iteraciones      int NOT NULL,
  Activo           bit NOT NULL CONSTRAINT DF_Usuario_Activo DEFAULT 1,
  IntentosFallidos int NOT NULL CONSTRAINT DF_Usuario_Intentos DEFAULT 0,
  BloqueadoHasta   datetime2(0) NULL,
  CreadoEn         datetime2(0) NOT NULL CONSTRAINT DF_Usuario_Creado DEFAULT SYSUTCDATETIME());

IF OBJECT_ID('seg.Sesion') IS NULL
CREATE TABLE seg.Sesion(
  HashToken binary(32) NOT NULL CONSTRAINT PK_Sesion PRIMARY KEY,
  UsuarioId int NOT NULL CONSTRAINT FK_Sesion_Usuario REFERENCES seg.Usuario,
  CreadoEn  datetime2(0) NOT NULL CONSTRAINT DF_Sesion_Creado DEFAULT SYSUTCDATETIME(),
  ExpiraEn  datetime2(0) NOT NULL,
  Ip        varchar(64) NULL);
GO

/* ---------- catálogo de acciones (lo que lee el controlador único) ---------- */
IF OBJECT_ID('meta.Accion') IS NULL
CREATE TABLE meta.Accion(
  Clave         varchar(100) NOT NULL CONSTRAINT PK_Accion PRIMARY KEY, -- p.ej. 'medio.listar'
  Esquema       sysname NOT NULL,
  Procedimiento sysname NOT NULL,
  RolMinimo     tinyint NOT NULL,          -- 0 anónimo, 1 espectador, 2 editor, 3 admin
  EfectoSesion  varchar(10) NOT NULL CONSTRAINT DF_Accion_Efecto DEFAULT '', -- '', 'INICIA', 'CIERRA'
  Interna       bit NOT NULL CONSTRAINT DF_Accion_Interna DEFAULT 0,   -- 1 = solo la invoca el servidor (archivos, trabajos)
  Activa        bit NOT NULL CONSTRAINT DF_Accion_Activa DEFAULT 1,
  Descripcion   nvarchar(300) NULL);
GO

/* ---------- catálogos ---------- */
IF OBJECT_ID('cat.Parametro') IS NULL
CREATE TABLE cat.Parametro(
  Clave       varchar(60) NOT NULL CONSTRAINT PK_Parametro PRIMARY KEY,
  Valor       decimal(18,4) NOT NULL,
  Descripcion nvarchar(300) NOT NULL);

IF OBJECT_ID('cat.Posicion') IS NULL
CREATE TABLE cat.Posicion(
  PosicionId tinyint NOT NULL CONSTRAINT PK_Posicion PRIMARY KEY,
  Clave      varchar(5) NOT NULL CONSTRAINT UQ_Posicion UNIQUE,
  Nombre     nvarchar(60) NOT NULL,
  Linea      varchar(12) NOT NULL);       -- PORTERIA, DEFENSA, MEDIO, ATAQUE

IF OBJECT_ID('cat.TipoEvento') IS NULL
CREATE TABLE cat.TipoEvento(
  TipoEventoId smallint NOT NULL CONSTRAINT PK_TipoEvento PRIMARY KEY,
  Clave        varchar(30) NOT NULL CONSTRAINT UQ_TipoEvento UNIQUE,
  Nombre       nvarchar(80) NOT NULL,
  Categoria    varchar(12) NOT NULL,      -- ATAQUE, CREACION, DEFENSA, PORTERIA
  PesoBase     decimal(6,2) NOT NULL,     -- valor intrínseco de la jugada (0-100)
  PreRollSeg   tinyint NOT NULL,          -- segundos antes del evento que debe mostrar el clip
  PostRollSeg  tinyint NOT NULL);

/* Qué tanto le importa a un reclutador cada tipo de jugada según la posición */
IF OBJECT_ID('cat.PesoPosicionEvento') IS NULL
CREATE TABLE cat.PesoPosicionEvento(
  PosicionId    tinyint  NOT NULL CONSTRAINT FK_PPE_Pos REFERENCES cat.Posicion,
  TipoEventoId  smallint NOT NULL CONSTRAINT FK_PPE_Tipo REFERENCES cat.TipoEvento,
  Multiplicador decimal(4,2) NOT NULL,
  CONSTRAINT PK_PPE PRIMARY KEY (PosicionId, TipoEventoId));

IF OBJECT_ID('cat.FasePartido') IS NULL
CREATE TABLE cat.FasePartido(
  Clave  varchar(12) NOT NULL CONSTRAINT PK_Fase PRIMARY KEY,
  Nombre nvarchar(40) NOT NULL,
  Factor decimal(4,2) NOT NULL,
  Orden  tinyint NOT NULL);
GO

/* ---------- dominio ---------- */
IF OBJECT_ID('fut.Temporada') IS NULL
CREATE TABLE fut.Temporada(
  TemporadaId int IDENTITY CONSTRAINT PK_Temporada PRIMARY KEY,
  Nombre      nvarchar(60) NOT NULL CONSTRAINT UQ_Temporada UNIQUE,
  FechaInicio date NOT NULL,
  FechaFin    date NOT NULL,
  Activa      bit NOT NULL CONSTRAINT DF_Temporada_Activa DEFAULT 0,
  CONSTRAINT CK_Temporada_Fechas CHECK (FechaFin >= FechaInicio));

IF OBJECT_ID('fut.Equipo') IS NULL
CREATE TABLE fut.Equipo(
  EquipoId  int IDENTITY CONSTRAINT PK_Equipo PRIMARY KEY,
  Nombre    nvarchar(100) NOT NULL CONSTRAINT UQ_Equipo UNIQUE,
  Categoria nvarchar(40) NULL,
  EsPropio  bit NOT NULL CONSTRAINT DF_Equipo_Propio DEFAULT 0);

IF OBJECT_ID('fut.Partido') IS NULL
CREATE TABLE fut.Partido(
  PartidoId      int IDENTITY CONSTRAINT PK_Partido PRIMARY KEY,
  TemporadaId    int NOT NULL CONSTRAINT FK_Partido_Temp REFERENCES fut.Temporada,
  Fecha          date NOT NULL,
  Jornada        smallint NULL,
  Competencia    nvarchar(80) NULL,
  Fase           varchar(12) NOT NULL CONSTRAINT FK_Partido_Fase REFERENCES cat.FasePartido,
  EquipoLocalId  int NOT NULL CONSTRAINT FK_Partido_Local REFERENCES fut.Equipo,
  EquipoVisitaId int NOT NULL CONSTRAINT FK_Partido_Visita REFERENCES fut.Equipo,
  GolesLocal     tinyint NULL,
  GolesVisita    tinyint NULL,
  NivelRival     tinyint NOT NULL CONSTRAINT DF_Partido_Nivel DEFAULT 3
                 CONSTRAINT CK_Partido_Nivel CHECK (NivelRival BETWEEN 1 AND 5),
  CONSTRAINT CK_Partido_Equipos CHECK (EquipoLocalId <> EquipoVisitaId));

IF OBJECT_ID('fut.Jugador') IS NULL
CREATE TABLE fut.Jugador(
  JugadorId            int IDENTITY CONSTRAINT PK_Jugador PRIMARY KEY,
  Nombre               nvarchar(80) NOT NULL,
  Apellidos            nvarchar(80) NOT NULL,
  FechaNacimiento      date NULL,
  PosicionId           tinyint NOT NULL CONSTRAINT FK_Jugador_Pos REFERENCES cat.Posicion,
  PosicionSecundariaId tinyint NULL CONSTRAINT FK_Jugador_Pos2 REFERENCES cat.Posicion,
  PieDominante         char(1) NOT NULL CONSTRAINT DF_Jugador_Pie DEFAULT 'D'
                       CONSTRAINT CK_Jugador_Pie CHECK (PieDominante IN ('D','I','A')),
  EstaturaCm           smallint NULL,
  PesoKg               smallint NULL,
  Dorsal               tinyint NULL,
  EquipoId             int NULL CONSTRAINT FK_Jugador_Equipo REFERENCES fut.Equipo,
  AnioGraduacion       smallint NULL,
  PromedioAcademico    decimal(4,2) NULL,
  CorreoContacto       nvarchar(200) NULL,
  TelefonoContacto     nvarchar(40) NULL,
  Bio                  nvarchar(1000) NULL,
  FotoMedioId          int NULL,
  Activo               bit NOT NULL CONSTRAINT DF_Jugador_Activo DEFAULT 1);
GO

/* ---------- medios: videos y fotos (el binario vive en disco/blob) ---------- */
IF OBJECT_ID('med.Medio') IS NULL
CREATE TABLE med.Medio(
  MedioId               int IDENTITY CONSTRAINT PK_Medio PRIMARY KEY,
  Tipo                  varchar(5) NOT NULL CONSTRAINT CK_Medio_Tipo CHECK (Tipo IN ('VIDEO','FOTO')),
  Titulo                nvarchar(200) NOT NULL,
  Descripcion           nvarchar(1000) NULL,
  TemporadaId           int NOT NULL CONSTRAINT FK_Medio_Temp REFERENCES fut.Temporada,
  PartidoId             int NULL CONSTRAINT FK_Medio_Partido REFERENCES fut.Partido,
  NombreOriginal        nvarchar(260) NOT NULL,
  TipoMime              varchar(100) NOT NULL,
  TamanoBytes           bigint NOT NULL,
  RutaArchivo           varchar(300) NOT NULL,
  RutaWeb               varchar(300) NULL,   -- versión reproducible en navegador
  RutaMiniatura         varchar(300) NULL,
  DuracionSeg           decimal(9,2) NULL,
  Ancho                 int NULL,
  Alto                  int NULL,
  SegundoInicioPartido  decimal(9,2) NULL,   -- en qué segundo del video rueda el balón (para calcular minuto)
  Estado                varchar(12) NOT NULL CONSTRAINT DF_Medio_Estado DEFAULT 'PENDIENTE'
                        CONSTRAINT CK_Medio_Estado CHECK (Estado IN ('PENDIENTE','SUBIDO','PROCESANDO','LISTO','ERROR')),
  ErrorProceso          nvarchar(500) NULL,
  SubidoPor             int NOT NULL CONSTRAINT FK_Medio_Usuario REFERENCES seg.Usuario,
  CreadoEn              datetime2(0) NOT NULL CONSTRAINT DF_Medio_Creado DEFAULT SYSUTCDATETIME(),
  Eliminado             bit NOT NULL CONSTRAINT DF_Medio_Elim DEFAULT 0);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Medio_Galeria')
  CREATE INDEX IX_Medio_Galeria ON med.Medio(TemporadaId, Tipo, CreadoEn DESC) WHERE Eliminado = 0;

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_Jugador_Foto')
  ALTER TABLE fut.Jugador ADD CONSTRAINT FK_Jugador_Foto FOREIGN KEY (FotoMedioId) REFERENCES med.Medio;

/* Jugadores que aparecen en un medio (etiquetado de fotos y videos) */
IF OBJECT_ID('med.MedioJugador') IS NULL
CREATE TABLE med.MedioJugador(
  MedioId   int NOT NULL CONSTRAINT FK_MJ_Medio REFERENCES med.Medio,
  JugadorId int NOT NULL CONSTRAINT FK_MJ_Jugador REFERENCES fut.Jugador,
  CONSTRAINT PK_MedioJugador PRIMARY KEY (MedioId, JugadorId));

IF OBJECT_ID('med.PicoAudio') IS NULL
CREATE TABLE med.PicoAudio(
  MedioId    int NOT NULL CONSTRAINT FK_Pico_Medio REFERENCES med.Medio,
  Segundo    int NOT NULL,
  Intensidad decimal(6,2) NOT NULL,      -- desviaciones estándar sobre la media del video
  CONSTRAINT PK_PicoAudio PRIMARY KEY (MedioId, Segundo));
GO

/* ---------- highlights ---------- */
IF OBJECT_ID('hl.Clip') IS NULL
CREATE TABLE hl.Clip(
  ClipId         int IDENTITY CONSTRAINT PK_Clip PRIMARY KEY,
  MedioId        int NOT NULL CONSTRAINT FK_Clip_Medio REFERENCES med.Medio,
  JugadorId      int NULL CONSTRAINT FK_Clip_Jugador REFERENCES fut.Jugador,
  TipoEventoId   smallint NULL CONSTRAINT FK_Clip_Tipo REFERENCES cat.TipoEvento,
  SegundoEvento  decimal(9,2) NOT NULL,
  SegundoInicio  decimal(9,2) NOT NULL,
  SegundoFin     decimal(9,2) NOT NULL,
  Minuto         tinyint NULL,           -- minuto de partido
  Resultado      char(1) NOT NULL CONSTRAINT DF_Clip_Res DEFAULT 'E'
                 CONSTRAINT CK_Clip_Res CHECK (Resultado IN ('E','F')),   -- exitosa / fallida
  Pie            char(1) NULL CONSTRAINT CK_Clip_Pie CHECK (Pie IN ('D','I','C')), -- derecha, izquierda, cabeza
  Calidad        tinyint NULL CONSTRAINT CK_Clip_Calidad CHECK (Calidad BETWEEN 1 AND 5), -- valoración técnica del editor
  EsDecisiva     bit NOT NULL CONSTRAINT DF_Clip_Decisiva DEFAULT 0,       -- cambió o salvó el resultado
  MarcaX         decimal(5,2) NULL,      -- posición del jugador al inicio del clip (% del ancho/alto)
  MarcaY         decimal(5,2) NULL,
  Nota           nvarchar(300) NULL,
  Origen         varchar(10) NOT NULL CONSTRAINT DF_Clip_Origen DEFAULT 'MANUAL'
                 CONSTRAINT CK_Clip_Origen CHECK (Origen IN ('MANUAL','AUDIO','REPETICION')),
  Estado         varchar(10) NOT NULL CONSTRAINT DF_Clip_Estado DEFAULT 'CONFIRMADO'
                 CONSTRAINT CK_Clip_Estado CHECK (Estado IN ('CONFIRMADO','CANDIDATO','DESCARTADO')),
  CreadoPor      int NULL CONSTRAINT FK_Clip_Usuario REFERENCES seg.Usuario,
  CreadoEn       datetime2(0) NOT NULL CONSTRAINT DF_Clip_Creado DEFAULT SYSUTCDATETIME(),
  CONSTRAINT CK_Clip_Ventana CHECK (SegundoInicio >= 0 AND SegundoFin > SegundoInicio),
  CONSTRAINT CK_Clip_Confirmado CHECK (Estado <> 'CONFIRMADO' OR (JugadorId IS NOT NULL AND TipoEventoId IS NOT NULL)));

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Clip_Jugador')
  CREATE INDEX IX_Clip_Jugador ON hl.Clip(JugadorId, Estado) INCLUDE (MedioId, TipoEventoId);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Clip_Medio')
  CREATE INDEX IX_Clip_Medio ON hl.Clip(MedioId, SegundoEvento);

IF OBJECT_ID('hl.Interaccion') IS NULL
CREATE TABLE hl.Interaccion(
  InteraccionId bigint IDENTITY CONSTRAINT PK_Interaccion PRIMARY KEY,
  MedioId       int NOT NULL CONSTRAINT FK_Int_Medio REFERENCES med.Medio,
  ClipId        int NULL CONSTRAINT FK_Int_Clip REFERENCES hl.Clip,
  UsuarioId     int NULL CONSTRAINT FK_Int_Usuario REFERENCES seg.Usuario,
  Tipo          varchar(12) NOT NULL CONSTRAINT CK_Int_Tipo CHECK (Tipo IN ('VISTA','REPETICION','COMPARTIR')),
  Segundo       int NULL,
  CreadoEn      datetime2(0) NOT NULL CONSTRAINT DF_Int_Creado DEFAULT SYSUTCDATETIME());
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Int_Clip')
  CREATE INDEX IX_Int_Clip ON hl.Interaccion(ClipId, Tipo) WHERE ClipId IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Int_Medio')
  CREATE INDEX IX_Int_Medio ON hl.Interaccion(MedioId, Tipo, Segundo);

IF OBJECT_ID('hl.MeGusta') IS NULL
CREATE TABLE hl.MeGusta(
  ClipId    int NOT NULL CONSTRAINT FK_MG_Clip REFERENCES hl.Clip,
  UsuarioId int NOT NULL CONSTRAINT FK_MG_Usuario REFERENCES seg.Usuario,
  CreadoEn  datetime2(0) NOT NULL CONSTRAINT DF_MG_Creado DEFAULT SYSUTCDATETIME(),
  CONSTRAINT PK_MeGusta PRIMARY KEY (ClipId, UsuarioId));

/* Reel de reclutamiento: selección ordenada de clips de un jugador */
IF OBJECT_ID('hl.Reel') IS NULL
CREATE TABLE hl.Reel(
  ReelId             int IDENTITY CONSTRAINT PK_Reel PRIMARY KEY,
  JugadorId          int NOT NULL CONSTRAINT FK_Reel_Jugador REFERENCES fut.Jugador,
  TemporadaId        int NULL CONSTRAINT FK_Reel_Temp REFERENCES fut.Temporada,
  Titulo             nvarchar(200) NOT NULL,
  DuracionObjetivoSeg int NOT NULL,
  Estado             varchar(10) NOT NULL CONSTRAINT DF_Reel_Estado DEFAULT 'BORRADOR'
                     CONSTRAINT CK_Reel_Estado CHECK (Estado IN ('BORRADOR','EN_COLA','LISTO','ERROR')),
  RutaVideo          varchar(300) NULL,
  DuracionSeg        decimal(9,2) NULL,
  ErrorProceso       nvarchar(500) NULL,
  CreadoPor          int NOT NULL CONSTRAINT FK_Reel_Usuario REFERENCES seg.Usuario,
  CreadoEn           datetime2(0) NOT NULL CONSTRAINT DF_Reel_Creado DEFAULT SYSUTCDATETIME());

IF OBJECT_ID('hl.ReelClip') IS NULL
CREATE TABLE hl.ReelClip(
  ReelId  int NOT NULL CONSTRAINT FK_RC_Reel REFERENCES hl.Reel ON DELETE CASCADE,
  Orden   smallint NOT NULL,
  ClipId  int NOT NULL CONSTRAINT FK_RC_Clip REFERENCES hl.Clip,
  Motivo  nvarchar(300) NULL,
  CONSTRAINT PK_ReelClip PRIMARY KEY (ReelId, Orden),
  CONSTRAINT UQ_ReelClip UNIQUE (ReelId, ClipId));
GO

/* ---------- cola de trabajos (ffmpeg corre fuera, la cola vive aquí) ---------- */
IF OBJECT_ID('med.Trabajo') IS NULL
CREATE TABLE med.Trabajo(
  TrabajoId  int IDENTITY CONSTRAINT PK_Trabajo PRIMARY KEY,
  Tipo       varchar(15) NOT NULL CONSTRAINT CK_Trabajo_Tipo CHECK (Tipo IN ('PROCESAR_MEDIO','RENDER_REEL')),
  MedioId    int NULL CONSTRAINT FK_Trabajo_Medio REFERENCES med.Medio,
  ReelId     int NULL CONSTRAINT FK_Trabajo_Reel REFERENCES hl.Reel ON DELETE CASCADE,
  Estado     varchar(12) NOT NULL CONSTRAINT DF_Trabajo_Estado DEFAULT 'PENDIENTE'
             CONSTRAINT CK_Trabajo_Estado CHECK (Estado IN ('PENDIENTE','EN_PROCESO','TERMINADO','ERROR')),
  Intentos   tinyint NOT NULL CONSTRAINT DF_Trabajo_Intentos DEFAULT 0,
  TomadoEn   datetime2(0) NULL,
  TerminadoEn datetime2(0) NULL,
  Error      nvarchar(500) NULL,
  CreadoEn   datetime2(0) NOT NULL CONSTRAINT DF_Trabajo_Creado DEFAULT SYSUTCDATETIME());
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Trabajo_Cola')
  CREATE INDEX IX_Trabajo_Cola ON med.Trabajo(Estado, TrabajoId);
GO

/* ---------- visorías: contacto del club, consentimiento de tutores y enlaces por destinatario ---------- */
IF OBJECT_ID('meta.Migracion') IS NULL
CREATE TABLE meta.Migracion(
  Clave      varchar(80) NOT NULL CONSTRAINT PK_Migracion PRIMARY KEY,
  AplicadaEn datetime2(0) NOT NULL CONSTRAINT DF_Migracion_En DEFAULT SYSUTCDATETIME());

-- A los visores se les da el contacto del club (coordinador), no el de un menor
IF COL_LENGTH('fut.Equipo', 'ContactoNombre') IS NULL
  ALTER TABLE fut.Equipo ADD ContactoNombre nvarchar(120) NULL, ContactoCargo nvarchar(80) NULL,
                             ContactoCorreo nvarchar(200) NULL, ContactoTelefono nvarchar(40) NULL;

-- "Clave" (lo que el diagnóstico exige ver en la posición) ya no depende del valor del multiplicador
IF COL_LENGTH('cat.PesoPosicionEvento', 'EsClave') IS NULL
  ALTER TABLE cat.PesoPosicionEvento ADD EsClave bit NOT NULL CONSTRAINT DF_PPE_Clave DEFAULT 0;

/* Autorización del padre, madre o tutor. No se edita: si cambia, se revoca y se registra una nueva. */
IF OBJECT_ID('fut.Consentimiento') IS NULL
CREATE TABLE fut.Consentimiento(
  ConsentimientoId   int IDENTITY CONSTRAINT PK_Consentimiento PRIMARY KEY,
  JugadorId          int NOT NULL CONSTRAINT FK_Cons_Jugador REFERENCES fut.Jugador,
  TutorNombre        nvarchar(120) NOT NULL,
  Parentesco         nvarchar(40) NOT NULL,
  Fecha              date NOT NULL,                 -- cuándo firmó
  VigenteHasta       date NULL,
  PermiteReelPublico bit NOT NULL,                  -- compartir el reel con visores fuera del club
  PermiteContacto    bit NOT NULL,                  -- mostrar a los visores el contacto personal/del tutor
  Referencia         nvarchar(200) NULL,            -- folio o ubicación del documento firmado
  RevocadoEn         datetime2(0) NULL,
  RegistradoPor      int NOT NULL CONSTRAINT FK_Cons_Usuario REFERENCES seg.Usuario,
  CreadoEn           datetime2(0) NOT NULL CONSTRAINT DF_Cons_Creado DEFAULT SYSUTCDATETIME());
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name='IX_Cons_Jugador')
  CREATE INDEX IX_Cons_Jugador ON fut.Consentimiento(JugadorId);

/* Un enlace por destinatario: se sabe a quién se le dio, caduca y se puede revocar sin afectar a los demás. */
IF OBJECT_ID('hl.ReelEnlace') IS NULL
CREATE TABLE hl.ReelEnlace(
  EnlaceId      int IDENTITY CONSTRAINT PK_ReelEnlace PRIMARY KEY,
  ReelId        int NOT NULL CONSTRAINT FK_Enlace_Reel REFERENCES hl.Reel ON DELETE CASCADE,
  Token         varchar(40) NOT NULL CONSTRAINT UQ_Enlace_Token UNIQUE,
  Destinatario  nvarchar(120) NOT NULL,
  ExpiraEn      datetime2(0) NOT NULL,
  RevocadoEn    datetime2(0) NULL,
  Vistas        int NOT NULL CONSTRAINT DF_Enlace_Vistas DEFAULT 0,
  UltimaVistaEn datetime2(0) NULL,
  CreadoPor     int NOT NULL CONSTRAINT FK_Enlace_Usuario REFERENCES seg.Usuario,
  CreadoEn      datetime2(0) NOT NULL CONSTRAINT DF_Enlace_Creado DEFAULT SYSUTCDATETIME());
GO

/* ---------- identificación del jugador y contexto para el visor ---------- */
-- La marca se pone en el momento en que el jugador entra a la jugada (no necesariamente al inicio del clip)
-- y con el tamaño que pide la toma: en cámara panorámica un jugador mide muy poco.
IF COL_LENGTH('hl.Clip', 'MarcaTamano') IS NULL
  ALTER TABLE hl.Clip ADD MarcaTamano decimal(4,1) NULL CONSTRAINT CK_Clip_MarcaTamano CHECK (MarcaTamano BETWEEN 4 AND 50), -- alto del recuadro, % del alto del cuadro
                          MarcaSegundo decimal(9,2) NULL;                                                                   -- segundo del video en que se señala
IF COL_LENGTH('fut.Partido', 'ColorUniforme') IS NULL
  ALTER TABLE fut.Partido ADD ColorUniforme nvarchar(30) NULL;   -- de qué color jugó nuestro equipo: lo primero que pregunta un visor
-- MEJORES = selección de highlights · PARTIDO = todas sus acciones en un partido, en orden y con las fallidas
IF COL_LENGTH('hl.Reel', 'Modo') IS NULL
  ALTER TABLE hl.Reel ADD Modo varchar(10) NOT NULL CONSTRAINT DF_Reel_Modo DEFAULT 'MEJORES' CONSTRAINT CK_Reel_Modo CHECK (Modo IN ('MEJORES','PARTIDO')),
                          PartidoId int NULL CONSTRAINT FK_Reel_Partido REFERENCES fut.Partido;
-- El enlace puede dar acceso también a los partidos completos de donde salen las jugadas
IF COL_LENGTH('hl.ReelEnlace', 'IncluyePartidos') IS NULL
  ALTER TABLE hl.ReelEnlace ADD IncluyePartidos bit NOT NULL CONSTRAINT DF_Enlace_Partidos DEFAULT 0;
GO
