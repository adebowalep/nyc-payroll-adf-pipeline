# Mapping Data Flow reference (copy/paste into ADF)

> Status: prepared locally. NOT YET VERIFIED in ADF until you test with Data preview.

## Names to use (keep identical everywhere)

| Type | Name |
|---|---|
| Linked service (ADLS) | `ls_adls_nycpayroll` (type AzureBlobFS) |
| Linked service (SQL) | `ls_sql_nycpayroll` (type AzureSqlDatabase, Version = Legacy) |
| CSV datasets | `ds_csv_agency`, `ds_csv_emp`, `ds_csv_title`, `ds_csv_payroll2020`, `ds_csv_payroll2021` |
| SQL datasets | `ds_sql_agency`, `ds_sql_emp`, `ds_sql_title`, `ds_sql_payroll2020`, `ds_sql_payroll2021`, `ds_sql_summary` |
| ADLS sink dataset | `ds_csv_staging_summary` (folder `dirstaging`) |
| Data flows | `dataflow_agency`, `dataflow_emp`, `dataflow_title`, `dataflow_payroll2020`, `dataflow_payroll2021`, `dataflow_summary` |
| Pipeline | `pl_nycpayroll_main` |

## CSV dataset settings (all five)

- Type DelimitedText, comma, row delimiter default (files are CRLF, ADF auto-detects), encoding UTF-8
- **First row as header = ON**, Quote char `"`, Escape char `\`
- Paths (container = your container): `dirpayrollfiles/EmpMaster.csv`, `.../AgencyMaster.csv`, `.../TitleMaster.csv`, `.../nycpayroll_2021.csv`, and `dirhistoryfiles/nycpayroll_2020.csv`
- Then: Schema tab > **Import schema** (fixes "Column not found: FiscalYear"). Preview data.
- Keep all CSV columns as **string** on import (safe), and cast in the data flow.

## Ingestion data flows (x5): Source (CSV) -> Sink (SQL table)

Source: CSV dataset, Allow schema drift OFF. Sink: matching SQL dataset.
Sink settings: **Table action: Truncate table** (this is what makes reruns safe; no duplicates), Update method: Insert.
Sink > Mapping: turn **Auto mapping OFF** only if names differ. Names are identical **except**:

- `dataflow_payroll2021`: source column `AgencyCode` -> sink column `AgencyCode` (same name, sink table is also AgencyCode). Do NOT expect `AgencyID`.
- `dataflow_payroll2020`: `AgencyID` -> `AgencyID`.

Type handling (put a **Derived Column** between source and sink for the two payroll flows, or rely on auto-cast if preview is clean):

| Column | Expression |
|---|---|
| FiscalYear | `toInteger(FiscalYear)` |
| PayrollNumber | `toInteger(PayrollNumber)` |
| AgencyStartDate | `toDate(AgencyStartDate, 'M/d/yyyy')`  (CSV dates look like `9/12/2016`) |
| BaseSalary, RegularHours, RegularGrossPaid, OTHours, TotalOTPaid, TotalOtherPay | `toDouble(<col>)` |

Verified locally: no blank numeric cells, all dates are `M/d/yyyy`, no text exceeds the VARCHAR widths.

## `dataflow_summary` (rubric core)

Parameter (Data flow > Parameters tab): `dataflow_param_fiscalyear`, type **integer**, default `2020`.

```
src2020  : source ds_sql_payroll2020   (dbo.NYC_Payroll_Data_2020)
src2021  : source ds_sql_payroll2021   (dbo.NYC_Payroll_Data_2021)
sel2020  : Select  - keep columns in the order below
sel2021  : Select  - same order; rename  AgencyCode -> AgencyID
union1   : Union (by name) of sel2020 + sel2021
filter1  : Filter
derive1  : Derived Column  TotalPaid
agg1     : Aggregate
sinkSQL  : Sink  ds_sql_summary
sinkLake : Sink  ds_csv_staging_summary
```

Keep in both Selects (same order): `FiscalYear, PayrollNumber, AgencyID, AgencyName, EmployeeID, RegularGrossPaid, TotalOTPaid, TotalOtherPay`
(only the columns needed; extra columns are harmless but renaming AgencyCode -> AgencyID is mandatory per the project brief).
`sel2021` rule: **Name as** `AgencyID` for input column `AgencyCode`.

**filter1** (after the union - both years already harmonized):

```
toInteger(FiscalYear) >= $dataflow_param_fiscalyear
```

**derive1** column `TotalPaid` (null-safe; a null component will not wipe out the others):

```
coalesce(toDouble(RegularGrossPaid), 0) + coalesce(toDouble(TotalOTPaid), 0) + coalesce(toDouble(TotalOtherPay), 0)
```

Course version `RegularGrossPaid + TotalOTPaid + TotalOtherPay` gives the same result on this data (no nulls), but the coalesce form is the safe one. Note: negative components exist in the real data (adjustments/retro) and are deliberately **included** (net pay); do not filter them.

**agg1**: Group by `AgencyName`, `FiscalYear`. Aggregates: `TotalPaid` = `sum(TotalPaid)`

**sinkSQL**: dataset `ds_sql_summary`, Settings > **Truncate table**. Mapping: FiscalYear, AgencyName, TotalPaid.
**sinkLake**: dataset `ds_csv_staging_summary`, Settings > **Clear the folder**; File name option: `Output to single file` is optional (Synapse reads a folder either way - do not rely on any file name).
Column order out of aggregate must be FiscalYear, AgencyName, TotalPaid to match the Synapse external table - add a final **Select** (or sink mapping) to force that order.

### Sink dataset `ds_csv_staging_summary` for Synapse

DelimitedText, comma, **First row as header = OFF**, quote `"`, UTF-8, folder `<container>/dirstaging`, no file name.
This matches `FIRST_ROW = 1` in `sql/synapse/01_serverless_external_objects.sql`. If you turn the header ON, change `FIRST_ROW` to 2.

## Pipeline `pl_nycpayroll_main`

```
dataflow_agency  -+
dataflow_emp     -+--(all 3 succeed)--> dataflow_payroll2020 -+
dataflow_title   -+                    dataflow_payroll2021 -+--(both succeed)--> dataflow_summary
```

- 3 `ExecuteDataFlow` activities with no dependencies (parallel).
- payroll2020 and payroll2021: each has a **Success** arrow from **all three** (drag each of 3 green handles to each of the 2).
- dataflow_summary: **Success** arrows from both payroll activities.
- Parameter on dataflow_summary activity > Parameters tab > `dataflow_param_fiscalyear` > Dynamic content:
  - Global parameter (course way): `@pipeline().globalParameters.dataflow_param_fiscalyear`
  - Or pipeline parameter `p_fiscalyear`: `@pipeline().parameters.p_fiscalyear`
  - Do not mix the two. Global parameter: Manage > Author > Global parameters > New (name `dataflow_param_fiscalyear`, Integer, 2020).
  - (Inside the data flow itself the parameter is referenced as `$dataflow_param_fiscalyear`.)
- Rerun safety: every SQL sink truncates, the lake sink clears the folder, so a rerun cannot double-count.
- Compute: use the default Azure IR; set TTL 0 / smallest core count (General, 8 cores is the minimum) and **turn Data flow debug off when done** to avoid wasting lab time.
