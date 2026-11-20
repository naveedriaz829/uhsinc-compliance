-- =============================================================================
-- US 11134 - DEV validation queries (READ-ONLY)
-- Supplemental Benefit Utilization and Costs — CY2026
-- =============================================================================
-- Safety:
--   * SELECT / EXISTS checks only. Do NOT run the main development script.
--   * Do NOT run DELETE, UPDATE, INSERT, MERGE, TRUNCATE, DROP, or ALTER.
--   * Prefer TOP when exploring large tables.
--   * Queries labeled [CONFIRM] need BA / Shreya / DEV DBA confirmation.
--   * These queries have NOT been executed in this workspace.
-- =============================================================================

USE [Medicare_Custom];
GO

DECLARE @REPORTING_YEAR int = 2026;
DECLARE @START_DATE date = DATEFROMPARTS(@REPORTING_YEAR, 1, 1);
DECLARE @END_DATE   date = DATEFROMPARTS(@REPORTING_YEAR, 12, 31);

-- -----------------------------------------------------------------------------
-- 1) Required database objects exist in DEV
-- -----------------------------------------------------------------------------
SELECT
    v.ExpectedObject,
    CASE WHEN OBJECT_ID(v.ExpectedObject, 'U') IS NOT NULL THEN 'EXISTS' ELSE 'MISSING' END AS ObjectStatus
FROM (VALUES
    ('Medicare_Custom.CMSReporting.QNXT_Benefits_2026'),
    ('Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026'),
    ('Medicare_Custom.CMSReporting.SBSC_Code'),
    ('Medicare_Custom.CMSReporting.PrimaryMapping'),
    ('Medicare_Custom.CMSReporting.SupplementalVendorRates'),
    ('Medicare_Custom.CMSReporting.ProcedureCodeToSBSC_Code_External'),
    -- [CONFIRM] Vendor staging tables may remain _2025 or be renamed for 2026
    ('Medicare_Custom.CMSReporting.Transportation_2025'),
    ('Medicare_Custom.CMSReporting.Meals_2025'),
    ('Medicare_Custom.CMSReporting.OTC_2025'),
    ('Medicare_Custom.CMSReporting.Activity_Tracker_2025'),
    ('Medicare_Custom.CMSReporting.Transportation_2026'),
    ('Medicare_Custom.CMSReporting.Meals_2026'),
    ('Medicare_Custom.CMSReporting.OTC_2026'),
    ('Medicare_Custom.CMSReporting.Activity_Tracker_2026')
) v(ExpectedObject)
ORDER BY v.ExpectedObject;

-- Optional: broader CMSReporting object inventory (DEV only)
SELECT TOP (200)
    s.name AS SchemaName,
    t.name AS TableName
FROM Medicare_Custom.sys.tables t
JOIN Medicare_Custom.sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'CMSReporting'
  AND (
        t.name LIKE '%QNXT_Benefits%'
     OR t.name LIKE '%SupplementalBenefit%'
     OR t.name LIKE '%Transportation%'
     OR t.name LIKE '%Meals%'
     OR t.name LIKE '%OTC%'
     OR t.name LIKE '%Activity_Tracker%'
     OR t.name LIKE '%SBSC%'
     OR t.name LIKE '%PrimaryMapping%'
  )
ORDER BY t.name;

-- -----------------------------------------------------------------------------
-- 2) 2026 category mappings available (SBSC_Code / PrimaryMapping)
-- [CONFIRM] Exact CY2026 category list is defined in CMS Technical Specifications
--           (missing from workspace) and the BA workbook (labeled PBP Category_2025).
-- -----------------------------------------------------------------------------
SELECT TOP (500)
    SBSC_Code,
    SBSC_BaseCode,
    SupplementalBenefitDescription,
    HowOffered,
    UtilizationUnit,
    DataSource,
    TypeOfPaymentArrangements,
    HowAreCostsAccounted
FROM Medicare_Custom.CMSReporting.SBSC_Code
ORDER BY SBSC_BaseCode, SBSC_Code;

