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
