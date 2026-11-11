/* Datos de demostración: una temporada, equipos, partidos y plantel. No trae videos. */
SET NOCOUNT ON;
IF EXISTS (SELECT 1 FROM fut.Temporada) RETURN;

INSERT fut.Temporada(Nombre, FechaInicio, FechaFin, Activa) VALUES (N'2026-2027', '2026-08-01', '2027-06-30', 1);
DECLARE @t int = SCOPE_IDENTITY();

INSERT fut.Equipo(Nombre, Categoria, EsPropio) VALUES
 (N'Halcones FC', N'Sub-17', 1), (N'Atlético Norte', N'Sub-17', 0), (N'Real Cantera', N'Sub-17', 0),
 (N'Deportivo Sur', N'Sub-17', 0), (N'Academia Élite', N'Sub-17', 0);
DECLARE @h int = (SELECT EquipoId FROM fut.Equipo WHERE Nombre = N'Halcones FC');
UPDATE fut.Equipo SET ContactoNombre = N'Coordinación de visorías', ContactoCargo = N'Coordinador deportivo',
       ContactoCorreo = N'visorias@halconesfc.example.com', ContactoTelefono = N'+52 55 5550 0100' WHERE EquipoId = @h;

INSERT fut.Partido(TemporadaId, Fecha, Jornada, Competencia, Fase, EquipoLocalId, EquipoVisitaId, GolesLocal, GolesVisita, NivelRival)
SELECT @t, v.Fecha, v.Jornada, v.Comp, v.Fase, IIF(v.Local = 1, @h, e.EquipoId), IIF(v.Local = 1, e.EquipoId, @h), v.GL, v.GV, v.Nivel
FROM (VALUES
 ('2026-09-05', 1, N'Liga Regional', 'LIGA',      1, N'Atlético Norte', 2, 1, 3),
 ('2026-09-19', 3, N'Liga Regional', 'LIGA',      0, N'Deportivo Sur',  0, 0, 2),
 ('2026-10-10', 6, N'Liga Regional', 'LIGA',      1, N'Real Cantera',   3, 2, 4),
 ('2026-10-24', NULL, N'Copa Showcase', 'SHOWCASE',  0, N'Academia Élite', 1, 2, 5),
 ('2026-11-07', NULL, N'Liga Regional', 'SEMIFINAL', 1, N'Real Cantera',   1, 0, 4)
) v(Fecha, Jornada, Comp, Fase, Local, Rival, GL, GV, Nivel)
JOIN fut.Equipo e ON e.Nombre = v.Rival;

INSERT fut.Jugador(Nombre, Apellidos, FechaNacimiento, PosicionId, PosicionSecundariaId, PieDominante, EstaturaCm, PesoKg, Dorsal,
                   EquipoId, AnioGraduacion, PromedioAcademico, CorreoContacto, TelefonoContacto, Bio)
SELECT v.Nombre, v.Apellidos, v.Nac, p.PosicionId, p2.PosicionId, v.Pie, v.Est, v.Peso, v.Dorsal, @h, v.Grad, v.Prom, v.Correo, v.Tel, v.Bio
FROM (VALUES
 (N'Diego',   N'Ramírez Soto',  '2009-03-14', 'DC',  'EXT', 'D', 181, 72,  9, 2027, 9.1, N'diego.ramirez@example.com', N'+52 55 5550 0101', N'Delantero de área con buen juego de espaldas.'),
 (N'Mateo',   N'López Herrera', '2009-07-02', 'MC',  'MCO', 'I', 174, 66,  8, 2027, 8.7, N'mateo.lopez@example.com',   NULL,               N'Interior zurdo, organiza y llega al área.'),
 (N'Santiago',N'Cruz Medina',   '2010-01-21', 'DFC', NULL,  'D', 186, 78,  4, 2028, 8.9, NULL,                         NULL,               NULL),
 (N'Emiliano',N'Vega Ruiz',     '2009-11-09', 'POR', NULL,  'D', 188, 80,  1, 2027, 9.4, N'emiliano.vega@example.com', N'+52 55 5550 0104', N'Portero con buen juego de pies.'),
 (N'Leonardo',N'Flores Díaz',   '2010-05-30', 'EXT', 'LAT', 'D', 170, 63, 11, 2028, NULL, NULL,                        NULL,               NULL)
) v(Nombre, Apellidos, Nac, Pos, Pos2, Pie, Est, Peso, Dorsal, Grad, Prom, Correo, Tel, Bio)
JOIN cat.Posicion p ON p.Clave = v.Pos LEFT JOIN cat.Posicion p2 ON p2.Clave = v.Pos2;
GO
