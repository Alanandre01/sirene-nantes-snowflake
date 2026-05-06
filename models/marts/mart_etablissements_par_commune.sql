-- Matérialisé en TABLE (défini dans dbt_project.yml)
-- Source : int_etablissements_actifs (ephemeral → injecté en CTE)
-- Agrégation : établissements actifs par commune et catégorie

WITH actifs AS (

    -- dbt injecte ici le contenu de int_etablissements_actifs
    SELECT * FROM {{ ref('int_etablissements_actifs') }}

),

par_commune AS (

    SELECT
        commune,
        code_postal,
        code_commune,
        code_departement,

        -- Catégorie entreprise (PME, ETI, GE, ou null)
        COALESCE(categorie_entreprise, 'Non renseignée') AS categorie_entreprise,

        -- Comptages
        COUNT(*)                                       AS nb_etablissements,
        SUM(CASE WHEN est_siege THEN 1 ELSE 0 END)    AS nb_sieges,
        SUM(CASE WHEN est_employeur = 'Oui'
                   THEN 1 ELSE 0 END)                 AS nb_employeurs,

        -- Ancienneté moyenne (utilise date_creation_etab parsée)
        AVG(
            DATEDIFF('year',
                date_creation_etab,
                CURRENT_DATE()
            )
        )                                              AS anciennete_moy_annees,

        -- Code NAF dominant (valeur arbitraire du groupe — Snowflake n'a pas MODE())
        ANY_VALUE(code_naf_etab)                       AS naf_dominant,

        -- Snapshot
        annee_snapshot,
        mois_snapshot

    FROM actifs
    WHERE commune IS NOT NULL
    GROUP BY
        commune, code_postal, code_commune,
        code_departement, categorie_entreprise,
        annee_snapshot, mois_snapshot

)

SELECT * FROM par_commune
ORDER BY nb_etablissements DESC
