# Mapping data flow and pipeline design reference

This document describes the Azure Data Factory objects in this repository: names, settings, and the expressions used. It reflects the exported definitions in `pipeline/`, `dataflow/`, `dataset/`, and `linkedService/`, and the implementation that was executed in a temporary Azure lab on sample files and validated (see [verification_results.md](verification_results.md)). Only `p_fiscalyear = 2020` was executed in Azure.

## Object names

| Type | Name |
|---|---|
| Linked service (ADLS Gen2) | `ls_adls_nycpayroll` (type AzureBlobFS, account-key authentication) |
| Linked service (Azure SQL) | `ls_sql_nycpayroll` (type AzureSqlDatabase, SQL authentication, connector version 1.0) |
| CSV datasets | `ds_csv_agency`, `ds_csv_emp`, `ds_csv_title`, `ds_csv_payroll2020`, `ds_csv_payroll2021` |
| SQL datasets | `ds_sql_agency`, `ds_sql_emp`, `ds_sql_title`, `ds_sql_payroll2020`, `ds_sql_payroll2021`, `ds_sql_summary` |
| ADLS output dataset | `ds_csv_staging_summary` (folder `dirstaging`) |
| Data flows | `dataflow_agency`, `dataflow_emp`, `dataflow_title`, `dataflow_payroll2020`, `dataflow_payroll2021`, `dataflow_summary` |
| Pipeline | `pl_nycpayroll_main` |

**SQL connector version.** The ADF UI offered version 2.0 (recommended) and version 1.0. Version 1.0 was selected, following guidance that the newer connector can raise `MissingRequiredPropertyException: server is a required property` in mapping data flows. Version 2.0 was not tested here.

## CSV datasets

