{{ config(materialized='view') }}

WITH source AS (
    SELECT * FROM {{ source('raw', 'sirene_etablissements') }}
),

cleaned AS (
    SELECT
        -- Identifiants
        CAST(SIREN AS VARCHAR(9))                          AS siren,
        CAST(NIC   AS VARCHAR(5))                          AS nic,
        CAST(SIRET AS VARCHAR(14))                         AS siret,

        -- Dates — DATE_CREATION_ETAB (epoch µs) ignoré intentionnellement
        TRY_TO_DATE(DATE_CREATION_ETAB_PARSED)             AS date_creation_etab,
        TRY_TO_DATE(DATE_FERMETURE_ETAB)                   AS date_fermeture_etab,
        TRY_TO_DATE(DATE_CREATION_UL)                      AS date_creation_ul,

        -- Statut
        ETAT_ADMIN_ETAB                                    AS etat_etablissement,
        ETABLISSEMENT_SIEGE = 'oui'                        AS est_siege,
        {{ clean_nd('STATUT_DIFFUSION') }}                 AS statut_diffusion,

        -- Activité
        ACTIVITE_PRINCIPALE_ETAB                           AS code_naf_etab,
        ACTIVITE_PRINCIPALE_UL                             AS code_naf_ul,
        {{ clean_nd('TRANCHE_EFFECTIF') }}                 AS tranche_effectif,
        {{ clean_nd('CATEGORIE_ENTREPRISE') }}             AS categorie_entreprise,
        CAST(CATEGORIE_JURIDIQUE AS VARCHAR)               AS categorie_juridique,
        CARACTERE_EMPLOYEUR                                AS est_employeur,

        -- Localisation
        {{ clean_nd('CODE_POSTAL') }}                      AS code_postal,
        {{ clean_nd('COMMUNE') }}                          AS commune,
        CODE_COMMUNE                                       AS code_commune,
        CODE_DEPARTEMENT                                   AS code_departement,
        DEPARTEMENT                                        AS departement,
        CODE_REGION                                        AS code_region,
        REGION                                             AS region,

        -- Unité légale
        {{ clean_nd('DENOMINATION_UNITE_LEGALE') }}        AS denomination,
        ETAT_ADMIN_UL                                      AS etat_unite_legale,

        -- Partition temporelle
        CAST(ANNEE AS INTEGER)                             AS annee_snapshot,
        CAST(MOIS  AS INTEGER)                             AS mois_snapshot

    FROM source

    WHERE LENGTH(CAST(SIRET AS VARCHAR)) = 14
      AND CAST(ANNEE AS INTEGER) != 1900
      AND CAST(MOIS  AS INTEGER) BETWEEN 1 AND 12
)

SELECT * FROM cleaned
