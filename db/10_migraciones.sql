/* ============================================================
   10 · Migraciones de datos: cada bloque se aplica una sola vez en bases ya desplegadas
   ============================================================ */
SET NOCOUNT ON;
IF NOT EXISTS (SELECT 1 FROM meta.Migracion WHERE Clave = '001_criterio_visoria')
BEGIN
  -- El ranking de reclutamiento deja de contar popularidad y ruido: solo el valor técnico
  UPDATE cat.Parametro SET Valor = IIF(Clave = 'PESO_REC_TECNICO', 1, 0)
  WHERE Clave IN ('PESO_REC_TECNICO', 'PESO_REC_INTERACCION', 'PESO_REC_AUDIO');

  -- "Clave" pasa a ser una bandera propia; se inicia con el criterio anterior (multiplicador >= 1.40)
  UPDATE cat.PesoPosicionEvento SET EsClave = IIF(Multiplicador >= 1.40, 1, 0);
  -- Atajar un penal tiene mucho de azar: no se le puede exigir a un portero como evidencia
  UPDATE ppe SET Multiplicador = 1.10, EsClave = 0
  FROM cat.PesoPosicionEvento ppe JOIN cat.Posicion p ON p.PosicionId = ppe.PosicionId JOIN cat.TipoEvento e ON e.TipoEventoId = ppe.TipoEventoId
  WHERE p.Clave = 'POR' AND e.Clave = 'PENAL_ATAJADO';
  -- La distribución sí es de lo primero que se le evalúa
  UPDATE ppe SET Multiplicador = 1.40, EsClave = 1
  FROM cat.PesoPosicionEvento ppe JOIN cat.Posicion p ON p.PosicionId = ppe.PosicionId JOIN cat.TipoEvento e ON e.TipoEventoId = ppe.TipoEventoId
  WHERE p.Clave = 'POR' AND e.Clave = 'SAQUE';

  -- El enlace único y sin caducidad de cada reel se convierte en un enlace con 30 días de vigencia
  IF COL_LENGTH('hl.Reel', 'TokenPublico') IS NOT NULL
  BEGIN
    EXEC('INSERT hl.ReelEnlace(ReelId, Token, Destinatario, ExpiraEn, CreadoPor)
          SELECT ReelId, TokenPublico, N''Enlace anterior'', DATEADD(day, 30, SYSUTCDATETIME()), CreadoPor
          FROM hl.Reel WHERE TokenPublico IS NOT NULL');
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Reel_Token') EXEC('DROP INDEX UX_Reel_Token ON hl.Reel');
    EXEC('ALTER TABLE hl.Reel DROP COLUMN TokenPublico');
  END
  INSERT meta.Migracion(Clave) VALUES ('001_criterio_visoria');
END
GO