- Type DelimitedText, comma delimiter, default row delimiter (the files use CRLF and ADF detects it), UTF-8.
- **First row as header: on.** Quote character `"`, escape character `\`.
- Paths: `dirpayrollfiles/EmpMaster.csv`, `dirpayrollfiles/AgencyMaster.csv`, `dirpayrollfiles/TitleMaster.csv`, `dirpayrollfiles/nycpayroll_2021.csv`, and `dirhistoryfiles/nycpayroll_2020.csv`.
- All columns are imported as **string** (Schema > Import schema) and cast inside the data flows. Importing the schema is also what prevents `Column not found` errors when a data flow references a column.

Source profile checks: no blank numeric cells, all dates are `M/d/yyyy`, and no text exceeds the target VARCHAR widths.

## Ingestion data flows (5): CSV source to SQL sink

Each flow reads one CSV dataset and writes one Azure SQL table. Sink settings: update method **Insert**, table action **Truncate table**. Truncating is what makes a rerun rebuild the table rather than append to it.

Column names are identical between source and sink, with one deliberate difference between the payroll years:

- `dataflow_payroll2020`: `AgencyID` maps to `AgencyID`.
- `dataflow_payroll2021`: `AgencyCode` maps to `AgencyCode` (the 2021 table also uses `AgencyCode`). The rename to a common name happens later, in the summary flow.

The two payroll flows add a derived column step, `castcols`, between the source and the sink, because the CSV columns are strings and the tables are typed:

| Column | Expression |
|---|---|
| FiscalYear, PayrollNumber | `toInteger(<col>)` |
| AgencyStartDate | `toDate(AgencyStartDate, 'M/d/yyyy')` (CSV dates look like `9/12/2016`) |
| BaseSalary, RegularHours, RegularGrossPaid, OTHours, TotalOTPaid, TotalOtherPay | `toDouble(<col>)` |

## `dataflow_summary`

Parameter (Data flow > Parameters): `dataflow_param_fiscalyear`, type **integer**, default `2020`.

```
src2020  : source ds_sql_payroll2020   (dbo.NYC_Payroll_Data_2020)
src2021  : source ds_sql_payroll2021   (dbo.NYC_Payroll_Data_2021)
sel2020  : Select, 8 columns
sel2021  : Select, same 8 columns; AgencyCode renamed to AgencyID
union1   : Union by name of sel2020 and sel2021
filter1  : Filter
derive1  : Derived column TotalPaid
agg1     : Aggregate
sinkSQL  : Sink ds_sql_summary
sinkLake : Sink ds_csv_staging_summary
```

Both Selects keep the same columns: `FiscalYear, PayrollNumber, AgencyID, AgencyName, EmployeeID, RegularGrossPaid, TotalOTPaid, TotalOtherPay`. The `sel2021` mapping is `AgencyID = AgencyCode`. Every pay column the calculation needs must be selected: because the calculation is null-safe, an omitted column would be treated as zero instead of failing.

**filter1** runs after the union, so both years are already harmonized:

```
toInteger(FiscalYear) >= $dataflow_param_fiscalyear
```

**derive1** column `TotalPaid`:

```
coalesce(toDouble(RegularGrossPaid), 0) + coalesce(toDouble(TotalOTPaid), 0) + coalesce(toDouble(TotalOtherPay), 0)
```

Plain addition (`RegularGrossPaid + TotalOTPaid + TotalOtherPay`) gives the same result on this data because there are no nulls, but `coalesce` stops one null component from nulling the whole sum. Negative components (adjustments) exist in the data and are deliberately **included**, so `TotalPaid` is net pay.

**agg1**: group by `FiscalYear`, then `AgencyName`; aggregate `TotalPaid = sum(TotalPaid)`.

**sinkSQL**: dataset `ds_sql_summary`, *Truncate table*; mapping `FiscalYear`, `AgencyName`, `TotalPaid`.

**sinkLake**: dataset `ds_csv_staging_summary`, *Clear the folder*, file name option *Default* (Spark writes many small part files; nothing downstream depends on a file name).

The aggregate emits `FiscalYear`, `AgencyName`, `TotalPaid` in that order (group-by columns first, in the order listed). That order matches the Synapse external table, so no extra Select was needed.

### Output dataset `ds_csv_staging_summary`

DelimitedText, comma, **First row as header: off**, quote `"`, UTF-8, folder `dirstaging` in the container, no file name. This matches `FIRST_ROW = 1` in [../sql/synapse/01_serverless_external_objects.sql](../sql/synapse/01_serverless_external_objects.sql). If the header were turned on, `FIRST_ROW` would have to be 2.

The exported dataset still lists an unused 19-column string schema left over from an earlier schema import. The sink writes the three aggregate columns (confirmed by the staged files and the Synapse results); the stale metadata has no effect and is left as exported.

## Pipeline `pl_nycpayroll_main`

```
dataflow_agency  -+
dataflow_emp     -+--(all 3 succeed)--> dataflow_payroll2020 -+
dataflow_title   -+                    dataflow_payroll2021 -+--(both succeed)--> dataflow_summary
```

- Three `ExecuteDataFlow` activities with no dependencies run in parallel.
- `dataflow_payroll2020` and `dataflow_payroll2021` each depend on **all three** reference loads (`Succeeded`).
- `dataflow_summary` depends on both payroll activities (`Succeeded`).
- Pipeline parameter `p_fiscalyear` (int, default 2020) is passed to the summary flow as `dataflow_param_fiscalyear` with the dynamic content `@pipeline().parameters.p_fiscalyear`. Inside the data flow it is referenced as `$dataflow_param_fiscalyear`. A global parameter would work equally well with `@pipeline().globalParameters.<name>`; a pipeline parameter avoids global-parameter handling in a Git-enabled factory. Only one of the two should be used.
- Every activity runs on the Auto-resolve Azure integration runtime (compute size Small: General purpose, 8 cores).
- Rerun behavior: every SQL sink truncates and the lake sink clears its folder, so a rerun rebuilds the outputs. Verified by a second run (see [verification_results.md](verification_results.md)).
- Cost note: data flow debug clusters bill while running; turn debug off when it is not needed.
