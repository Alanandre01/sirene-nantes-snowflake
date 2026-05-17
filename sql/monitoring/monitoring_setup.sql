-- =============================================================
-- monitoring_setup.sql
-- Snowflake Task de monitoring volume - Projet Sirene 44
-- Rôle requis : SYSADMIN
-- =============================================================

USE ROLE SYSADMIN;
USE DATABASE ALAN_DW;
USE SCHEMA RAW;
USE WAREHOUSE ALAN_WH;

-- Table de monitoring
CREATE TABLE IF NOT EXISTS alan_dw.raw.monitoring_volume (
    check_date           DATE          NOT NULL,
    table_name           VARCHAR(100)  NOT NULL,
    total_rows           INTEGER,
    rows_actifs          INTEGER,
    rows_fermes          INTEGER,
    rows_statut_p        INTEGER,
    pct_nd_code_postal   FLOAT,
    checked_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Vue 7 derniers jours
CREATE OR REPLACE VIEW alan_dw.raw.v_monitoring_derniers_7j AS
SELECT *
FROM   alan_dw.raw.monitoring_volume
WHERE  check_date >= DATEADD('day', -7, CURRENT_DATE())
ORDER BY check_date DESC;

-- Task nuitamment 5h Paris
CREATE OR REPLACE TASK task_monitoring_volume
    WAREHOUSE = ALAN_WH
    SCHEDULE  = 'USING CRON 0 5 * * * Europe/Paris'
AS
INSERT INTO alan_dw.raw.monitoring_volume
    (check_date, table_name, total_rows, rows_actifs,
     rows_fermes, rows_statut_p, pct_nd_code_postal)
SELECT
    CURRENT_DATE(),
    'sirene_etablissements',
    COUNT(*),
    SUM(CASE WHEN ETAT_ADMIN_ETAB = 'Actif'  THEN 1 ELSE 0 END),
    SUM(CASE WHEN ETAT_ADMIN_ETAB = 'Fermé'  THEN 1 ELSE 0 END),
    SUM(CASE WHEN STATUT_DIFFUSION = 'P'      THEN 1 ELSE 0 END),
    ROUND(100.0 * SUM(CASE WHEN CODE_POSTAL = '[ND]'
                      OR  CODE_POSTAL IS NULL
                      THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 2)
FROM alan_dw.raw.sirene_etablissements;

ALTER TASK task_monitoring_volume RESUME;
