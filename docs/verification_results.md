# Verified results (observed in the Udacity lab, 2026-11-16)

Only results actually seen in Azure are listed.

## Pipeline run
- Pipeline `pl_nycpayroll_main`, trigger now, `p_fiscalyear = 2020`.
- All 6 activities Succeeded (evidence/screenshots/09_*, evidence/pipeline_activity_runs_2020run.csv).
- Order proven by start times: agency, emp, title started together (20:07:00); both payroll flows started at 20:11:42, one second after the slowest master finished; `dataflow_summary` started at 20:14:47, one second after `dataflow_payroll2020` finished.

## Azure SQL row counts after the run
| Table | Rows | Matches CSV |
|---|---|---|
| NYC_Payroll_AGENCY_MD | 153 | yes |
| NYC_Payroll_EMP_MD | 1000 | yes |
| NYC_Payroll_TITLE_MD | 1446 | yes |
| NYC_Payroll_Data_2020 | 100 | yes |
| NYC_Payroll_Data_2021 | 101 | yes |

## Summary table `dbo.NYC_Payroll_Summary` (parameter 2020)
- 25 rows: 2 for FiscalYear 2020, 23 for 2021. Totals 6,837,400.28 and 28,872,110.15 (sum 35,709,510.43).
- Every row equals the total computed independently from the CSV files (difference below 0.01) and from the SQL source tables (reconciliation query returned 0 rows).
- The stray FiscalYear 1998 and 1999 rows are not in the summary (filter works).
- Null cells: 0. Duplicate (FiscalYear, AgencyName) keys: 0. Negative totals: 0. Duplicate (EmployeeID, PayrollNumber) in source tables: 0.

## Overtime (TotalOTPaid in source tables)
| FiscalYear | TotalOTPaid | OTHours |
|---|---|---|
| 1998 (stray row) | 0 | 0 |
| 1999 (stray row) | 102,184.53 | 1,085.25 |
| 2020 | 335,504.15 | 7,278 |
| 2021 | 9,272,589.25 | 101,589.65 |

Overtime is about 4.9% of TotalPaid for 2020 and about 32.1% for 2021 in these **sample files** (100 rows per file, a few agencies). Do not generalize these to the City as a whole. `TotalPaid` is payroll expenditure, not the City's budget.

## ADLS `dirstaging` (after the run)
- 25 objects: `_SUCCESS`, one 0-byte `part-00000-...csv`, and 23 non-empty part files of 33 to 91 bytes (many small files, as expected from Spark partitioning).
- Part-file content checked (part-00010, 91 B): two lines, comma-separated, no header row, e.g. `2021,COMMUNITY COLLEGE (QUEENSBORO),297484.08` (evidence/screenshots/11b_dirstaging_part_file_content.png). Matches `FIRST_ROW = 1` in the Synapse file format.

## Rerun test (second run of the same pipeline, `p_fiscalyear = 2020`)
- Second run started 21:47:13 and all 6 activities Succeeded (same order: masters, then payrolls at 21:51:31, summary at 21:51:53).
- Azure SQL after the rerun: row counts unchanged (153 / 1000 / 1446 / 100 / 101); summary 25 rows, total 35,709,510.43; reconciliation query 0 rows; duplicate summary keys 0 rows; duplicate source keys 0 rows.
- `dirstaging` after the rerun: still 25 objects, all with new names and timestamps (21:52:21 to 21:52:32), so "Clear the folder" removed the first run's files (no accumulation).
- Synapse after the rerun: 25 rows, total 35,709,510.43000001 (floating-point rounding only), 0 duplicate keys, OPENROWSET read 25 lines.
- Conclusion: a rerun does not create duplicates (the SQL sinks truncate, the lake sink clears the folder).
- Evidence: 09c, 10j, 10j2, 10k, 10l, 10m, 11c, 12c, 12d, 12e in evidence/screenshots/.

## Synapse built-in serverless SQL pool (database `udacity`)
- External data source over the container (SAS credential, read and list only), external file format (comma, no header, `FIRST_ROW = 1`), external table `dbo.NYC_Payroll_Summary` with `LOCATION = 'dirstaging/'`. No dedicated pool and no CREATE TABLE.
- OPENROWSET over `dirstaging/*.csv` read **25 lines**.
- `SELECT * FROM dbo.NYC_Payroll_Summary` returned **25 rows**; `COUNT(*) = 25`, `SUM(TotalPaid) = 35,709,510.43`.
- Compared with the Azure SQL summary export: same 25 keys, maximum absolute difference 0.0.
- Evidence: evidence/screenshots/12_*.png, evidence/synapse_external_table_result.csv.