-- Categories present in BA workbook but potentially missing from SBSC_Code
-- [CONFIRM] Replace / expand this list after Technical Specs are available.
SELECT w.PBP_Category
FROM (VALUES
    ('1a1'),('1a2'),('1a3'),('1a-B'),
    ('1b1'),('1b2'),('1b-B'),
    ('2-1'),('2-3'),('2-B'),
    ('3-1'),('3-2'),('3-3'),('3-4'),
    ('4c1'),('4c2'),('4c3'),
    ('7b1'),('7b2'),('7f'),
    ('9d-1'),
    ('10b1'),('10b2'),
    ('13a'),('13b'),('13c'),('13d'),('13e'),('13f'),('13g'),
    ('13i1'),('13i2'),('13i3'),('13i4'),('13i5'),('13i6'),('13i7'),('13i8'),
    ('13i9'),('13i10'),('13i11'),('13i12'),('13i13'),('13i14'),('13i15'),
    ('14b'),('14c1'),('14c2'),('14c3'),('14c4a'),('14c4b'),('14c4c'),
    ('14c5'),('14c6'),('14c7a'),('14c7b'),('14c8'),('14c9'),('14c10'),
    ('14c11'),('14c12'),('14c13'),('14c14'),('14c15'),('14c16'),('14c17'),
    ('14c18'),('14c19'),('14c20'),('14c21'),('14c22a'),('14c22b'),('14c22c'),
    ('16b1'),('16b2'),('16b3'),('16b4'),('16b5'),('16b6'),
    ('16c1'),('16c2'),('16c3'),('16c4'),('16c5'),('16c6'),('16c7'),('16c8'),('16c9'),('16c10'),
    ('17a1'),('17a2'),('17b1'),('17b2'),('17b3'),('17b4'),('17b5'),
    ('18a1'),('18a2'),('18b1'),('18b2'),('18b3'),('18b4'),('18c'),
    ('VT'),('POS')
) w(PBP_Category)
WHERE NOT EXISTS (
    SELECT 1
    FROM Medicare_Custom.CMSReporting.SBSC_Code c
    WHERE c.SBSC_BaseCode = w.PBP_Category
       OR c.SBSC_Code = w.PBP_Category
);

SELECT TOP (500) *
FROM Medicare_Custom.CMSReporting.PrimaryMapping;

-- -----------------------------------------------------------------------------
-- 3) Contract / PBP values vs approved plan listing
-- [CONFIRM] Download '2026 PBP - Plan name listing 052825.xlsx' into 01_Requirements
--           and compare against these distinct plan columns / PolicyNum values.
-- -----------------------------------------------------------------------------
-- Plans hardcoded in PrimaryMapping UNPIVOT (from development SQL)
SELECT v.PlanID
FROM (VALUES
    ('H5945-001'),('H5945-002'),('H5945-013'),('H5945-014'),('H5945-016'),
    ('H5945-017'),('H5945-018'),('H5945-027'),('H5945-032'),('H5945-801'),
    ('H5945-802'),('H5945-804'),('H5945-805'),
    ('H7239-001'),('H7239-002'),('H7239-003'),
    ('H7680-001'),('H7680-002'),('H7680-007'),('H7680-009'),('H7680-011'),
    ('H7680-012'),('H7680-014'),('H7680-015'),('H7680-016'),('H7680-017'),
    ('H7680-018'),('H7680-019'),('H7680-801'),('H7680-802')
) v(PlanID)
ORDER BY v.PlanID;

-- Distinct MA PolicyNum in PlanData for the reporting window
SELECT TOP (500)
    LEFT(pol.PolicyNum, 5) AS Contract,
    SUBSTRING(pol.PolicyNum, 6, 3) AS PBP,
    COUNT(*) AS PolicyRows
FROM PlanData_Prod.dbo.Policy pol
JOIN PHP_EDW.dbo.vwLineOfBusinessByProgram pgm
    ON pgm.ProgramId = pol.programid
   AND pgm.LOB = 'Medicare Advantage'
WHERE pol.effdate <= @END_DATE
GROUP BY LEFT(pol.PolicyNum, 5), SUBSTRING(pol.PolicyNum, 6, 3)
ORDER BY Contract, PBP;

-- -----------------------------------------------------------------------------
-- 4) Enrollment counts and reporting dates
-- -----------------------------------------------------------------------------
SELECT
    @REPORTING_YEAR AS ReportingYear,
    @START_DATE AS StartDate,
    @END_DATE AS EndDate;

SELECT TOP (200)
    enrl.PolicyNum,
    COUNT(DISTINCT enrl.MemberID) AS EligibleMembers_EverInPeriod
FROM PHP_EDW.Master.MedicalEnrollAll enrl
WHERE enrl.[Type] = 'Medicare Advantage'
  AND enrl.EffDate <= @END_DATE
  AND ISNULL(enrl.TermDate, '2078-12-31') >= @START_DATE
  AND enrl.TermDate > enrl.EffDate
GROUP BY enrl.PolicyNum
ORDER BY enrl.PolicyNum;

-- Target table row counts / last update (if table already seeded in DEV)
SELECT
    COUNT(*) AS ResultRows,
    COUNT(DISTINCT Contract) AS Contracts,
    COUNT(DISTINCT CONCAT(Contract, '-', PBP)) AS ContractPBPs,
    COUNT(DISTINCT [PBP Category]) AS DistinctCategories,
    MIN(LastUpdate) AS MinLastUpdate,
    MAX(LastUpdate) AS MaxLastUpdate
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026;

SELECT TOP (100)
    Contract,
    PBP,
    [PBP Category],
    [How is the SB offered?],
    [The number of enrollees eligible],
    LastUpdate
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026
ORDER BY Contract, PBP, [PBP Category];

