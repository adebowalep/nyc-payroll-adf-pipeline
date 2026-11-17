# Portfolio summary: NYC Payroll Analytics Pipeline

Content for a project card or case-study page. Every statement is supported by this repository; see the links at the bottom.

## Portfolio title

NYC Payroll Analytics Pipeline

## Short description

An end-to-end Azure data engineering pipeline that ingests NYC payroll CSV files, harmonizes two fiscal years with different schemas, computes null-safe agency-level payroll totals, and exposes the results through Azure SQL Database and Azure Synapse serverless SQL. Correctness was verified independently across services, and a second pipeline run confirmed that reruns do not create duplicates.

## Technologies

Azure Data Factory (pipelines, mapping data flows, Git integration) · Azure Data Lake Storage Gen2 · Azure SQL Database · Azure Synapse Analytics (built-in serverless SQL pool, external tables) · T-SQL · GitHub · draw.io (architecture diagram)

## My engineering contributions

- Built five CSV-to-SQL mapping data flows, with explicit type casting of dates and numeric columns, and a sixth summary data flow that normalizes schemas, unions two years, filters by a fiscal-year parameter, computes `TotalPaid`, aggregates by agency and year, and writes to two destinations.
- Orchestrated six data flow activities in one pipeline with `Succeeded` dependencies: three parallel reference loads, then two parallel payroll loads, then the summary.
- Set up a Synapse serverless query layer (external data source, file format, external table) over the staged CSV output.
- Designed and ran the validation: row-count checks, independent SQL and CSV recomputation, duplicate and null checks, a cross-service comparison, and a rerun test.
- Documented the architecture, decisions, results, limitations, and reproduction steps.

## Main technical challenge

Producing a summary that can be trusted. The 2020 and 2021 files name the agency column differently, and null-safe arithmetic means a column accidentally dropped upstream becomes zero instead of an error. A Select that omitted overtime for one year was caught in review before the first run. This is why the project relies on independent reconciliation rather than on pipeline success status.

## Technical highlights

1. **Independent verification:** summary totals matched a fresh SQL aggregation of the source tables (zero discrepancies), a separate calculation from the raw CSV files, and the Synapse external table over the staged files.
2. **Rerun consistency:** a second run produced identical counts, totals, and Synapse results because the SQL sinks truncate and the ADLS sink clears its folder.
3. **Dependency-based orchestration:** parallel where independent, strictly ordered where data depends on earlier loads; confirmed by Azure Monitor start times.
4. **Schema harmonization:** `AgencyCode` mapped to `AgencyID` before a union by name, followed by a parameterized fiscal-year filter.
5. **Null-safe, adjustment-preserving calculation:** `coalesce` on each pay component; negative adjustments kept so totals reflect net pay.

## Result

In the verified run, all 6 pipeline activities succeeded and the summary contained 25 rows (2 for FiscalYear 2020, 23 for 2021) with a sample total of 35,709,510.43. The row counts of every loaded table matched the source files, the reconciliation returned no differences, there were no duplicate summary keys, and the Synapse external table returned the same values. Results were unchanged after a second run.

## Limitations

Built and validated in a temporary Azure lab on small sample files (100 payroll rows per year), so the figures are not representative of the full NYC payroll dataset, and the pipeline is not a continuously running service.

## Recommended visuals for the case-study page

1. `docs/images/architecture.svg` (or `architecture.png`): lead image.
2. `evidence/screenshots/08_pipeline_canvas.png`: pipeline orchestration.
3. `evidence/screenshots/07_dataflow_summary.png`: the summary transformation.
4. `evidence/screenshots/10b_reconciliation_zero_rows.png`: independent reconciliation (empty result means no discrepancies).
5. Optional: `evidence/screenshots/09c_rerun_success.png` for the rerun.

## Links

- Repository: https://github.com/adebowalep/nyc-payroll-adf-pipeline
- Results: [verification_results.md](verification_results.md)
- Design reference: [dataflow-expressions.md](dataflow-expressions.md)
- Requirements and evidence: [validation-and-evidence.md](validation-and-evidence.md)

No live demo is linked: the Azure resources used for this project were temporary and no longer exist.
