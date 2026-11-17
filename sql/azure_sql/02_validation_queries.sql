-- =====================================================================
-- Azure SQL Database validation queries (read-only SELECTs).
-- Run AFTER a successful pipeline run. Run one query at a time: the Azure
-- portal query editor shows only the result of the last statement in a script.
-- These queries were executed against db_nycpayroll after two pipeline runs
-- (@p / @p2 = 2020); the observed results are recorded in
-- docs/verification_results.md.
-- Expected values computed locally from the CSV files:
--   docs/expected_summary_param2020_LOCAL.csv
--   docs/expected_summary_param2021_LOCAL.csv (not run in Azure)
-- =====================================================================

-- 1) Source row counts after the five ingestion data flows
--    Expected from CSV files (excluding header): AGENCY 153, EMP 1000,
--    TITLE 1446, 2020 = 100, 2021 = 101  (counted locally from the CSVs)
--    The 2020 file has one FiscalYear=1998 row; the 2021 file has one
--    FiscalYear=1999 row. The fiscal-year filter removes both (see docs).
SELECT 'AGENCY_MD' t, COUNT(*) n FROM dbo.NYC_Payroll_AGENCY_MD UNION ALL
SELECT 'EMP_MD',      COUNT(*)   FROM dbo.NYC_Payroll_EMP_MD    UNION ALL
SELECT 'TITLE_MD',    COUNT(*)   FROM dbo.NYC_Payroll_TITLE_MD  UNION ALL
SELECT 'Data_2020',   COUNT(*)   FROM dbo.NYC_Payroll_Data_2020 UNION ALL
SELECT 'Data_2021',   COUNT(*)   FROM dbo.NYC_Payroll_Data_2021;

-- 2) The summary the pipeline wrote
SELECT * FROM dbo.NYC_Payroll_Summary ORDER BY FiscalYear, AgencyName;

-- 3) INDEPENDENT recomputation straight from the two source tables
--    (@p = the fiscal year parameter value used for the run: 2020 or 2021)
DECLARE @p int = 2020;
;WITH u AS (
    SELECT FiscalYear, AgencyName, RegularGrossPaid, TotalOTPaid, TotalOtherPay
    FROM dbo.NYC_Payroll_Data_2020
    UNION ALL
    SELECT FiscalYear, AgencyName, RegularGrossPaid, TotalOTPaid, TotalOtherPay
    FROM dbo.NYC_Payroll_Data_2021
)
SELECT FiscalYear, AgencyName,
       SUM(ISNULL(RegularGrossPaid,0)+ISNULL(TotalOTPaid,0)+ISNULL(TotalOtherPay,0)) AS TotalPaid_check,
       SUM(ISNULL(TotalOTPaid,0)) AS OT_only,
       COUNT(*) AS source_rows
FROM u
WHERE FiscalYear >= @p
GROUP BY FiscalYear, AgencyName
ORDER BY FiscalYear, AgencyName;

-- 4) Reconcile pipeline output vs independent check: expect ZERO rows
DECLARE @p2 int = 2020;
;WITH u AS (
    SELECT FiscalYear, AgencyName, RegularGrossPaid, TotalOTPaid, TotalOtherPay FROM dbo.NYC_Payroll_Data_2020
    UNION ALL
    SELECT FiscalYear, AgencyName, RegularGrossPaid, TotalOTPaid, TotalOtherPay FROM dbo.NYC_Payroll_Data_2021
), chk AS (
    SELECT FiscalYear, AgencyName,
           SUM(ISNULL(RegularGrossPaid,0)+ISNULL(TotalOTPaid,0)+ISNULL(TotalOtherPay,0)) AS TotalPaid_check
    FROM u WHERE FiscalYear >= @p2 GROUP BY FiscalYear, AgencyName
)
SELECT COALESCE(s.FiscalYear,c.FiscalYear) FiscalYear,
       COALESCE(s.AgencyName,c.AgencyName) AgencyName,
       s.TotalPaid, c.TotalPaid_check
FROM dbo.NYC_Payroll_Summary s
FULL OUTER JOIN chk c ON s.FiscalYear=c.FiscalYear AND s.AgencyName=c.AgencyName
WHERE s.FiscalYear IS NULL OR c.FiscalYear IS NULL
   OR ABS(s.TotalPaid - c.TotalPaid_check) > 0.01;

-- 5) Quality checks
SELECT COUNT(*) AS null_cells
FROM dbo.NYC_Payroll_Summary
WHERE FiscalYear IS NULL OR AgencyName IS NULL OR TotalPaid IS NULL;           -- expect 0

SELECT FiscalYear, AgencyName, COUNT(*) c
FROM dbo.NYC_Payroll_Summary GROUP BY FiscalYear, AgencyName HAVING COUNT(*)>1; -- expect 0 rows (duplicate keys => double-load)

SELECT * FROM dbo.NYC_Payroll_Summary WHERE TotalPaid < 0;                       -- expect 0 rows; investigate any

SELECT FiscalYear, COUNT(*) AS agencies, SUM(TotalPaid) AS grand_total
FROM dbo.NYC_Payroll_Summary GROUP BY FiscalYear;

-- 6) Overtime-specific (does not change the required summary schema)
SELECT FiscalYear, SUM(TotalOTPaid) AS ot_paid, SUM(OTHours) AS ot_hours
FROM (SELECT FiscalYear,TotalOTPaid,OTHours FROM dbo.NYC_Payroll_Data_2020
      UNION ALL SELECT FiscalYear,TotalOTPaid,OTHours FROM dbo.NYC_Payroll_Data_2021) x
GROUP BY FiscalYear ORDER BY FiscalYear;

-- 7) Duplicate-load detector on the source tables (expect 0 rows)
SELECT 'Data_2020' t, EmployeeID, PayrollNumber, COUNT(*) c FROM dbo.NYC_Payroll_Data_2020 GROUP BY EmployeeID, PayrollNumber HAVING COUNT(*)>1
UNION ALL
SELECT 'Data_2021', EmployeeID, PayrollNumber, COUNT(*) FROM dbo.NYC_Payroll_Data_2021 GROUP BY EmployeeID, PayrollNumber HAVING COUNT(*)>1;
