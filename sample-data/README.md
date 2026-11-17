# Synthetic example dataset

A tiny, **fictional** dataset for exercising the pipeline end to end. It lets another engineer deploy and run the workflow without the original source files.

**This is not the original source data.** Every agency, title, employee, and amount here is invented ("DEMO ..." agencies, `EXAMPLE-nn` / `PERSON-x` employees); it contains no real people. It uses the same file names, column names, and column types the pipeline expects, but it will **not** reproduce the validation figures in [../docs/verification_results.md](../docs/verification_results.md) (25 summary rows, total 35,709,510.43), because those come from the original sample files.

## Files

| File | Rows | Folder to upload to | Schema |
|---|---|---|---|
| `AgencyMaster.csv` | 4 | `dirpayrollfiles/` | `AgencyID`, `AgencyName` |
| `EmpMaster.csv` | 12 | `dirpayrollfiles/` | `EmployeeID`, `LastName`, `FirstName` |
| `TitleMaster.csv` | 6 | `dirpayrollfiles/` | `TitleCode`, `TitleDescription` |
| `nycpayroll_2021.csv` | 9 | `dirpayrollfiles/` | 19 payroll columns; agency column is **`AgencyCode`** |
| `nycpayroll_2020.csv` | 9 | `dirhistoryfiles/` | the same 19 columns; agency column is **`AgencyID`** |

Payroll columns, in order: `FiscalYear`, `PayrollNumber`, `AgencyID` or `AgencyCode`, `AgencyName`, `EmployeeID`, `LastName`, `FirstName`, `AgencyStartDate` (`M/d/yyyy`), `WorkLocationBorough`, `TitleCode`, `TitleDescription`, `LeaveStatusasofJune30`, `BaseSalary`, `PayBasis`, `RegularHours`, `RegularGrossPaid`, `OTHours`, `TotalOTPaid`, `TotalOtherPay`.

Files are UTF-8 with LF line endings and a header row (ADF detects the row delimiter automatically). Value lengths fit the VARCHAR widths in [../sql/azure_sql/01_create_tables.sql](../sql/azure_sql/01_create_tables.sql).

## Behaviors it exercises

- **Schema difference between years:** `AgencyID` in the 2020 file, `AgencyCode` in the 2021 file.
- **Fiscal-year filter:** one out-of-range row in each payroll file (`FiscalYear` 1998 and 1999) that the filter removes, as in the original samples.
- **Overtime and other pay:** several rows have overtime pay and other pay; one row has a negative `TotalOtherPay` and another a negative `TotalOTPaid` (adjustments that must be kept).
- **Aggregation:** more than one payroll row per agency per year, across four agencies.

## Expected output

Computed locally from these CSV files with the same logic as `dataflow_summary` (union, `FiscalYear >= p_fiscalyear`, `TotalPaid = RegularGrossPaid + TotalOTPaid + TotalOtherPay`, group by `FiscalYear` and `AgencyName`). **These values were not produced by running the pipeline in Azure.**

| Parameter | Summary rows | Total | File |
|---|---|---|---|
| `p_fiscalyear = 2020` | 7 | 1,183,100.00 | [expected_summary_param2020.csv](expected_summary_param2020.csv) |
| `p_fiscalyear = 2021` | 4 | 628,800.00 | [expected_summary_param2021.csv](expected_summary_param2021.csv) |

## Using it

1. Upload the files to the folders shown above (see "Reproducing the Pipeline" in the main README).
2. Run the pipeline with `p_fiscalyear` set to 2020 or 2021.
3. Run the validation queries in [../sql/azure_sql/02_validation_queries.sql](../sql/azure_sql/02_validation_queries.sql). Expected row counts for the master and payroll tables: 4, 12, 6, 9, 9.
4. Compare `dbo.NYC_Payroll_Summary` with the matching expected file.
