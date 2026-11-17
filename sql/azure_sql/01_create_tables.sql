-- =====================================================================
-- Azure SQL Database  (db_nycpayroll)  --  NOT Synapse serverless
-- Run in: Azure Portal > SQL database > Query editor, or SSMS/Azure Data Studio
-- Re-runnable: each table is created only if it does not already exist.
-- This script never drops or deletes anything.
-- Column widths and types follow the project brief and were checked against
-- the real CSV files: the longest values are far below every VARCHAR width
-- (see docs/validation-and-evidence.md). FLOAT is used for amounts as in the
-- brief; DECIMAL would be preferable for currency in a production design.
-- NOTE: 2020 table has AgencyID; 2021 table has AgencyCode (matches the CSVs).
-- The summary flow renames AgencyCode to AgencyID before the union.
-- =====================================================================

IF OBJECT_ID(N'dbo.NYC_Payroll_EMP_MD', N'U') IS NULL
CREATE TABLE [dbo].[NYC_Payroll_EMP_MD](
    [EmployeeID] [varchar](10) NULL,
    [LastName]   [varchar](20) NULL,
    [FirstName]  [varchar](20) NULL
);
GO

IF OBJECT_ID(N'dbo.NYC_Payroll_TITLE_MD', N'U') IS NULL
CREATE TABLE [dbo].[NYC_Payroll_TITLE_MD](
    [TitleCode]        [varchar](10)  NULL,
    [TitleDescription] [varchar](100) NULL
);
GO

IF OBJECT_ID(N'dbo.NYC_Payroll_AGENCY_MD', N'U') IS NULL
CREATE TABLE [dbo].[NYC_Payroll_AGENCY_MD](
    [AgencyID]   [varchar](10) NULL,
    [AgencyName] [varchar](50) NULL
);
GO

IF OBJECT_ID(N'dbo.NYC_Payroll_Data_2020', N'U') IS NULL
CREATE TABLE [dbo].[NYC_Payroll_Data_2020](
    [FiscalYear]            [int]          NULL,
    [PayrollNumber]         [int]          NULL,
    [AgencyID]              [varchar](10)  NULL,   -- 2020 file header = AgencyID
    [AgencyName]            [varchar](50)  NULL,
    [EmployeeID]            [varchar](10)  NULL,
    [LastName]              [varchar](20)  NULL,
    [FirstName]             [varchar](20)  NULL,
    [AgencyStartDate]       [date]         NULL,
    [WorkLocationBorough]   [varchar](50)  NULL,
    [TitleCode]             [varchar](10)  NULL,
    [TitleDescription]      [varchar](100) NULL,
    [LeaveStatusasofJune30] [varchar](50)  NULL,
    [BaseSalary]            [float]        NULL,
    [PayBasis]              [varchar](50)  NULL,
    [RegularHours]          [float]        NULL,
    [RegularGrossPaid]      [float]        NULL,
    [OTHours]               [float]        NULL,
    [TotalOTPaid]           [float]        NULL,
    [TotalOtherPay]         [float]        NULL
);
GO

IF OBJECT_ID(N'dbo.NYC_Payroll_Data_2021', N'U') IS NULL
CREATE TABLE [dbo].[NYC_Payroll_Data_2021](
    [FiscalYear]            [int]          NULL,
    [PayrollNumber]         [int]          NULL,
    [AgencyCode]            [varchar](10)  NULL,   -- 2021 file header = AgencyCode (NOT AgencyID)
    [AgencyName]            [varchar](50)  NULL,
    [EmployeeID]            [varchar](10)  NULL,
    [LastName]              [varchar](20)  NULL,
    [FirstName]             [varchar](20)  NULL,
    [AgencyStartDate]       [date]         NULL,
    [WorkLocationBorough]   [varchar](50)  NULL,
    [TitleCode]             [varchar](10)  NULL,
    [TitleDescription]      [varchar](100) NULL,
    [LeaveStatusasofJune30] [varchar](50)  NULL,
    [BaseSalary]            [float]        NULL,
    [PayBasis]              [varchar](50)  NULL,
    [RegularHours]          [float]        NULL,
    [RegularGrossPaid]      [float]        NULL,
    [OTHours]               [float]        NULL,
    [TotalOTPaid]           [float]        NULL,
    [TotalOtherPay]         [float]        NULL
);
GO

IF OBJECT_ID(N'dbo.NYC_Payroll_Summary', N'U') IS NULL
CREATE TABLE [dbo].[NYC_Payroll_Summary](
    [FiscalYear] [int]         NULL,
    [AgencyName] [varchar](50) NULL,
    [TotalPaid]  [float]       NULL
);
GO

-- Verify: expect 6 rows
SELECT name FROM sys.tables WHERE name LIKE 'NYC_Payroll%' ORDER BY name;