-- -----------------------------------------------------------------------------
-- 5) Vendor data availability for the reporting period
-- [CONFIRM] Table year suffixes and date columns with Shreya / vendor owners.
-- -----------------------------------------------------------------------------
-- Transportation (current script joins Transportation_2025)
IF OBJECT_ID('Medicare_Custom.CMSReporting.Transportation_2025', 'U') IS NOT NULL
BEGIN
    SELECT TOP (50) *
    FROM Medicare_Custom.CMSReporting.Transportation_2025;
    SELECT COUNT(*) AS Transportation_2025_Rows
    FROM Medicare_Custom.CMSReporting.Transportation_2025;
END

IF OBJECT_ID('Medicare_Custom.CMSReporting.Meals_2025', 'U') IS NOT NULL
BEGIN
    SELECT TOP (50) *
    FROM Medicare_Custom.CMSReporting.Meals_2025;
    SELECT COUNT(*) AS Meals_2025_Rows
    FROM Medicare_Custom.CMSReporting.Meals_2025;
END

IF OBJECT_ID('Medicare_Custom.CMSReporting.OTC_2025', 'U') IS NOT NULL
BEGIN
    SELECT TOP (50) *
    FROM Medicare_Custom.CMSReporting.OTC_2025;
    SELECT COUNT(*) AS OTC_2025_Rows
    FROM Medicare_Custom.CMSReporting.OTC_2025;
END

IF OBJECT_ID('Medicare_Custom.CMSReporting.Activity_Tracker_2025', 'U') IS NOT NULL
BEGIN
    SELECT TOP (50) *
    FROM Medicare_Custom.CMSReporting.Activity_Tracker_2025;
    SELECT COUNT(*) AS Activity_Tracker_2025_Rows
    FROM Medicare_Custom.CMSReporting.Activity_Tracker_2025;
END

-- Capitation / PMPM rates overlapping reporting year
SELECT TOP (200)
    *
FROM Medicare_Custom.CMSReporting.SupplementalVendorRates
WHERE EffDate <= @END_DATE
  AND ISNULL(TermDate, '2078-12-31') >= @START_DATE
ORDER BY DataSource, PolicyNum, EffDate;

-- -----------------------------------------------------------------------------
-- 6) Unexpected duplicates or missing categories in results
-- -----------------------------------------------------------------------------
-- Duplicate Contract/PBP/Category/OfferType combinations
SELECT
    Contract,
    PBP,
    [PBP Category],
    [How is the SB offered?],
    COUNT(*) AS DupCount
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026
GROUP BY Contract, PBP, [PBP Category], [How is the SB offered?]
HAVING COUNT(*) > 1
ORDER BY DupCount DESC, Contract, PBP, [PBP Category];

-- Categories in SBSC_Code with no rows in the CY2026 results table
SELECT
    c.SBSC_BaseCode,
    c.SBSC_Code,
    c.SupplementalBenefitDescription,
    c.DataSource
FROM Medicare_Custom.CMSReporting.SBSC_Code c
WHERE NOT EXISTS (
    SELECT 1
    FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026 s
    WHERE s.[PBP Category] = c.SBSC_BaseCode
       OR s.SBSC_Code = c.SBSC_Code
)
ORDER BY c.SBSC_BaseCode, c.SBSC_Code;

-- QNXT benefits mapping row counts (after DEV load)
IF OBJECT_ID('Medicare_Custom.CMSReporting.QNXT_Benefits_2026', 'U') IS NOT NULL
BEGIN
    SELECT COUNT(*) AS QNXT_Benefits_2026_Rows
    FROM Medicare_Custom.CMSReporting.QNXT_Benefits_2026;

    SELECT TOP (50)
        SBSC_Code,
        COUNT(*) AS RowsPerCode
    FROM Medicare_Custom.CMSReporting.QNXT_Benefits_2026
    GROUP BY SBSC_Code
    ORDER BY RowsPerCode DESC;
END

-- Sanity: median utilization should not exceed total instances when both > 0
-- [CONFIRM] Post-processing force-adjustments in the main script may alter these.
SELECT TOP (100)
    Contract,
    PBP,
    [PBP Category],
    [The number of enrollees eligible],
    [The number of enrollees who utilized benefit once],
    [The total instances of utilization among eligible enrollees],
    [The median number of utilizations among enrollees who utilized the benefit at least once]
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026
WHERE [The median number of utilizations among enrollees who utilized the benefit at least once]
      > [The total instances of utilization among eligible enrollees]
  AND [The total instances of utilization among eligible enrollees] > 0
ORDER BY Contract, PBP, [PBP Category];

-- Utilizers exceeding eligible
SELECT TOP (100)
    Contract,
    PBP,
    [PBP Category],
    [The number of enrollees eligible],
    [The number of enrollees who utilized benefit once]
FROM Medicare_Custom.CMSReporting.SupplementalBenefitUtilizationAndCosts_2026
WHERE [The number of enrollees who utilized benefit once] > [The number of enrollees eligible]
ORDER BY Contract, PBP, [PBP Category];
GO
