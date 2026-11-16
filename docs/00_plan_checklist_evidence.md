# NYC Payroll pipelines: rubric checklist and evidence register

All statuses below were observed in a temporary Udacity Azure lab on 2026-11-16. Screenshots are in `evidence/screenshots/`; numbers are in [verification_results.md](verification_results.md). The lab resources are deleted when the session ends.

## 1. About the data (computed locally from the five CSV files)

| File | Data rows | Notes |
|---|---|---|
| AgencyMaster.csv | 153 | AgencyID, AgencyName |
| EmpMaster.csv | 1000 | EmployeeID, LastName, FirstName |
| TitleMaster.csv | 1446 | one empty TitleDescription (NULL allowed) |
| nycpayroll_2020.csv | 100 | uses **AgencyID** |
| nycpayroll_2021.csv | 101 | uses **AgencyCode** |

1. These are 100-row **sample** files, not the full NYC payroll data.
2. One stray row per file: `FiscalYear=1998` (2020 file) and `1999` (2021 file). The `>= parameter` filter removes them.
3. With parameter 2020 the summary has 25 rows (2 for 2020, 23 for 2021); with 2021 it would have 23. Expected values computed from the CSVs: `expected_summary_param2020_LOCAL.csv` and `expected_summary_param2021_LOCAL.csv` (not from Azure).
4. Negative pay components exist (1 row in 2020, 5 in 2021). They are kept, so `TotalPaid` is net.
5. Payroll employee IDs do not exist in EmpMaster, and some 2021 agency names differ from AgencyMaster, so there are no joins or foreign keys.
6. `TotalPaid` = RegularGrossPaid + TotalOTPaid + TotalOtherPay. It is payroll expenditure, not the City's budget.
7. A storage account name cannot contain hyphens, so the hyphenated name from the instructions is used for the **container**, and the account has a hyphen-free name.

## 2. Rubric checklist

| # | Criterion | Status and evidence |
|---|---|---|
| 1 | AzureBlobFS linked service to ADLS Gen2 | PASS. `linkedService/ls_adls_nycpayroll.json` (type AzureBlobFS); Connection successful (04a). |
| 2 | AzureSqlDatabase linked service | PASS. `linkedService/ls_sql_nycpayroll.json` (type AzureSqlDatabase, Version 1.0); Connection successful (04b); all SQL sinks ran. |
| 3 | Datasets for AgencyMaster, TitleMaster, EmpMaster, 2021 and 2020 CSVs | PASS. 5 DelimitedText datasets, previews parsed (05a to 05g). |
| 4 | SQL table datasets (agency, emp, title, 2020, 2021, summary) | PASS. 6 Azure SQL datasets with imported schemas (05h, 05i) plus the staging sink dataset. |
| 5 | Data flows moving ADLS data to Azure SQL | PASS. 5 flows (agency, emp, title, payroll2020, payroll2021), all ran (06 series). |
| 6 | Union, parameterized filter, TotalPaid, aggregate, two sinks | PASS. `dataflow_summary` (07, 07b); results reconciled (10 series). |
| 7 | Pipeline with ExecuteDataFlow activities, correct order, successful run | PASS. `pl_nycpayroll_main`, dependencies verified in the JSON and by start times (08, 09). |
| 8 | Data verification in SQL, ADLS and Synapse | PASS. SQL summary reconciled to the CSVs; `dirstaging` part files checked; Synapse external table returns the same 25 rows (10 to 12 series). |
| 9 | GitHub integration and repo contents | PASS. ADF connected to GitHub (main); datasets, data flows, linked services, pipeline and factory JSON committed (13 series). |
| 10 | Safe, documented configuration | PASS. No keys, tokens, passwords or connection strings with secrets in the repo; the Synapse script uses placeholders only. |
| Extra | Rerun safety | PASS. A second run left counts, totals and Synapse results unchanged and replaced the `dirstaging` files (09c, 10j to 10m, 11c, 12c to 12e). |

## 3. Evidence register (files in `evidence/screenshots/`)

| Files | What they show |
|---|---|
| 00, 01a to 01c | Storage account with hierarchical namespace; container folders and uploaded CSVs |
| 02, 02a, 02b | Azure SQL Basic tier and the 6 tables |
| 03, 03a to 03c | Synapse external table in the tree; ADF deployed; resource group; ADF connected to GitHub |
| 04, 04a, 04b | Linked services and successful connection tests |
| 05, 05a to 05i | Datasets list, CSV previews and schemas, SQL dataset schemas |
| 06, 06a to 06g | Ingestion data flows, previews and Truncate settings on all 5 sinks |
| 07, 07b | Summary data flow with the AgencyCode to AgencyID rename |
| 08, 08b | Pipeline canvas and publish list |
| 09, 09b, 09c | First run and rerun in Monitor |
| 10 to 10m | Row counts, summary, independent recomputation, quality and duplicate checks, overtime, rerun checks |
| 11, 11b, 11c | `dirstaging` listing, part file content, after the rerun |
| 12 to 12e | Synapse queries (first run and rerun) |
| 13 series | GitHub repo folders and the linked service JSON files |

## 4. Troubleshooting quick map

| Symptom | Check first |
|---|---|
| `EndpointUnsupportedAccountFeatures` | Hierarchical namespace not enabled on the storage account |
| Column not found `FiscalYear` | Dataset > Schema > Import schema |
| Column not found `AgencyID` in 2021 | Rename `AgencyCode` in the Select before the union |
| `MissingRequiredPropertyException: server` | SQL linked service Version 1.0 (the course's "Legacy") |
| Synapse CREATE TABLE fails | Serverless pool: use an external table |
| Synapse nulls or parse errors | Header setting vs `FIRST_ROW`, column order, wrong LOCATION |
| Duplicates after a rerun | Sinks need Truncate table / Clear the folder |
| `CREATE DATABASE SCOPED CREDENTIAL is not supported in master` | Switch the script to the `udacity` database first |
