/* ============================================================
   02 · Catálogos y pesos (criterio futbolístico, ajustable sin redesplegar)
   ============================================================ */
SET NOCOUNT ON;

MERGE cat.Posicion t USING (VALUES
 (1,'POR',N'Portero','PORTERIA'),
 (2,'DFC',N'Defensa central','DEFENSA'),
 (3,'LAT',N'Lateral / carrilero','DEFENSA'),
 (4,'MCD',N'Mediocentro defensivo','MEDIO'),
 (5,'MC', N'Interior / mixto','MEDIO'),
 (6,'MCO',N'Mediapunta','MEDIO'),
 (7,'EXT',N'Extremo','ATAQUE'),
 (8,'DC', N'Delantero centro','ATAQUE')
) s(PosicionId,Clave,Nombre,Linea) ON t.PosicionId=s.PosicionId
WHEN NOT MATCHED THEN INSERT VALUES (s.PosicionId,s.Clave,s.Nombre,s.Linea);

MERGE cat.TipoEvento t USING (VALUES
 ( 1,'GOL',               N'Gol',                               'ATAQUE',  100,10,6),
 ( 2,'TIRO_PUERTA',       N'Tiro a puerta',                     'ATAQUE',   55, 7,4),
 ( 3,'REGATE',            N'Regate / 1v1 ofensivo',             'ATAQUE',   65, 6,5),
 ( 4,'DESMARQUE',         N'Desmarque / movimiento sin balón',  'ATAQUE',   50, 6,5),
 ( 5,'BALON_PARADO',      N'Balón parado (tiro libre/córner)',  'ATAQUE',   60, 5,6),
 (10,'ASISTENCIA',        N'Asistencia',                        'CREACION', 85,10,6),
 (11,'PASE_CLAVE',        N'Pase clave / entre líneas',         'CREACION', 70, 7,5),
 (12,'PASE_LARGO',        N'Pase largo',                        'CREACION', 60, 5,6),
 (13,'CAMBIO_ORIENTACION',N'Cambio de orientación',             'CREACION', 55, 5,6),
 (14,'CONTROL',           N'Control orientado / primer toque',  'CREACION', 50, 4,4),
 (15,'CONDUCCION',        N'Conducción',                        'CREACION', 55, 4,7),
 (16,'CENTRO',            N'Centro',                            'CREACION', 55, 5,5),
 (17,'SALIDA_BALON',      N'Salida de balón bajo presión',      'CREACION', 55, 5,6),
 (20,'RECUPERACION',      N'Recuperación',                      'DEFENSA',  60, 6,4),
 (21,'ENTRADA',           N'Entrada',                           'DEFENSA',  60, 5,4),
 (22,'INTERCEPCION',      N'Intercepción / anticipación',       'DEFENSA',  60, 5,4),
 (23,'DUELO_AEREO',       N'Duelo aéreo',                       'DEFENSA',  55, 5,4),
 (24,'DUELO_1V1_DEF',     N'1v1 defensivo',                     'DEFENSA',  65, 6,4),
 (25,'DESPEJE',           N'Despeje',                           'DEFENSA',  45, 4,3),
 (26,'COBERTURA',         N'Cobertura / lectura defensiva',     'DEFENSA',  55, 6,4),
 (27,'PRESION',           N'Presión tras pérdida',              'DEFENSA',  50, 5,5),
 (30,'ATAJADA',           N'Atajada',                           'PORTERIA', 80, 7,5),
 (31,'ATAJADA_1V1',       N'Atajada en mano a mano',            'PORTERIA', 90, 8,5),
 (32,'PENAL_ATAJADO',     N'Penal atajado',                     'PORTERIA', 95, 6,6),
 (33,'SALIDA_AEREA',      N'Salida aérea / corte de centro',    'PORTERIA', 65, 6,4),
 (34,'JUEGO_PIES',        N'Juego con los pies',                'PORTERIA', 60, 5,6),
 (35,'SAQUE',             N'Saque / distribución',              'PORTERIA', 50, 3,7)
) s(TipoEventoId,Clave,Nombre,Categoria,PesoBase,PreRollSeg,PostRollSeg) ON t.TipoEventoId=s.TipoEventoId
WHEN NOT MATCHED THEN INSERT VALUES (s.TipoEventoId,s.Clave,s.Nombre,s.Categoria,s.PesoBase,s.PreRollSeg,s.PostRollSeg);

