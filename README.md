# Soccer · videos, fotos y highlights de la temporada para reclutamiento

Aplicación para guardar los videos y fotos de la temporada, verlos como galería, marcar las jugadas de cada
jugador y armar automáticamente su **reel de reclutamiento** con las mejores.

- **SQL Server**: toda la lógica de negocio (validaciones, permisos, puntaje, selección del reel, cola de trabajos).
- **C# / ASP.NET Core 8**: un solo controlador que lee metadatos y ejecuta el procedimiento que corresponda.
- **React + TypeScript (Vite)**: galería, marcado de jugadas, ranking, ficha de jugador, reel y enlace para visores.

## Arquitectura

```
React ──POST /api/exec {accion, params}──▶ ApiController ──▶ meta.usp_Accion_Resolver ──▶ api.usp_…
      ──PUT/GET /api/archivo/{id}──────▶ (solo mueve bytes; la base autoriza y dice la ruta)
                                          ProcesadorMedios (ffmpeg) ◀── cola med.Trabajo ──▶ sis.usp_Trabajo_…
```

### El controlador único (`api/Controllers/ApiController.cs`, `api/Datos/EjecutorSp.cs`)

1. El cliente manda una **acción** (`medio.listar`), nunca el nombre de un procedimiento.
2. `meta.usp_Accion_Resolver` busca la acción en `meta.Accion`, valida sesión y rol mínimo, y devuelve el
   procedimiento junto con sus parámetros leídos de `sys.parameters`.
3. El ejecutor enlaza el JSON por nombre con el tipo que declara el procedimiento. Parámetros desconocidos se
   rechazan; los que empiezan con `@_` (`@_UsuarioId`, `@_Rol`, `@_Ip`, `@_Token`) los pone el servidor.
4. Devuelve todos los conjuntos de resultados como JSON. Una columna `XxxJson` se entrega ya interpretada.
5. Errores de negocio: `THROW 50000 + código HTTP` (50400, 50401, 50403, 50404, 50409).

Agregar una función nueva = crear el procedimiento y registrarlo en `db/09_acciones.sql`. No se toca C#.

El usuario de base de datos de la aplicación (`soccer_app`) solo tiene `EXECUTE` sobre los esquemas `api` y `sis`
y sobre el resolvedor: no puede leer ni escribir tablas directamente.

### Archivos

El binario no pasa por SQL. `medio.crear` valida extensión y tamaño, decide la ruta y registra el medio; el
archivo se sube por partes a `PUT /api/archivo/{id}?offset=` (reanudable) y se sirve con `Range`. Un proceso en
segundo plano con ffmpeg genera miniatura, versión para navegador y análisis de audio, tomando el trabajo de una
cola en la base. `Almacen.cs` guarda en disco; es la única clase a cambiar para usar Azure Blob o S3.

## Cómo se eligen los mejores highlights

SQL no ve el video: puntúa señales. Cada jugada confirmada tiene tres componentes de 0 a 100
(vista `hl.vw_ClipPuntaje`):

| Componente | De dónde sale |
|---|---|
| **Técnico** | valor del tipo de jugada × relevancia para la posición del jugador × calidad (1-5★) × nivel del rival (1-5) × fase del partido × bonos (decisiva, pie no dominante, tramo final); las fallidas valen la mitad |
| **Interacción** | me gusta y repeticiones por vista, con suavizado para que 2 de 2 no le gane a 150 de 500 |
| **Audio** | pico de ruido ambiente dentro del clip (reacción de la grada o la banca) |

Dos mezclas: **general** (55 / 35 / 10) para la galería y **reclutamiento** (100 % técnico): los «me gusta»
miden popularidad y el audio favorece goles y partidos con grada; ninguno evalúa al jugador. Todos los pesos están en `cat.Parametro`,
`cat.TipoEvento`, `cat.PesoPosicionEvento` y `cat.FasePartido`: se ajustan con un `UPDATE`, sin redesplegar.

**Candidatos automáticos.** Al procesar un video se proponen momentos sin marcar: picos de audio y tramos que
varios usuarios regresaron a ver. El editor los confirma (jugador + tipo) o los descarta.

**Reel de reclutamiento** (`api.usp_Reel_Generar`):

- Solo jugadas donde el jugador luce; las fallidas entran únicamente con ejecución de 4-5★.
- Selección por puntaje con rendimientos decrecientes por tipo de jugada y por partido: perfil completo y
  consistente en vez de diez goles iguales contra el mismo rival.
- Las mejores primero (el visor decide en los primeros 30 s) y una fuerte reservada para el cierre.
- El video final lleva tarjeta inicial con los datos del jugador y, en cada jugada, un cuadro congelado (1 s)
  con un recuadro que lo señala. La marca se pone en el momento en que el jugador entra a la jugada y con el
  tamaño que pida la toma. Cada jugada lleva una etiqueta con rival, fecha, color del uniforme y dorsal.
  Sale sin audio. La duración objetivo incluye la tarjeta y los cuadros congelados.
- **Reel de un partido** (`@Modo = 'PARTIDO'`): todas las acciones marcadas del jugador en un partido, en orden
  y con las fallidas. Es el contexto que un visor pide después de los highlights.
- El video no lleva contacto ni fecha de nacimiento completa (solo «Categoría» = año de nacimiento y
  «Class of» = año de graduación): un archivo descargado ya no se puede retirar.

