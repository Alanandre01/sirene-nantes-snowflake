# Gouvernance des données - Projet Sirene Nantes

## Contexte réglementaire

Ce projet traite les données du registre national SIRENE (établissements Loire-Atlantique - département 44).
Ces données sont soumises au **Règlement Général sur la Protection des Données (RGPD - UE 2016/679)**.

## Base légale du traitement

| Critère | Valeur |
|---|---|
| Source | INSEE / data.gouv.fr - Open Data officiel |
| Base légale | RGPD Art. 6(1)(e) - Mission d'intérêt public |
| Responsable de traitement | Alan André - Projet portfolio Data Engineering |
| Contact RGPD | alanandre19@gmail.com |

---

## Données personnelles identifiées (PII)

| Colonne staging | Colonne RAW source | Type | Traitement appliqué |
|---|---|---|---|
| `denomination` | `DENOMINATION_UNITE_LEGALE` | Nom personne physique (EI) | Exclu si `STATUT_DIFFUSION = 'P'` + anonymisé Art.17 |
| `code_postal` | `CODE_POSTAL` | Localisation | Conservé pour agrégats géographiques communes |
| `commune` | `LIBELLE_COMMUNE` | Localisation | Conservé pour agrégats |
| `code_commune` | `CODE_COMMUNE_ETABLISSEMENT` | Identifiant géo | Conservé |
| `siret` | `SIRET` | Identifiant établissement | Pseudonymisé via surrogate key MD5 dans `fct_etablissements` |
| `siren` | `SIREN` | Identifiant entreprise | Pseudonymisé via surrogate key MD5 dans `fct_etablissements` |
| `date_creation_etab` | `DATE_CREATION_ETAB_PARSED` | Date événement | Conservée - utile analytiquement |
| `date_creation_ul` | `DATE_CREATION_UL` | Date événement | Conservée |

> **Marquage dans dbt** : toutes les colonnes PII sont taguées `meta: {pii: true}` dans les fichiers `schema.yml`.
> Le lineage dbt permet de tracer chaque colonne PII de la source RAW jusqu'aux marts.

---

## Règles de diffusion SIRENE

| Valeur `statut_diffusion` | Signification | Traitement dans le pipeline |
|---|---|---|
| `O` | Données publiques diffusables | Inclus dans tous les modèles |
| `P` | Entrepreneur individuel - droit d'opposition exercé (RGPD Art. 21) | **Exclu** dès la couche `int_etablissements_actifs` (ephemeral CTE) |
| `[ND]` / vide | Non diffusé INSEE | Converti en `NULL` via la macro `clean_nd` en staging |

---

## Politique de rétention

| Couche | Schéma Snowflake | Table | Time Travel | Justification |
|---|---|---|---|---|
| RAW | `ALAN_DW.RAW` | `SIRENE_ETABLISSEMENTS` | 7 jours | Correction d'erreurs d'ingestion Snowpipe |
| STAGING | `ALAN_DW.DBT_DEV_STAGING` | `STG_SIRENE_ETABLISSEMENTS` (view) | - | Vue - pas de rétention |
| MARTS | `ALAN_DW.DBT_DEV_MARTS` | `FCT_ETABLISSEMENTS` | 7 jours | Modèle incrémental principal |
| MARTS | `ALAN_DW.DBT_DEV_MARTS` | `MART_ETABLISSEMENTS_PAR_COMMUNE` | 7 jours | Agrégats - risque PII minimal |
| LOG | `ALAN_DW.RAW` | `RGPD_AUDIT_LOG` | 30 jours | Preuve de conformité (accountability Art. 5(2)) |

---

## Droits des personnes (RGPD Art. 15–22)

### Droit à l'effacement (Art. 17)

La procédure stockée versionnée dans [sql/governance/rgpd_procedures.sql](sql/governance/rgpd_procedures.sql) anonymise les champs PII d'un SIREN et trace l'action :