/* Multiplicadores por posición. Lo no listado vale 1.00. Al sembrar, las de 1.40 o más quedan marcadas
   como "clave" (EsClave): lo que un visor espera ver en esa posición. Después EsClave se ajusta aparte. */
MERGE cat.PesoPosicionEvento t USING (
  SELECT p.PosicionId, e.TipoEventoId, v.Mult, EsClave = CAST(IIF(v.Mult >= 1.40, 1, 0) AS bit)
  FROM (VALUES
   ('POR','ATAJADA',1.50),('POR','ATAJADA_1V1',1.60),('POR','PENAL_ATAJADO',1.10),('POR','SALIDA_AEREA',1.50),
   ('POR','JUEGO_PIES',1.50),('POR','SAQUE',1.40),('POR','PASE_LARGO',1.20),('POR','GOL',0.60),
   ('DFC','DUELO_1V1_DEF',1.60),('DFC','DUELO_AEREO',1.50),('DFC','INTERCEPCION',1.50),('DFC','ENTRADA',1.40),
   ('DFC','COBERTURA',1.40),('DFC','SALIDA_BALON',1.50),('DFC','PASE_LARGO',1.30),('DFC','DESPEJE',1.20),('DFC','GOL',0.80),
   ('LAT','DUELO_1V1_DEF',1.50),('LAT','CENTRO',1.50),('LAT','CONDUCCION',1.30),('LAT','RECUPERACION',1.30),
   ('LAT','ENTRADA',1.30),('LAT','ASISTENCIA',1.20),('LAT','DESMARQUE',1.20),
   ('MCD','RECUPERACION',1.60),('MCD','INTERCEPCION',1.50),('MCD','SALIDA_BALON',1.50),('MCD','CAMBIO_ORIENTACION',1.40),
   ('MCD','COBERTURA',1.40),('MCD','ENTRADA',1.30),('MCD','CONTROL',1.30),('MCD','PRESION',1.30),
   ('MC','PASE_CLAVE',1.50),('MC','CONTROL',1.40),('MC','CAMBIO_ORIENTACION',1.40),('MC','CONDUCCION',1.30),
   ('MC','RECUPERACION',1.30),('MC','PRESION',1.30),('MC','SALIDA_BALON',1.30),('MC','ASISTENCIA',1.20),
   ('MCO','PASE_CLAVE',1.60),('MCO','ASISTENCIA',1.40),('MCO','REGATE',1.40),('MCO','CONTROL',1.40),
   ('MCO','BALON_PARADO',1.30),('MCO','TIRO_PUERTA',1.20),('MCO','GOL',1.20),
   ('EXT','REGATE',1.60),('EXT','CENTRO',1.40),('EXT','ASISTENCIA',1.40),('EXT','CONDUCCION',1.40),
   ('EXT','DESMARQUE',1.30),('EXT','GOL',1.20),('EXT','PRESION',1.20),
   ('DC','GOL',1.50),('DC','DESMARQUE',1.50),('DC','TIRO_PUERTA',1.40),('DC','CONTROL',1.30),
   ('DC','DUELO_AEREO',1.30),('DC','PRESION',1.30),('DC','ASISTENCIA',1.10)
  ) v(Pos,Ev,Mult)
  JOIN cat.Posicion p ON p.Clave=v.Pos JOIN cat.TipoEvento e ON e.Clave=v.Ev
) s ON t.PosicionId=s.PosicionId AND t.TipoEventoId=s.TipoEventoId
WHEN NOT MATCHED THEN INSERT (PosicionId, TipoEventoId, Multiplicador, EsClave) VALUES (s.PosicionId,s.TipoEventoId,s.Mult,s.EsClave);

