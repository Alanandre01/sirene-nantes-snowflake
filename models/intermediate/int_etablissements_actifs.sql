-- EPHEMERAL : aucun objet créé dans Snowflake
-- Injecté comme CTE dans les modèles marts qui utilisent ref()
{{
  config(materialized='ephemeral')
}}

SELECT
    siret,
    siren,
    nic,
    date_creation_etab,
    date_fermeture_etab,
    date_creation_ul,
    etat_etablissement,
    est_siege,
    code_naf_etab,
    code_naf_ul,
    tranche_effectif,
    categorie_entreprise,
    categorie_juridique,
    est_employeur,
    code_postal,
    commune,
    code_commune,
    code_departement,
    denomination,
    etat_unite_legale,
    annee_snapshot,
    mois_snapshot

FROM {{ ref('stg_sirene_etablissements') }}

WHERE
    etat_etablissement = 'Actif'
    -- Exclure les établissements à diffusion restreinte
    AND statut_diffusion = 'O'