```sql
-- Déclencher depuis Snowflake Worksheet (rôle SYSADMIN)
CALL ALAN_DW.RAW.ANONYMISER_ETABLISSEMENT(
    '123456789',                    -- SIREN de l'entreprise
    'Exercice droit Art.17 RGPD',   -- Motif
    'alanandre19@gmail.com'         -- Demandeur
);
```

Champs effacés : `CODE_POSTAL`, `DENOMINATION_UNITE_LEGALE` → `'[EFFACE]'`, `STATUT_DIFFUSION` → `'P'`.
L'action est automatiquement tracée dans `ALAN_DW.RAW.RGPD_AUDIT_LOG`.

### Droit d'accès (Art. 15)

```sql
SELECT SIREN, SIRET, STATUT_DIFFUSION, DENOMINATION_UNITE_LEGALE, CODE_POSTAL
FROM ALAN_DW.RAW.SIRENE_ETABLISSEMENTS
WHERE SIREN = '123456789';
```

### Suivi du journal d'audit RGPD

```sql
SELECT LOG_ID, ACTION, SIREN_CONCERNE, NB_LIGNES_MODIFIEES,
       MOTIF, DEMANDEUR, EFFECTUE_PAR, EFFECTUE_LE, STATUT, COMMENTAIRE
FROM ALAN_DW.RAW.RGPD_AUDIT_LOG
ORDER BY EFFECTUE_LE DESC;
```

---

## Contrôle d'accès (RBAC Snowflake)

| Rôle Snowflake | Droits | Usage |
|---|---|---|
| `SYSADMIN` | DDL + DML complet | Administration, exécution des procédures RGPD |
| `TRANSFORMER` | SELECT RAW + DDL/DML STAGING/MARTS | dbt CI/CD (GitHub Actions) |
| `ANALYST` | SELECT MARTS uniquement | Consommation analytique BI |

---

## Sécurité

- Credentials Snowflake dans des **variables d'environnement système Windows** - jamais en dur dans le code
- `~/.dbt/profiles.yml` listé dans `.gitignore` - jamais commis dans Git
- Secrets CI/CD dans les **GitHub Actions Secrets** du repo (jamais dans le code source)
- Valeurs manquantes encodées `[ND]` nettoyées via la macro `clean_nd` avant toute persistance
- Filtre `STATUT_DIFFUSION != 'P'` appliqué au niveau ephemeral pour garantir l'exclusion en amont des marts

---

## Pièges de conformité connus

| Piège | Règle appliquée |
|---|---|
| `DATE_CREATION_ETAB` (epoch microsecondes) | Ne jamais utiliser - remplacée par `DATE_CREATION_ETAB_PARSED` en staging |
| `ANNEE = 1900` (sentinelle année inconnue) | Filtré `WHERE ANNEE != 1900` en staging |
| `MOIS` hors 1–12 (ex. `99`) | Filtré `WHERE MOIS BETWEEN 1 AND 12` en staging |
| SIRET mal formé (< 14 chiffres) | Filtré `WHERE LENGTH(CAST(SIRET AS VARCHAR)) = 14` en staging |

---

## Anomalies de qualité documentées

> Mesures issues du rapport Elementary (`edr report`, M4-S1-J1, voir
> [docs/j1_elementary_findings.md](docs/j1_elementary_findings.md)) et de
> requêtes SQL directes sur `ALAN_DW.RAW.SIRENE_ETABLISSEMENTS`, revérifiées
> le 2026-08-05 (M4-S1-J5) sur la population filtrée par le `WHERE` de staging
> (`LENGTH(SIRET) = 14`, `ANNEE != 1900`, `MOIS` entre 1 et 12 — 1 565 014 lignes).

### NULL structurel 75,00 % sur les colonnes métier

**Colonnes concernées** : `etat_etablissement`, `commune`, `code_postal`,
`etablissement_siege`, `statut_diffusion`, `caractere_employeur`

**Taux mesuré** : 75,00 % — 1 173 753 lignes sur 1 565 014.
Taux stable sur tous les millésimes 2020–2026.

