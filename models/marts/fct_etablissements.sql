{{
  config(
    materialized         = 'incremental',
    unique_key           = ['siret', 'partition_annee_mois'],
    incremental_strategy = 'merge',
    on_schema_change     = 'sync_all_columns'
  )
}}

WITH staged AS (
    SELECT * FROM {{ ref('stg_sirene_etablissements') }}
),

enriched AS (
    SELECT
        siret,
        siren,
        nic,

        date_creation_etab,
        date_fermeture_etab,
        date_creation_ul,

        etat_etablissement,
        etat_etablissement = 'Actif'                  AS est_actif,
        est_siege,
        statut_diffusion,

        code_naf_etab,
        code_naf_ul,
        tranche_effectif,
        est_employeur,

        code_postal,
        commune,
        code_commune,
        departement,
        code_departement,
        region,
        code_region,

        denomination,
        categorie_entreprise,
        etat_unite_legale,
        categorie_juridique,

        annee_snapshot,
        mois_snapshot,
        CAST(annee_snapshot AS VARCHAR) || '-' ||
        LPAD(CAST(mois_snapshot AS VARCHAR), 2, '0')  AS partition_annee_mois,

        CURRENT_TIMESTAMP()                           AS loaded_at

    FROM staged
    WHERE annee_snapshot IS NOT NULL
      AND mois_snapshot BETWEEN 1 AND 12
)

SELECT * FROM enriched

{% if is_incremental() %}
WHERE partition_annee_mois > (
    SELECT MAX(partition_annee_mois)
    FROM {{ this }}
)
{% endif %}
