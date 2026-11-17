# Verification results

Results observed in a temporary Azure lab environment on 2026-11-16, with the pipeline run at `p_fiscalyear = 2020`. Only results actually seen in Azure, or computed locally from the source CSV files, are listed. The source files are small samples, so every figure describes this dataset only.

## How the output was verified

Run status alone was not accepted as proof of correctness. The summary was checked from independent directions:

| # | Check | Method |
|---|---|---|
| 1 | Load completeness | Row counts of every Azure SQL table compared with the row counts of the source CSV files |
| 2 | Aggregation logic, inside Azure | A separate SQL query re-aggregated the two source tables and was compared with the pipeline's summary table using a `FULL OUTER JOIN`; any missing, extra, or differing (above 0.01) row would be returned |
| 3 | Aggregation logic, outside Azure | The raw CSV files were aggregated by a separate local script; every summary row was compared with the exported Azure SQL result |
| 4 | Data quality | Null cells, duplicate summary keys, negative totals, and duplicate source keys |
| 5 | Cross-service consistency | The Synapse serverless external table (reading the staged CSV files) compared with the Azure SQL summary table |
| 6 | Rerun consistency | The whole pipeline run a second time and checks 1 to 5 repeated |

The expected values computed from the CSV files are stored in `expected_summary_param2020_LOCAL.csv` and `expected_summary_param2021_LOCAL.csv`. The 2021 file is a local calculation only; the pipeline was not executed with 2021.

## Pipeline run

- Pipeline `pl_nycpayroll_main`, triggered with `p_fiscalyear = 2020`.
- All 6 activities succeeded (`evidence/screenshots/09_*`, `evidence/pipeline_activity_runs_2020run.csv`).
- Order confirmed by start times: agency, employee, and title loads started together (20:07:00); both payroll loads started at 20:11:42, one second after the slowest reference load finished; `dataflow_summary` started at 20:14:47, one second after `dataflow_payroll2020` finished.

## Azure SQL row counts after the run

| Table | Rows | Matches source CSV |
|---|---|---|
| NYC_Payroll_AGENCY_MD | 153 | yes |
| NYC_Payroll_EMP_MD | 1000 | yes |
| NYC_Payroll_TITLE_MD | 1446 | yes |
| NYC_Payroll_Data_2020 | 100 | yes |
| NYC_Payroll_Data_2021 | 101 | yes |

The 1,000-row preview limit of the ADF debug view had initially shown 1,000 title rows. The pipeline run itself loaded all 1,446.

## Summary table `dbo.NYC_Payroll_Summary` (parameter 2020)

- 25 rows: 2 for FiscalYear 2020, 23 for 2021. Totals 6,837,400.28 and 28,872,110.15 (sum 35,709,510.43).
- Every row equals the total computed independently from the CSV files (difference below 0.01) and from the SQL source tables (reconciliation query returned 0 rows).
- The stray FiscalYear 1998 and 1999 rows present in the sample files are not in the summary, which confirms the filter.
- Null cells: 0. Duplicate (FiscalYear, AgencyName) keys: 0. Negative totals: 0. Duplicate (EmployeeID, PayrollNumber) keys in the source tables: 0.

## Overtime (`TotalOTPaid` in the source tables)

| FiscalYear | TotalOTPaid | OTHours |
|---|---|---|
| 1998 (stray row) | 0 | 0 |
| 1999 (stray row) | 102,184.53 | 1,085.25 |
| 2020 | 335,504.15 | 7,278 |
| 2021 | 9,272,589.25 | 101,589.65 |

Overtime is about 4.9% of `TotalPaid` for 2020 and about 32.1% for 2021 in these sample files (100 rows per file, a few agencies). These ratios do not generalize to the City as a whole. `TotalPaid` is payroll expenditure, not the City's budget.

## ADLS `dirstaging`

- 25 objects after the first run: a `_SUCCESS` marker, one 0-byte `part-00000-...csv`, and 23 non-empty part files of 33 to 91 bytes (many small files, as expected from Spark partitioning).
- Part-file content checked (`part-00010`, 91 B): two lines, comma-separated, no header row, for example `2021,COMMUNITY COLLEGE (QUEENSBORO),297484.08` (`evidence/screenshots/11b_dirstaging_part_file_content.png`). This matches `FIRST_ROW = 1` in the Synapse file format.

## Rerun test (second run, `p_fiscalyear = 2020`)

- The second run started at 21:47:13 and all 6 activities succeeded in the same order (payroll loads at 21:51:31, summary at 21:51:53).
- Azure SQL after the rerun: row counts unchanged (153 / 1000 / 1446 / 100 / 101); summary 25 rows, total 35,709,510.43; reconciliation query 0 rows; duplicate summary keys 0 rows; duplicate source keys 0 rows.
- `dirstaging` after the rerun: still 25 objects, all with new names and timestamps (21:52:21 to 21:52:32), so the sink's "Clear the folder" removed the first run's files.
- Synapse after the rerun: 25 rows, total 35,709,510.43000001 (floating-point rounding only), 0 duplicate keys, `OPENROWSET` read 25 lines.
- Conclusion: in this test, rerunning the pipeline did not create duplicate rows (SQL sinks truncate; the lake sink clears its folder). This is demonstrated rerun consistency for this batch-rebuild design, not a general idempotency guarantee.
- Evidence: `09c`, `10j`, `10j2`, `10k`, `10l`, `10m`, `11c`, `12c`, `12d`, `12e` in `evidence/screenshots/`.

## Synapse built-in serverless SQL pool

- The user database was named `udacity` in the lab; any non-default name works, since serverless pools do not allow objects in `master`.
- External data source over the container (SAS credential, read and list only), external file format (comma-delimited, no header, `FIRST_ROW = 1`), and external table `dbo.NYC_Payroll_Summary` with `LOCATION = 'dirstaging/'`. No dedicated pool and no `CREATE TABLE`.
- `OPENROWSET` over `dirstaging/*.csv` read **25 lines**.
- `SELECT * FROM dbo.NYC_Payroll_Summary` returned **25 rows**; `COUNT(*) = 25`, `SUM(TotalPaid) = 35,709,510.43`.
- Compared with the Azure SQL summary export: the same 25 keys and a maximum absolute difference of 0.0.
- Evidence: `evidence/screenshots/12_*.png`, `evidence/synapse_external_table_result.csv`.

## Not tested

- Any `p_fiscalyear` value other than 2020 was not run in Azure.
- Failure paths (a failed activity stopping downstream activities) were not exercised; the behavior follows from the `Succeeded` dependency conditions in the pipeline JSON.
- No load, scale, cost, or performance measurements were taken.
- The data are small samples; behavior on the full NYC payroll dataset was not evaluated.
