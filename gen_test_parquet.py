import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

output = "sirene_44_test_snowpipe_v4.parquet"

cols = [
    'SIREN','NIC','SIRET','STATUT_DIFFUSION','DATE_CREATION_ETAB',
    'TRANCHE_EFFECTIF','ACTIVITE_PRINCIPALE_ETAB','ETABLISSEMENT_SIEGE',
    'CODE_POSTAL','COMMUNE','CODE_COMMUNE','DEPARTEMENT','CODE_DEPARTEMENT',
    'REGION','CODE_REGION','ETAT_ADMIN_ETAB','DATE_FERMETURE_ETAB',
    'DENOMINATION_UNITE_LEGALE','CATEGORIE_ENTREPRISE','ETAT_ADMIN_UL',
    'CARACTERE_EMPLOYEUR','ACTIVITE_PRINCIPALE_UL','CATEGORIE_JURIDIQUE',
    'DATE_CREATION_UL','ANNEE','MOIS','DATE_CREATION_ETAB_PARSED'
]

rows = [
    ['000000001','01','00000000100001','O',None,'Etablissement non employeur',
     '62.01Z','oui','44000','NANTES','44109','Loire-Atlantique','44',
     'Pays de la Loire','52','Actif',None,'TEST SNOWPIPE SA','PME','Active',
     'Non','62.01Z','1000','2021-01-01',2021,1,'2021-01-01'],
    ['000000002','01','00000000200001','O',None,'Etablissement non employeur',
     '47.91Z','non','44300','NANTES','44109','Loire-Atlantique','44',
     'Pays de la Loire','52','Actif',None,'TEST PIPE SARL',None,'Active',
     'Non','47.91Z','5499','2021-02-01',2021,2,'2021-02-01'],
]

df = pd.DataFrame(rows, columns=cols)

# DATE_CREATION_ETAB = NULL (jamais utilisee dans le projet)
# DATE_CREATION_UL et DATE_CREATION_ETAB_PARSED -> date32 (pas timestamp)
df['DATE_CREATION_UL']          = pd.to_datetime(df['DATE_CREATION_UL']).dt.date
df['DATE_CREATION_ETAB_PARSED'] = pd.to_datetime(df['DATE_CREATION_ETAB_PARSED']).dt.date

table = pa.Table.from_pandas(df, preserve_index=False)

print("Types PyArrow colonnes date :")
for field in table.schema:
    if 'DATE' in field.name:
        print(f"  {field.name}: {field.type}")

pq.write_table(table, output, compression='snappy')
print(f"Fichier cree : {output} ({len(df)} lignes)")