**Diagnóstico** (`hl.fn_Diagnostico`): dice qué le falta al material de un jugador según su posición — jugadas
clave sin evidencia (bandera `EsClave` en `cat.PesoPosicionEvento`), nada con el pie no dominante, todo de un
solo partido, nada ante rivales fuertes, jugadas sin señalar al jugador, falta de consentimiento del tutor,
equipo sin contacto para visores.

## Compartir con visores y protección de menores

- **Consentimiento del tutor** (`fut.Consentimiento`): el reel de un menor de 18 años (o de un jugador sin
  fecha de nacimiento) no se puede compartir sin una autorización vigente registrada en su ficha. Revocarla
  corta el acceso de inmediato, porque el permiso se comprueba en cada visita.
- **Un enlace por destinatario** (`hl.ReelEnlace`): con caducidad (30 días por defecto, parámetro
  `ENLACE_DIAS`), retirable de forma individual y con conteo de aperturas.
- **Partidos completos, opcional por enlace**: al crear el enlace se puede incluir el video completo de los
  partidos de donde salen las jugadas, con las jugadas como índice. En esos videos aparecen también otros
  jugadores, por eso no se incluyen por defecto.
- **Lo que ve el visor**: el video, año de nacimiento y el **contacto del club** (se captura en
  Administración → Equipos). El contacto personal o del tutor solo aparece si el jugador es mayor de edad o el
  tutor lo autorizó expresamente.
- La página y los archivos se sirven con `noindex` y el reproductor oculta la descarga (es disuasorio, no una
  protección real; por eso el video no lleva datos personales).

Esto no sustituye la revisión legal del aviso de privacidad y del formato de autorización del club.

## Puesta en marcha

Requisitos: .NET 8 SDK, Node 20+, SQL Server 2022 (usa `LEAST`/`GREATEST`), ffmpeg y ffprobe en el PATH.

```bash
# 1. SQL Server (o usa uno existente)
SA_PASSWORD='...' docker compose up -d

# 2. Base de datos (idempotente; --demo agrega temporada, equipos, partidos y plantel de ejemplo)
SQL_CONTENEDOR=soccer-sql SA_PASSWORD='...' APP_PASSWORD='...' \
ADMIN_CORREO=admin@miclub.com ADMIN_CLAVE='...' db/desplegar.sh --demo

# 3. Interfaz (queda en api/wwwroot)
cd web && npm install && npm run build && cd ..

# 4. API (sirve también la interfaz)
cd api
ConnectionStrings__Soccer='Server=localhost,1433;Database=Soccer;User Id=soccer_app;Password=...;TrustServerCertificate=True' \
ASPNETCORE_URLS=http://localhost:5080 dotnet run
```

Sin `SQL_CONTENEDOR`, `desplegar.sh` usa el `sqlcmd` local (`SQL_SERVER`, `SQLCMD`). Para desarrollo de la
interfaz: `cd web && npm run dev` (redirige `/api` a `localhost:5080`).

Configuración en `api/appsettings.json`: `Almacenamiento:Raiz` (carpeta de archivos), `Procesador:Ffmpeg`,
`Procesador:Ffprobe`, `Procesador:Fuente` (tipografía de la tarjeta del reel).

En producción la API debe ir detrás de HTTPS: la cookie de sesión se marca `Secure` solo si la petición llega
por HTTPS.

### Instalar como aplicación

La interfaz es una SPA instalable (PWA): tiene manifiesto, iconos y un service worker (`web/public/sw.js`).
En Chrome/Edge aparece «Instalar app» en la barra lateral y en la barra de direcciones; en iPhone,
Compartir → «Agregar a inicio». El navegador solo ofrece instalar si el sitio se sirve por **HTTPS**
(o en `localhost`). El service worker guarda únicamente la interfaz; datos, sesión y videos siempre van al
servidor, así que sin conexión la app abre y avisa que no hay red.

### Prueba de punta a punta

Con la API en marcha y los datos de demostración:

```bash
node scripts/prueba.mjs un_video.mp4 una_foto.jpg
```

Recorre sesión, permisos por rol, subida, procesamiento, candidatos por audio, puntaje, ranking, generación y
render del reel, consentimiento del tutor y enlaces para visores.

## Roles

| Rol | Puede |
|---|---|
| Espectador | ver galería y highlights, dar me gusta |
| Editor / entrenador | subir, marcar jugadas, editar jugadores y partidos, registrar consentimientos, generar y compartir reels |
| Administrador | además, temporadas y usuarios |

## Estructura

```
db/    01 tablas · 02 catálogos y pesos · 03 seguridad y resolvedor · 04 futbol · 05 medios
       06 puntaje y highlights · 07 consentimiento, enlaces, reels y diagnóstico · 08 internos
       09 catálogo de acciones · 10 migraciones de datos (se aplican una sola vez)
api/   Controllers/ApiController.cs · Datos/EjecutorSp.cs · Datos/Almacen.cs · Trabajos/ProcesadorMedios.cs
web/   src/paginas (Galeria, Subir, VideoDetalle, Highlights, Jugadores, ReelDetalle, ReelPublico, Admin)
```

## Limitaciones conocidas

- Eliminar un medio lo oculta, pero no borra sus archivos del almacén; tampoco se borra el video anterior de un
  reel al renderizarlo de nuevo.
- El hash de contraseñas es SHA2-512 con sal e iteraciones, hecho en T-SQL para mantener la autenticación en la
  base; es más débil que bcrypt/Argon2.
- La detección automática propone momentos, no identifica la jugada ni al jugador: eso lo confirma una persona.
