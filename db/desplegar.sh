#!/usr/bin/env bash
# Despliega la base de datos (idempotente: se puede correr en cada versión).
# Uso: SA_PASSWORD=... APP_PASSWORD=... ADMIN_CORREO=... ADMIN_CLAVE=... db/desplegar.sh [--demo]
# Variables opcionales: SQL_SERVER (localhost), SQL_DB (Soccer), SQLCMD (ruta a sqlcmd),
#                       SQL_CONTENEDOR (nombre del contenedor docker donde vive sqlcmd)
set -euo pipefail
cd "$(dirname "$0")"
: "${SA_PASSWORD:?Define SA_PASSWORD}" "${APP_PASSWORD:?Define APP_PASSWORD}"
SQL_SERVER="${SQL_SERVER:-localhost}"; SQL_DB="${SQL_DB:-Soccer}"

if [[ -n "${SQL_CONTENEDOR:-}" ]]; then
  correr() { docker exec -i "$SQL_CONTENEDOR" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -b -I "$@"; }
else
  correr() { "${SQLCMD:-sqlcmd}" -S "$SQL_SERVER" -U sa -P "$SA_PASSWORD" -C -b -I "$@"; }
fi

echo "· base de datos y usuario de aplicación"
correr -v DB="$SQL_DB" APP_PASSWORD="$APP_PASSWORD" <<'SQL'
IF DB_ID('$(DB)') IS NULL CREATE DATABASE [$(DB)];
GO
IF SUSER_ID('soccer_app') IS NULL CREATE LOGIN soccer_app WITH PASSWORD = '$(APP_PASSWORD)', CHECK_POLICY = OFF;
ELSE ALTER LOGIN soccer_app WITH PASSWORD = '$(APP_PASSWORD)';
GO
USE [$(DB)];
IF DATABASE_PRINCIPAL_ID('soccer_app') IS NULL CREATE USER soccer_app FOR LOGIN soccer_app;
GO
SQL

for f in 0*.sql; do
  echo "· $f"
  correr -d "$SQL_DB" < "$f"
done

if [[ -n "${ADMIN_CORREO:-}" && -n "${ADMIN_CLAVE:-}" ]]; then
  echo "· administrador inicial"
  correr -d "$SQL_DB" -v CORREO="$ADMIN_CORREO" CLAVE="$ADMIN_CLAVE" <<'SQL'
IF NOT EXISTS (SELECT 1 FROM seg.Usuario WHERE Correo = LOWER('$(CORREO)'))
  EXEC seg.usp_Usuario_Guardar NULL, '$(CORREO)', N'Administrador', 3, N'$(CLAVE)', 1;
SQL
fi

if [[ "${1:-}" == "--demo" ]]; then
  echo "· datos de demostración"
  correr -d "$SQL_DB" < demo.sql
fi
echo "Listo."
