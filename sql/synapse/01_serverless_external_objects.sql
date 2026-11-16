-- =====================================================================
-- Synapse Analytics  --  BUILT-IN SERVERLESS SQL POOL ONLY
-- No dedicated pool (DW100c) is created. No CREATE TABLE is used.
-- Run in Synapse Studio > Develop > SQL script, Connect to: Built-in.
-- Run this ONLY AFTER the pipeline has written files into dirstaging
-- (inspect the real files first - see docs/checklist).
-- Replace every <PLACEHOLDER>. Never commit real keys/SAS tokens.
-- =====================================================================

-- STEP A  (run while "Use database" = master)
-- You cannot create objects in master, so create a user database:
-- CREATE DATABASE udacity;
-- Then REFRESH the database dropdown, select "udacity", and run STEP B+.

-- STEP B  (database = udacity)
-- Needed once before creating a credential:
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<STRONG-PASSWORD-NOT-COMMITTED>';
GO

-- STEP C  Credential so serverless can read YOUR storage account.
-- Option 1 (simplest, works across storage accounts): SAS token.
--   Portal > Storage account > Shared access signature (read+list, container+object,
--   short expiry). Paste WITHOUT the leading '?'.
-- Option 2: grant the Synapse workspace managed identity "Storage Blob Data Reader"
--   on the storage account and use IDENTITY = 'Managed Identity' (if the lab allows
--   role assignments).
IF NOT EXISTS (SELECT * FROM sys.database_scoped_credentials WHERE name = 'cred_nycpayroll')
    CREATE DATABASE SCOPED CREDENTIAL cred_nycpayroll
    WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
         SECRET   = '<SAS-TOKEN-WITHOUT-QUESTION-MARK>';
GO

-- STEP D  External data source = the CONTAINER (file system), not the account.
-- <CONTAINER> and <STORAGE_ACCOUNT> are the exact names from the Portal.
IF NOT EXISTS (SELECT * FROM sys.external_data_sources WHERE name = 'ds_nycpayroll_lake')
    CREATE EXTERNAL DATA SOURCE ds_nycpayroll_lake
    WITH ( LOCATION   = 'https://<STORAGE_ACCOUNT>.dfs.core.windows.net/<CONTAINER>',
           CREDENTIAL = cred_nycpayroll );
GO

-- STEP E  File format. MUST match how ADF writes the files:
--   * Recommended ADF sink dataset: DelimitedText, comma, NO header row,
--     UTF-8, no quote surprises  ->  FIRST_ROW = 1 (default).
--   * If you instead keep "First row as header" ON in the sink dataset, change
--     FIRST_ROW to 2 (requires PARSER_VERSION = '2.0').
IF NOT EXISTS (SELECT * FROM sys.external_file_formats WHERE name = 'SynapseDelimitedTextFormat')
    CREATE EXTERNAL FILE FORMAT SynapseDelimitedTextFormat
    WITH ( FORMAT_TYPE = DELIMITEDTEXT,
           FORMAT_OPTIONS ( FIELD_TERMINATOR = ',',
                            STRING_DELIMITER = '"',
                            FIRST_ROW        = 1,
                            USE_TYPE_DEFAULT = FALSE ) );
GO

-- STEP F  The external table (schema = Udacity's, column ORDER = ADF aggregate output order).
-- LOCATION is the folder inside the container where the ADF sink writes.
-- Do NOT point at a single filename: ADF writes part-* files.
IF OBJECT_ID(N'dbo.NYC_Payroll_Summary', N'U') IS NULL
   AND NOT EXISTS (SELECT * FROM sys.external_tables WHERE name = 'NYC_Payroll_Summary')
    CREATE EXTERNAL TABLE dbo.NYC_Payroll_Summary (
        [FiscalYear] int          NULL,
        [AgencyName] varchar(50)  NULL,
        [TotalPaid]  float        NULL
    )
    WITH ( LOCATION     = 'dirstaging/',
           DATA_SOURCE  = ds_nycpayroll_lake,
           FILE_FORMAT  = SynapseDelimitedTextFormat );
GO

-- STEP G  Verify. Compare to the Azure SQL summary (must match; see docs).
SELECT * FROM dbo.NYC_Payroll_Summary ORDER BY FiscalYear, AgencyName;
SELECT COUNT(*) AS row_count, SUM(TotalPaid) AS grand_total FROM dbo.NYC_Payroll_Summary;
-- Debug helper: see raw lines + which part-file they came from
-- SELECT TOP 20 r.filepath() AS part_file, r.*
-- FROM OPENROWSET(BULK 'dirstaging/', DATA_SOURCE='ds_nycpayroll_lake',
--                 FORMAT='CSV', PARSER_VERSION='2.0') WITH (line varchar(500) 1) AS r;
