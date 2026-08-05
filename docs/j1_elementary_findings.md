# J1 — Résultats analyse rapport Elementary

Date de l'analyse : 2026-07-31
Rapport source : `edr_target/elementary_report.html` (généré via `edr report --profile-target dev`)

## Taux de NULL exact (→ à reporter dans GOVERNANCE.md en J5)

**75,00 %** des lignes de `RAW.SIRENE_ETABLISSEMENTS` (population filtrée par le WHERE de staging : SIRET longueur 14, ANNEE != 1900, MOIS entre 1 et 12) ont un bloc de colonnes NULL simultanément.

- Population filtrée totale : 1 565 014 lignes
- Lignes concernées par l'anomalie : **1 173 753** (exactement 75,00 %)
- Vérifié par deux méthodes indépendantes et concordantes :
  - requête SQL directe sur `RAW.SIRENE_ETABLISSEMENTS`
  - `affected_rows` dans l'historique Elementary du test `not_null(etat_etablissement)` sur `stg_sirene_etablissements` (identique : 1 173 753 sur tous les runs)

Colonnes touchées par **cette même cohorte de lignes** (NULL simultanément, pas indépendamment) :
- `ETAT_ADMIN_ETAB` (etat_etablissement)
- `COMMUNE`
- `CODE_POSTAL`
- `ETABLISSEMENT_SIEGE` (est_siege)
- `STATUT_DIFFUSION`
- `CARACTERE_EMPLOYEUR` (~75,11 %, quasi la même cohorte)

Autres colonnes affectées à des taux proches mais pas identiques (cohorte plus large) :
- `DENOMINATION_UNITE_LEGALE` : 84,70 %
- `CATEGORIE_ENTREPRISE` : 87,36 %
- `DATE_FERMETURE_ETAB` : 86,04 %
- `DATE_CREATION_UL`, `ACTIVITE_PRINCIPALE_ETAB`, `ACTIVITE_PRINCIPALE_UL`, `TRANCHE_EFFECTIF`, `CATEGORIE_JURIDIQUE`, `ETAT_ADMIN_UL` : ~75 %

**Piste de cause à approfondir avant de figer le texte dans GOVERNANCE.md** : le taux reste stable à ~75 % sur chaque mois de 2020 à 2026 (pas seulement les vieux mois), donc l'hypothèse "Delta schema evolution" seule (mentionnée dans le commit `ed28b05`) n'explique pas tout — ressemble à un artefact structurel où chaque snapshot mensuel contient un sous-lot de lignes quasi vides, plutôt qu'un problème purement temporel.

**Anomalie distincte, plus grave, découverte pendant l'analyse** : `DATE_CREATION_ETAB_PARSED` est NULL à **100 %** (1 565 004 / 1 565 014) — colonne que CLAUDE.md recommande d'utiliser à la place de l'epoch cassé, mais elle est entièrement vide. Aucun test ne la surveille actuellement. À traiter séparément de l'anomalie à 75 %.

## Colonnes candidates pour les Expectation Suites (J2)

1. **`etat_etablissement`** — remplacer/compléter le test dbt `not_null` (actuellement en `warn` statique) par une expectation `expect_column_values_to_not_be_null(mostly=0.25)` : formalise le seuil de 75 % au lieu d'un warn qui ne réagirait pas si le taux dérivait au-delà.
2. **`date_creation_etab`** — aucun test actuellement alors que la colonne est NULL à 100 %. Une expectation `expect_column_values_to_not_be_null` échouerait immédiatement et rendrait visible un problème actuellement silencieux.
3. **`code_postal` / `commune`** — colonnes géographiques PII utilisées par `mart_etablissements_par_commune` (qui n'a lui-même aucun test Elementary/dbt actuellement). Bons candidats pour une expectation de format + seuil de complétude.

## Autres constats de l'analyse (contexte, non actionnable en J2/J5)

- Tests summary dernière exécution : 29 passed / 1 warn / 0 fail / 0 error sur 30 tests.
- `not_null(etat_etablissement)` : conforme, en `warn` (pas fail) — confirmé via historique : fail sur les 2 premiers runs du 2026-07-27 avant le déclassement en warn (commit `ed28b05`), warn stable depuis.
- 6 échecs historiques sur `source_accepted_values_..._ETAT_ADMIN_UL` (2026-07-27, `affected_rows=1`) — cohérent avec le piège de test documenté dans CLAUDE.md (valeur `ETAT_ADMIN_UL` copiée depuis `ETAT_ADMIN_ETAB`). Résolu depuis.
- `mart_etablissements_par_commune` : aucun test Elementary/dbt actuellement — gap de couverture (n'est pas ephemeral, contrairement à `int_etablissements_actifs`).
- `fct_etablissements` : row count actuel 391 255, sous le plafond de test `dbt_expectations_expect_table_row_count_to_be_between` (1 000–1 000 000) avec marge confortable.
