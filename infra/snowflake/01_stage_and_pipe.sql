-- Stage et Pipe Snowpipe -- ALAN_DW.RAW
-- Prerequis : Storage Integration s3_int_sirene cree par ACCOUNTADMIN
-- Executer avec SYSADMIN

USE ROLE SYSADMIN;
USE DATABASE ALAN_DW;
USE SCHEMA RAW;
USE WAREHOUSE ALAN_WH;

CREATE OR REPLACE STAGE stg_s3_sirene
  STORAGE_INTEGRATION = s3_int_sirene
  URL = 's3://alan-data-lake-fr/raw/sirene/'
  FILE_FORMAT = (
    TYPE = PARQUET
    SNAPPY_COMPRESSION = TRUE
    NULL_IF = ()
  )
  COMMENT = 'Stage S3 SIRENE etablissements -- Parquet Snappy -- eu-west-1';

CREATE OR REPLACE PIPE alan_dw.raw.pipe_sirene_etablissements
  AUTO_INGEST = TRUE
  COMMENT = 'Ingestion auto Parquet S3 -> RAW.SIRENE_ETABLISSEMENTS via SQS'
AS
  COPY INTO alan_dw.raw.sirene_etablissements
  FROM @alan_dw.raw.stg_s3_sirene
  FILE_FORMAT = (TYPE = PARQUET SNAPPY_COMPRESSION = TRUE)
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  ON_ERROR = 'CONTINUE'
  PURGE = FALSE;
