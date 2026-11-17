# Validation and evidence index

This document connects each design requirement to its implementation and to recorded evidence. All observations come from a temporary Azure lab environment (2026-11-16), run on small sample files. The pipeline has six Execute Data Flow activities: five ingestion flows (three reference loads, two payroll loads) and one summary flow. Only the fiscal-year parameter 2020 was executed in Azure; the 2021 results were calculated locally. Numbers are in [verification_results.md](verification_results.md); screenshots are in `../evidence/screenshots/`.

## 1. Source data profile

Computed locally from the five source CSV files (which are not stored in this repository).

| File | Data rows | Notes |
|---|---|---|
| AgencyMaster.csv | 153 | `AgencyID`, `AgencyName` |
| EmpMaster.csv | 1000 | `EmployeeID`, `LastName`, `FirstName` |
| TitleMaster.csv | 1446 | one empty `TitleDescription` (NULL allowed) |
| nycpayroll_2020.csv | 100 | uses **`AgencyID`** |
| nycpayroll_2021.csv | 101 | uses **`AgencyCode`** |

Findings that shaped the design:

1. The payroll files are 100-row **samples**, not the full NYC payroll dataset.
2. Each payroll file contains one stray row outside its fiscal year (`FiscalYear = 1998` in the 2020 file, `1999` in the 2021 file). The `>= parameter` filter removes them, which also makes the filter observable in the results.
3. With parameter 2020 the summary has 25 rows (2 for 2020, 23 for 2021); with parameter 2021 it would have 23. Expected values: [expected_summary_param2020_LOCAL.csv](expected_summary_param2020_LOCAL.csv) and [expected_summary_param2021_LOCAL.csv](expected_summary_param2021_LOCAL.csv), computed from the CSVs rather than observed in Azure.
4. Negative pay components exist (1 row in 2020, 5 in 2021). They are genuine adjustments and are kept, so `TotalPaid` is net.
5. Payroll employee IDs are not present in the employee master sample, and some 2021 agency names differ from the agency master. The pipeline therefore loads each file independently, with no joins or foreign keys.
6. Files are CRLF, UTF-8, with no BOM and no commas inside values. Field lengths are well under the VARCHAR widths, and dates are `M/d/yyyy`.
7. `TotalPaid` is regular + overtime + other pay. It measures payroll expenditure, not the City's budget.
8. A storage account name cannot contain hyphens, so hyphenated names apply to the container, and the account has a hyphen-free name.

## 2. Requirements and how each was verified

| Requirement | Implementation | Evidence |
|---|---|---|
| Connect to ADLS Gen2 and Azure SQL | Linked services `ls_adls_nycpayroll` (AzureBlobFS) and `ls_sql_nycpayroll` (AzureSqlDatabase, connector version 1.0) | Connection tests `04a`, `04b`; JSON `13g`, `13h` |
| Represent every file and table as a dataset | 6 DelimitedText and 6 Azure SQL datasets, schemas imported | `05`, `05a` to `05i` |
| Load five CSV files into Azure SQL | Five mapping data flows; payroll flows cast types in a `castcols` derived column; every sink truncates | `06` series; row counts `10a`, `10j` |
| Harmonize the 2020/2021 agency identifier | Select before union maps `AgencyCode` to `AgencyID` | `07`, `07b` |
| Parameterized fiscal-year filter | `$dataflow_param_fiscalyear` driven by pipeline parameter `p_fiscalyear` | Stray 1998/1999 rows absent from the summary (`10`) |
| Null-safe `TotalPaid` including overtime | `coalesce(toDouble(...), 0)` over the three pay columns | Independent reconciliation returned zero differences (`10b`, `10c`); overtime totals `10h` |
| Aggregate by fiscal year and agency; two sinks | `agg1`, `sinkSQL` (truncate), `sinkLake` (clear folder) | SQL summary `10`, `10g`; staging files `11`, `11b` |
| Dependency-based orchestration | The three reference loads run in parallel; both payroll loads wait for all three; the summary waits for both payroll loads (`dependsOn` with `Succeeded` conditions in the pipeline JSON) | `08`, `09`; start times in `evidence/pipeline_activity_runs_2020run.csv` |
| Serverless query layer | External data source, file format, and table over `dirstaging/` | `03`, `12`, `12a`, `12b` |
| Rerun consistency | Second run of the whole pipeline | `09c`, `10j` to `10m`, `11c`, `12c` to `12e` |
| Version control | ADF Git integration to GitHub | `03c`, `13` series |
| Runnable without the original files | Synthetic example dataset with both agency-column variants; expected results computed locally, not run in Azure | [../sample-data/README.md](../sample-data/README.md) |
| No exposed secrets | Placeholders only; SAS tokens and passwords never stored | Repository scan before publishing |

## 3. Evidence index (`evidence/screenshots/`)

| Files | What they show |
|---|---|
| `00`, `01a` to `01c` | Storage account with hierarchical namespace; container folders and uploaded CSVs |
| `02`, `02a`, `02b` | Azure SQL Basic tier and the six tables |
| `03`, `03a` to `03c` | Synapse external table in the object tree; Data Factory deployed; resource group; ADF connected to GitHub |
| `04`, `04a`, `04b` | Linked services and connection tests |
| `05`, `05a` to `05i` | Datasets list, CSV previews and schemas, SQL dataset schemas |
| `06`, `06a` to `06g` | Ingestion data flows, previews, and the truncate setting on all five sinks |
| `07`, `07b` | Summary data flow, including the `AgencyCode` to `AgencyID` rename |
| `08`, `08b` | Pipeline canvas and publish list |
| `09`, `09b`, `09c` | First run and rerun in Azure Monitor |
| `10` to `10m` | Row counts, summary output, independent recomputation, quality and duplicate checks, overtime totals, rerun checks |
| `11`, `11b`, `11c` | `dirstaging` listing, part-file content, listing after the rerun |
| `12` to `12e` | Synapse queries after both runs |
| `13` series | GitHub repository and the linked service JSON files |

Result exports are in `evidence/*.csv`.

**Privacy.** Data-preview screenshots (`05a`, `05d`, `05f`, `06d3`, `06e2`) have the employee ID, last-name, and first-name columns redacted. The Git history still contains the earlier, unredacted versions of those five images: last and first names plus employee IDs, and in two of them agency start dates, boroughs, and titles, for roughly 60 employees; no pay amounts or credentials. Names, start dates, boroughs, and titles are published by the City's Office of Payroll Administration in its public Citywide Payroll Data dataset; employee IDs and title codes are not columns of that dataset. No employee-level source file is published in this repository.

## 4. Troubleshooting notes

| Symptom | Likely cause and fix |
|---|---|
| `EndpointUnsupportedAccountFeatures` when testing the ADLS linked service | The storage account was created without hierarchical namespace; create it with hierarchical namespace enabled |
| `Column not found: FiscalYear` in a data flow | The dataset schema is empty or stale: Dataset > Schema > Import schema |
| `Column not found: AgencyID` for 2021 | The 2021 file has `AgencyCode`; rename it in the Select before the union |
| `MissingRequiredPropertyException: server` from the SQL connection in a data flow | Reported with the newer SQL connector; connector version 1.0 was used here (2.0 was not tested) |
| `CREATE TABLE` fails in Synapse | The built-in serverless pool has no persistent user tables; use an external table |
| Synapse returns nulls or parse errors | Header setting vs `FIRST_ROW`, column order, or a wrong `LOCATION` |
| `CREATE DATABASE SCOPED CREDENTIAL is not supported in master` | Create and switch to a user database first |
| Duplicate rows after a rerun | A sink is not set to Truncate table / Clear the folder |