MERGE cat.FasePartido t USING (VALUES
 ('AMISTOSO',N'Amistoso',0.85,1),('LIGA',N'Liga regular',1.00,2),('SHOWCASE',N'Torneo / showcase',1.10,3),
 ('OCTAVOS',N'Octavos',1.10,4),('CUARTOS',N'Cuartos',1.10,5),('SEMIFINAL',N'Semifinal',1.15,6),('FINAL',N'Final',1.25,7)
) s(Clave,Nombre,Factor,Orden) ON t.Clave=s.Clave
WHEN NOT MATCHED THEN INSERT VALUES (s.Clave,s.Nombre,s.Factor,s.Orden);

MERGE cat.Parametro t USING (VALUES
 ('SESION_HORAS',            168,   N'Duración de la sesión en horas'),
 ('HASH_ITERACIONES',        5000,  N'Iteraciones del hash de contraseña'),
 ('MAX_VIDEO_MB',            8192,  N'Tamaño máximo de un video'),
 ('MAX_FOTO_MB',             25,    N'Tamaño máximo de una foto'),
 ('ESCALA_TECNICA',          150,   N'Valor técnico bruto que equivale a 63 puntos (curva 0-100)'),
 ('BONO_DECISIVA',           0.25,  N'Bono si la jugada cambió o salvó el resultado'),
 ('BONO_PIE_DEBIL',          0.12,  N'Bono si se ejecutó con el pie no dominante'),
 ('BONO_TRAMO_FINAL',        0.08,  N'Bono si ocurrió del minuto 75 en adelante'),
 ('FACTOR_FALLIDA',          0.50,  N'Factor para jugadas que no terminaron bien'),
 ('PESO_GEN_TECNICO',        0.55,  N'Ranking general: peso del valor técnico'),
 ('PESO_GEN_INTERACCION',    0.35,  N'Ranking general: peso de la interacción de usuarios'),
 ('PESO_GEN_AUDIO',          0.10,  N'Ranking general: peso del pico de audio'),
 ('PESO_REC_TECNICO',        1.00,  N'Ranking reclutamiento: peso del valor técnico'),
 ('PESO_REC_INTERACCION',    0,     N'Ranking reclutamiento: peso de la interacción (popularidad; no evalúa al jugador)'),
 ('PESO_REC_AUDIO',          0,     N'Ranking reclutamiento: peso del pico de audio (favorece goles y partidos con grada)'),
 ('ENLACE_DIAS',             30,    N'Días de vigencia de un enlace para visores'),
 ('REEL_MAX_CLIPS',          25,    N'Máximo de jugadas en un reel'),
 ('REEL_MIN_CLIPS_RECOM',    12,    N'Mínimo recomendado de jugadas para un reel creíble'),
 ('REEL_PENAL_MISMO_TIPO',   0.80,  N'Penalización por cada jugada ya elegida del mismo tipo'),
 ('REEL_PENAL_MISMO_PARTIDO',0.93,  N'Penalización por cada jugada ya elegida del mismo partido'),
 ('REEL_APERTURA',           5,     N'Jugadas de apertura: las mejores van primero'),
 ('REEL_TARJETA_SEG',        4,     N'Duración de la tarjeta inicial del reel'),
 ('REEL_CONGELADO_SEG',      1.0,   N'Segundos que se congela el cuadro para señalar al jugador'),
 ('MARCA_TAMANO_DEF',        12,    N'Alto por defecto del recuadro que señala al jugador (% del alto del cuadro)'),
 ('CAND_PRE_SEG',            8,     N'Candidatos automáticos: segundos antes del pico'),
 ('CAND_POST_SEG',           4,     N'Candidatos automáticos: segundos después del pico'),
 ('CAND_MIN_USUARIOS_REP',   3,     N'Usuarios distintos que deben repetir un tramo para proponerlo')
) s(Clave,Valor,Descripcion) ON t.Clave=s.Clave
WHEN NOT MATCHED THEN INSERT VALUES (s.Clave,s.Valor,s.Descripcion);
GO
