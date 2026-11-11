/* ============================================================
   09 · Catálogo de acciones: lo único que el controlador sabe ejecutar
   Rol mínimo: 0 anónimo · 1 espectador · 2 editor/entrenador · 3 administrador
   ============================================================ */
SET NOCOUNT ON;
DECLARE @a TABLE (Clave varchar(100), Proc_ varchar(260), Rol tinyint, Efecto varchar(10), Interna bit, Descr nvarchar(300));
INSERT @a VALUES
 ('sesion.iniciar',     'api.usp_Sesion_Iniciar',     0, 'INICIA', 0, N'Inicia sesión'),
 ('sesion.cerrar',      'api.usp_Sesion_Cerrar',      0, 'CIERRA', 0, N'Cierra la sesión'),
 ('sesion.actual',      'api.usp_Sesion_Actual',      0, '',       0, N'Usuario de la sesión'),
 ('usuario.listar',     'api.usp_Usuario_Listar',     3, '',       0, N'Usuarios'),
 ('usuario.guardar',    'api.usp_Usuario_Guardar',    3, '',       0, N'Alta/edición de usuario'),
 ('catalogo.inicial',   'api.usp_Catalogo_Inicial',   1, '',       0, N'Temporadas, posiciones, tipos de jugada, fases, equipos'),
 ('temporada.guardar',  'api.usp_Temporada_Guardar',  3, '',       0, N'Alta/edición de temporada'),
 ('equipo.guardar',     'api.usp_Equipo_Guardar',     2, '',       0, N'Alta/edición de equipo'),
 ('partido.listar',     'api.usp_Partido_Listar',     1, '',       0, N'Partidos de una temporada'),
 ('partido.guardar',    'api.usp_Partido_Guardar',    2, '',       0, N'Alta/edición de partido'),
 ('jugador.listar',     'api.usp_Jugador_Listar',     1, '',       0, N'Plantel'),
 ('jugador.obtener',    'api.usp_Jugador_Obtener',    1, '',       0, N'Ficha de jugador con diagnóstico de reclutamiento'),
 ('jugador.guardar',    'api.usp_Jugador_Guardar',    2, '',       0, N'Alta/edición de jugador'),
 ('medio.crear',        'api.usp_Medio_Crear',        2, '',       0, N'Registra un video o foto antes de subir el archivo'),
 ('medio.listar',       'api.usp_Medio_Listar',       1, '',       0, N'Galería'),
 ('medio.obtener',      'api.usp_Medio_Obtener',      1, '',       0, N'Detalle de un medio con sus jugadas'),
 ('medio.actualizar',   'api.usp_Medio_Actualizar',   2, '',       0, N'Edita datos de un medio'),
 ('medio.eliminar',     'api.usp_Medio_Eliminar',     2, '',       0, N'Elimina un medio'),
 ('medio.interaccion',  'api.usp_Medio_Interaccion',  1, '',       0, N'Registra vistas y repeticiones de un video'),
 ('medio.candidatos',   'api.usp_Medio_Candidatos',   2, '',       0, N'Busca jugadas candidatas en un video'),
 ('clip.guardar',       'api.usp_Clip_Guardar',       2, '',       0, N'Marca o edita una jugada'),
 ('clip.eliminar',      'api.usp_Clip_Eliminar',      2, '',       0, N'Descarta una jugada o candidato'),
 ('clip.interaccion',   'api.usp_Clip_Interaccion',   1, '',       0, N'Registra vista/repetición/compartir de una jugada'),
 ('clip.meGusta',       'api.usp_Clip_MeGusta',       1, '',       0, N'Alterna me gusta'),
 ('highlight.top',      'api.usp_Highlight_Top',      1, '',       0, N'Ranking de highlights'),
 ('reel.generar',       'api.usp_Reel_Generar',       2, '',       0, N'Arma el reel de reclutamiento de un jugador'),
 ('reel.listar',        'api.usp_Reel_Listar',        1, '',       0, N'Reels'),
 ('reel.obtener',       'api.usp_Reel_Obtener',       1, '',       0, N'Detalle de un reel'),
 ('reel.ordenar',       'api.usp_Reel_Ordenar',       2, '',       0, N'Reordena/edita las jugadas de un reel'),
 ('reel.renderizar',    'api.usp_Reel_Renderizar',    2, '',       0, N'Encola el render del video del reel'),
 ('reel.publicar',      'api.usp_Reel_Publicar',      2, '',       0, N'Genera o revoca el enlace público'),
 ('reel.eliminar',      'api.usp_Reel_Eliminar',      2, '',       0, N'Elimina un reel'),
 ('reel.publico',       'api.usp_Reel_Publico',       0, '',       0, N'Reel visto por un visor con el enlace'),
 ('archivo.autorizarSubida',  'sis.usp_Archivo_AutorizarSubida',  2, '', 1, N'Interna'),
 ('archivo.subidaCompleta',   'sis.usp_Archivo_SubidaCompleta',   2, '', 1, N'Interna'),
 ('archivo.autorizarLectura', 'sis.usp_Archivo_AutorizarLectura', 0, '', 1, N'Interna'),
 ('archivo.autorizarReel',    'sis.usp_Archivo_AutorizarReel',    0, '', 1, N'Interna'),
 ('trabajo.tomar',            'sis.usp_Trabajo_Tomar',            0, '', 1, N'Interna'),
 ('trabajo.completar',        'sis.usp_Trabajo_Completar',        0, '', 1, N'Interna');

DECLARE @c varchar(100), @p varchar(260), @r tinyint, @e varchar(10), @i bit, @d nvarchar(300);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT * FROM @a;
OPEN cur; FETCH NEXT FROM cur INTO @c, @p, @r, @e, @i, @d;
WHILE @@FETCH_STATUS = 0
BEGIN
  EXEC meta.usp_Accion_Registrar @c, @p, @r, @e, @i, @d;
  FETCH NEXT FROM cur INTO @c, @p, @r, @e, @i, @d;
END
CLOSE cur; DEALLOCATE cur;
UPDATE meta.Accion SET Activa = 0 WHERE Clave NOT IN (SELECT Clave FROM @a);
GO

/* La aplicación se conecta con un usuario que solo puede ejecutar procedimientos: sin acceso a tablas. */
IF DATABASE_PRINCIPAL_ID('soccer_app') IS NOT NULL
BEGIN
  GRANT EXECUTE ON SCHEMA::api TO soccer_app;
  GRANT EXECUTE ON SCHEMA::sis TO soccer_app;
  GRANT EXECUTE ON OBJECT::meta.usp_Accion_Resolver TO soccer_app;
END
GO
