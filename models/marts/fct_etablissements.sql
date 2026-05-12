{{
  config(
    materialized         = 'incremental',
    unique_key           = 'etablissement_sk',
    incremental_strategy = 'merge',
    on_schema_change     = 'sync_all_columns'
  )
}}

WITH staged AS (
    SELECT * FROM {{ ref('stg_sirene_etablissements') }}
),

enriched AS (
    SELECT
        -- Partition temporelle — calculée en premier car utilisée dans la SK
        annee_snapshot,
        mois_snapshot,
        CAST(annee_snapshot AS VARCHAR) || '-' ||
        LPAD(CAST(mois_snapshot AS VARCHAR), 2, '0')  AS partition_annee_mois,

        -- Clé de substitution : hash stable sur (siret x partition)
        {{ dbt_utils.generate_surrogate_key(['siren', 'nic', 'partition_annee_mois']) }}
            AS etablissement_sk,

        -- Identifiants métier
        siret,
        siren,
        nic,

        -- Statut courant
        etat_etablissement,
        est_siege,
        etat_etablissement = 'Actif'                  AS est_actif,
        statut_diffusion,

        -- Activité économique
        code_naf_etab,
        code_naf_ul,
        tranche_effectif,
        est_employeur,

        -- Dimension géographique
        code_postal,
        commune,
        code_commune,
        departement,
        code_departement,
        region,
        code_region,

        -- Entité légale
        denomination,
        categorie_entreprise,
        etat_unite_legale,
        categorie_juridique,

        -- Dates (DATE_CREATION_ETAB_PARSED utilisé, jamais DATE_CREATION_ETAB)
        date_creation_etab,
        date_fermeture_etab,
        date_creation_ul,

        -- Métadonnées dbt
        CURRENT_TIMESTAMP()                           AS dbt_loaded_at

    FROM staged
    WHERE annee_snapshot IS NOT NULL
      AND mois_snapshot BETWEEN 1 AND 12
)

SELECT * FROM enriched

-- LOGIQUE INCREMENTALE
-- Ignoré au premier run (table inexistante) et avec --full-refresh.
-- On ne retraite que les partitions ANNEE-MOIS strictement plus récentes
-- que la dernière déjà présente dans la table cible.
{% if is_incremental() %}
WHERE partition_annee_mois > (
    SELECT MAX(partition_annee_mois)
    FROM {{ this }}
)
{% endif %}