**Hypothèse causale (avec nuance)** : Probable artefact de schema evolution
Delta non rétroactif côté Databricks — colonnes ajoutées postérieurement
au chargement initial, sans rétroaction sur les lignes déjà écrites.
*Nuance* : la stabilité inter-millésimes (même taux observé de 2020 à 2026)
contredit partiellement cette hypothèse, qui devrait produire un taux plus
élevé sur les lignes les plus anciennes. Cause définitive non établie.

**Décision opérationnelle** :
- Test dbt `not_null` sur `etat_etablissement` maintenu à `severity: warn`
  (commit `ed28b05`, M3-S3-J3 — poussé sur GitHub en M4-S1-J5).
- Expectation GE `expect_column_values_to_not_be_null` avec `mostly=0.25`
  sur `ETAT_ETABLISSEMENT`, classifiée `WARN_EXPECTATIONS` dans le Checkpoint
  `sirene_checkpoint_dag06` de `dag_06` (non bloquante).
- Aucune action corrective planifiée — anomalie structurelle, pas un bug pipeline.

### `date_creation_etab_parsed` NULL à 100 %

**Taux mesuré** : 100 % — 1 565 004 lignes sur 1 565 014 (colonne quasi
entièrement vide en staging ; 10 lignes non-NULL résiduelles, négligeables).

**Cause identifiée** : `TRY_TO_DATE()` dans `stg_sirene_etablissements.sql`
échoue silencieusement sur le format epoch microsecondes brut de
`DATE_CREATION_ETAB` (RAW). Retour NULL systématique, sans erreur levée.

**Décision opérationnelle** :
- Colonne `date_creation_etab` (staging, alimentée depuis `DATE_CREATION_ETAB_PARSED`)
  maintenue dans le schéma staging (contrat d'interface stable).
- Non utilisée dans les modèles intermédiaires ou marts.
- Conversion correcte à implémenter : `TO_TIMESTAMP(DATE_CREATION_ETAB / 1000000)::DATE`
- Expectation GE stricte (sans `mostly`) sur `DATE_CREATION_ETAB` classifiée
  `WARN_EXPECTATIONS` dans `dag_06` — visible dans Data Docs, non bloquante.

### `code_postal` NULL 79,15 % — deux causes indépendantes et additives

**Taux mesuré** : 79,15 % — 1 238 688 lignes sur 1 565 014 (supérieur aux 75 %
ci-dessus). Décomposition vérifiée par requête SQL directe, exhaustive et sans
résidu inexpliqué :

| Cause | Lignes | Part |
|---|---|---|
| Cohorte structurelle 75 % (`etat_etablissement` NULL) | 1 173 753 | 75,00 % |
| Filtre RGPD Art. 21 (`statut_diffusion = 'P'`) | 64 935 | 4,15 % |
| **Total `code_postal` NULL** | **1 238 688** | **79,15 %** |

**Causes** :
1. Artefact structurel (~75 %) — identique à la cohorte ci-dessus.
2. Restriction RGPD Art. 21 : le filtre `statut_diffusion = 'O'` dans
   `int_etablissements_actifs` exclut des marts les établissements à diffusion
   restreinte (`statut_diffusion = 'P'`) — la totalité de ces 64 935 lignes a un
   `CODE_POSTAL` manquant en RAW, sans exception.

**Dimension RGPD** : Le surplus de NULL issu de la population `P` est
intentionnel et attendu — il ne s'agit pas d'un phénomène résiduel marginal
mais d'une cohorte entière (64 935 lignes, 4,15 points de plus que la cohorte
structurelle). Documenté ici pour prévenir toute interprétation erronée lors
d'un audit de conformité : ce n'est pas une anomalie à corriger.

**Décision opérationnelle** : Expectation GE `mostly=0.25` sur `CODE_POSTAL`,
classifiée `WARN_EXPECTATIONS` dans `dag_06` (non bloquante).
