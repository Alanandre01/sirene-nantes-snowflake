-- ============================================================
-- RGPD Art. 17 - Procédure d'anonymisation par SIREN
-- Projet : Sirene Nantes | Snowflake : ALAN_DW.RAW
-- ============================================================

-- 1. Table de log (idempotent)
CREATE TABLE IF NOT EXISTS ALAN_DW.RAW.RGPD_AUDIT_LOG (
    LOG_ID                  NUMBER AUTOINCREMENT PRIMARY KEY,
    ACTION                  VARCHAR(50)   NOT NULL,
    SIREN_CONCERNE          VARCHAR(9),
    NB_LIGNES_MODIFIEES     INTEGER       DEFAULT 0,
    MOTIF                   VARCHAR(500),
    DEMANDEUR               VARCHAR(200),
    EFFECTUE_PAR            VARCHAR(100)  DEFAULT CURRENT_USER(),
    EFFECTUE_LE             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    STATUT                  VARCHAR(20)   DEFAULT 'SUCCES',
    COMMENTAIRE             VARCHAR(1000)
)
DATA_RETENTION_TIME_IN_DAYS = 30;

-- 2. Procédure d'anonymisation
CREATE OR REPLACE PROCEDURE ALAN_DW.RAW.ANONYMISER_ETABLISSEMENT(
    P_SIREN     VARCHAR,
    P_MOTIF     VARCHAR,
    P_DEMANDEUR VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'RGPD Art.17 - Anonymisation par SIREN - Log dans RGPD_AUDIT_LOG'
AS
$$
DECLARE
    nb_lignes INTEGER;
    message   VARCHAR;
BEGIN
    -- Effacement des champs PII (meta: {pii: true} dans schema.yml)
    -- Seuls les établissements pas encore anonymisés (STATUT_DIFFUSION != 'P') sont touchés
    UPDATE ALAN_DW.RAW.SIRENE_ETABLISSEMENTS
    SET
        CODE_POSTAL               = '[EFFACE]',
        STATUT_DIFFUSION          = 'P',
        DENOMINATION_UNITE_LEGALE = '[EFFACE]'
    WHERE SIREN = :P_SIREN
      AND STATUT_DIFFUSION != 'P';

    nb_lignes := SQLROWCOUNT;

    INSERT INTO ALAN_DW.RAW.RGPD_AUDIT_LOG (
        ACTION, SIREN_CONCERNE, NB_LIGNES_MODIFIEES,
        MOTIF, DEMANDEUR, STATUT, COMMENTAIRE
    ) VALUES (
        'ANONYMISATION', :P_SIREN, :nb_lignes, :P_MOTIF, :P_DEMANDEUR,
        CASE WHEN :nb_lignes > 0 THEN 'SUCCES' ELSE 'PARTIEL' END,
        CASE WHEN :nb_lignes > 0
            THEN 'Anonymisation effectuee : ' || :nb_lignes || ' etablissement(s)'
            ELSE 'SIREN introuvable ou deja anonymise'
        END
    );

    RETURN CASE
        WHEN nb_lignes > 0
            THEN 'SIREN ' || P_SIREN || ' anonymise (' || nb_lignes || ' ligne(s))'
        ELSE 'SIREN ' || P_SIREN || ' introuvable ou deja anonymise'
    END;
END;
$$;

-- ============================================================
-- Exemples d'utilisation
-- ============================================================

-- Anonymiser un SIREN sur demande d'exercice du droit à l'effacement :
-- CALL ALAN_DW.RAW.ANONYMISER_ETABLISSEMENT(
--     '123456789',
--     'Demande Art.17 - email recu le 2026-05-17',
--     'alanandre19@gmail.com'
-- );

-- Consulter le journal d'audit :
-- SELECT * FROM ALAN_DW.RAW.RGPD_AUDIT_LOG
-- ORDER BY EFFECTUE_LE DESC;

-- Vérifier qu'un SIREN est bien anonymisé :
-- SELECT SIREN, STATUT_DIFFUSION, CODE_POSTAL, DENOMINATION_UNITE_LEGALE
-- FROM ALAN_DW.RAW.SIRENE_ETABLISSEMENTS
-- WHERE SIREN = '123456789';
