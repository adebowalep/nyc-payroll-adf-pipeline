-- =====================================================================
-- Azure Synapse Analytics: BUILT-IN SERVERLESS SQL POOL
-- Query layer over the CSV files that dataflow_summary writes to ADLS
-- (dirstaging/). No dedicated SQL pool and no CREATE TABLE: serverless
-- pools hold metadata only, so the table is an EXTERNAL table.
--
-- Run in Synapse Studio > Develop > SQL script, Connect to: Built-in.
-- Run AFTER the pipeline has written files to dirstaging/, and run each
-- numbered section separately, checking its result before the next.
-- These statements were executed in this order and verified (25 rows,
-- total 35,709,510.43; see docs/verification_results.md).
--
-- Replace every <PLACEHOLDER>. Never commit a real SAS token or password.
-- =====================================================================

-- 0) Create a user database (objects cannot be created in master).
--    Run while the script is connected to master, then refresh the database
--    list and switch the script to the new database. Each script tab has its
--    own database selection. The lab database was named "udacity".
--    Confirm with: SELECT DB_NAME();
-- CREATE DATABASE udacity;

-- 1) Master key (required before creating a database scoped credential).
--    Use a new strong password, stored in a password manager.
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<STRONG-PASSWORD-NOT-COMMITTED>';

-- 2) Credential that lets serverless read the storage account.
--    SAS token generated for Blob service, resource types Container + Object,
--    permissions Read + List only, short expiry, HTTPS only. Paste the token
--    WITHOUT the leading '?'.
--    Alternative: grant the workspace managed identity "Storage Blob Data
--    Reader" on the storage account and use IDENTITY = 'Managed Identity'.
CREATE DATABASE SCOPED CREDENTIAL cred_nycpayroll
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
     SECRET   = '<SAS-TOKEN-WITHOUT-QUESTION-MARK>';

-- 3) External data source = the CONTAINER (file system), not the account.
CREATE EXTERNAL DATA SOURCE ds_nycpayroll_lake
WITH ( LOCATION   = 'https://<STORAGE_ACCOUNT>.dfs.core.windows.net/<CONTAINER>',
       CREDENTIAL = cred_nycpayroll );

-- 4) Sanity check before creating the table: can serverless read the files?
--    Expected: one line per aggregate row (25 in the verified run).
SELECT COUNT(*) AS lines_read
FROM OPENROWSET(
        BULK 'dirstaging/*.csv',
        DATA_SOURCE = 'ds_nycpayroll_lake',
        FORMAT = 'CSV',
        PARSER_VERSION = '2.0'
     ) WITH (c1 VARCHAR(200) 1) AS r;

-- 5) File format. It must match how ADF writes the files:
--    comma-delimited, NO header row (ds_csv_staging_summary has
--    firstRowAsHeader = false), so FIRST_ROW = 1. If the header were turned
--    on in the sink dataset, use FIRST_ROW = 2.
CREATE EXTERNAL FILE FORMAT SynapseDelimitedTextFormat
WITH ( FORMAT_TYPE = DELIMITEDTEXT,
       FORMAT_OPTIONS ( FIELD_TERMINATOR = ',',
                        STRING_DELIMITER = '"',
                        FIRST_ROW        = 1,
                        USE_TYPE_DEFAULT = FALSE ) );

-- 6) External table. Column order = the aggregate output order of
--    dataflow_summary (FiscalYear, AgencyName, TotalPaid). LOCATION is the
--    folder, not a file name: ADF writes many part-*.csv files, and files
--    whose names start with '_' (such as _SUCCESS) are ignored.
CREATE EXTERNAL TABLE dbo.NYC_Payroll_Summary (
    [FiscalYear] INT         NULL,
    [AgencyName] VARCHAR(50) NULL,
    [TotalPaid]  FLOAT       NULL
)
WITH ( LOCATION    = 'dirstaging/',
       DATA_SOURCE = ds_nycpayroll_lake,
       FILE_FORMAT = SynapseDelimitedTextFormat );

-- 7) Verify. Compare with dbo.NYC_Payroll_Summary in Azure SQL Database.
SELECT * FROM dbo.NYC_Payroll_Summary ORDER BY FiscalYear, AgencyName;

SELECT COUNT(*) AS row_count, SUM(TotalPaid) AS grand_total
FROM dbo.NYC_Payroll_Summary;

SELECT FiscalYear, AgencyName, COUNT(*) AS c
FROM dbo.NYC_Payroll_Summary
GROUP BY FiscalYear, AgencyName
HAVING COUNT(*) > 1;            -- expect 0 rows
