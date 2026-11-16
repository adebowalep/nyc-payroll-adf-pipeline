# NYC Payroll Data Integration Pipelines (Azure)

Status: pipeline built and run once in a temporary Udacity lab (parameter `p_fiscalyear = 2020`). Results below were observed in that run. The lab resources are deleted when the session expires, so only the repo and screenshots remain.

## Architecture

```
ADLS Gen2 (dirpayrollfiles, dirhistoryfiles)
      | 5 mapping data flows (CSV -> SQL)
      v
Azure SQL DB  db_nycpayroll  (3 master, 2020, 2021 tables)
      | dataflow_summary: union 2020+2021 -> filter FiscalYear >= param
      |                   -> TotalPaid -> aggregate (FiscalYear, AgencyName)
      +--> dbo.NYC_Payroll_Summary (Azure SQL, truncate)
      +--> ADLS dirstaging (CSV part-files, clear folder)
                 ^
                 | external table (Synapse built-in serverless SQL pool)
```

Orchestrated by ADF pipeline `pl_nycpayroll_main`: Agency / Emp / Title (parallel) -> Payroll 2020 / 2021 (parallel) -> Summary.

## Repository layout

| Path | Content |
|---|---|
| `sql/azure_sql/` | table DDL (rerunnable) and validation queries |
| `sql/synapse/` | serverless external objects (no CREATE TABLE) |
| `docs/` | plan/checklist/evidence register, data-flow expressions, locally computed expected results |
| `evidence/screenshots/` | screenshots from real runs |
| ADF JSON folders (`dataset/`, `dataflow/`, `pipeline/`, `linkedService/`) | added by ADF GitHub integration |

## Execution order

1. Create resources, upload CSVs, run `01_create_tables.sql`.
2. Linked services, datasets, data flows, pipeline (see `docs/dataflow-expressions.md`). Publish.
3. Trigger pipeline with `dataflow_param_fiscalyear` (2020 or 2021).
4. Run `02_validation_queries.sql`, then the Synapse script.

## Key design decisions

- 2021 uses `AgencyCode`; it is renamed to `AgencyID` in a Select before the Union.
- Fiscal year filter is applied after the Union, with an integer parameter.
- `TotalPaid` is null-safe (`coalesce`) and includes negative adjustments.
- Reruns are safe: SQL sinks truncate, the staging sink clears its folder.
- Synapse serverless reads the `dirstaging` folder, never a single hard-coded part file.
- `TotalPaid` is payroll expenditure, not the City's total budget.

## Security

No keys, passwords or SAS tokens are stored in this repo. Placeholders are in `<ANGLE_BRACKETS>`. The ADF linked service JSON files contain only the server and database names, the SQL login name, and ADF's `encryptedCredential` metadata; no password or account key is readable. For anything beyond a throwaway lab, use Azure Key Vault references for secrets.

## Known lab constraints

Temporary Udacity sandbox (10 attempts, resources deleted on expiry), built-in serverless pool only (no dedicated pool), one Synapse workspace per account.

## Verified results

Full details: [docs/verification_results.md](docs/verification_results.md). Screenshots: `evidence/screenshots/`.

- Pipeline `pl_nycpayroll_main`: all 6 data flow activities succeeded; start times show the three master loads in parallel, both payroll loads after them, and the summary last.
- Azure SQL row counts match the CSV files: Agency 153, Employee 1000, Title 1446, Payroll 2020 = 100, Payroll 2021 = 101.
- `dbo.NYC_Payroll_Summary`: 25 rows (2 for FiscalYear 2020, 23 for 2021), total 35,709,510.43. Every row matches an independent calculation from the source CSVs, and an in-database reconciliation query returned 0 rows.
- Rerun test: a second run of the same pipeline left every row count, the summary and the Synapse results unchanged, and `dirstaging` was cleared and rewritten (no duplicates).
- The stray FiscalYear 1998 and 1999 rows in the sample files are removed by the parameterized filter.
- Synapse serverless external table over `dirstaging/` returns the same 25 rows and total.
- Data caveat: the CSV files are 100-row samples, and `TotalPaid` is payroll expenditure (regular + overtime + other pay, including negative adjustments), not the City's budget.

## Deviations from the course text (and why)

- Azure SQL linked service uses Version 1.0 (the current UI name for the course's "Legacy").
- The pipeline passes the fiscal year through a pipeline parameter (`p_fiscalyear`) instead of a global parameter.
- Synapse uses the built-in serverless pool and an external table; no dedicated pool and no CREATE TABLE.
- All five ingestion sinks use Truncate table so reruns do not duplicate rows (screenshots confirm each one).
