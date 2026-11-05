/*
DigiKala BI Analytics — 03_load_dimensions.sql
Sources:
  * DimProduct and DimCustomer INSERT patterns recovered from Query Store export
    (2026-10-25), restructured for readable/idempotent loads.
  * DimCity and DimDate reconstructed from the project's prior implementation
    discussion, NOT recovered as exact historical SQL text.
  * Persian dates use SQL Server FORMAT(..., 'fa-IR'); validate your environment.
Prerequisite: Source CSV/XLSX already loaded into stg.* on a fresh DB.
Safety: INSERT operations check for existing business keys; no TRUNCATE/DELETE.
         Existing dimension attribute values are not overwritten.
*/
USE [DigikalaBI];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF NOT EXISTS (SELECT 1 FROM stg.orders)
    THROW 51001, 'stg.orders is empty. Import source files before loading the warehouse.', 1;

-- 1) Customer dimension — directly recovered core query.
INSERT INTO dw.DimCustomer (CustomerID)
SELECT DISTINCT o.ID_Customer
FROM stg.orders AS o
WHERE o.ID_Customer IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dw.DimCustomer AS c
      WHERE c.CustomerID = o.ID_Customer
  );

-- 2) City dimension — reconstructed from the earlier project workflow.
--    Normalize Arabic Yeh/Kaf, trim whitespace and remove empty names.
;WITH NormalizedCities AS (
    SELECT DISTINCT
        NULLIF(
            REPLACE(
                REPLACE(TRIM(o.city_name_fa), N'ي', N'ی'),
                N'ك', N'ک'
            ), N''
        ) AS CityNameFa
    FROM stg.orders AS o
)
INSERT INTO dw.DimCity (CityNameFa)
SELECT nc.CityNameFa
FROM NormalizedCities AS nc
WHERE nc.CityNameFa IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dw.DimCity AS c
      WHERE c.CityNameFa = nc.CityNameFa
  );

-- 3) Product dimension — recovered Query Store logic, with defensive
--    aggregation of duplicate product IDs and an existing-key guard.
--    Primary product attributes take precedence over Keifiat title fallback.
;WITH AllProductIds AS (
    SELECT TRY_CONVERT(BIGINT, id) AS ProductID FROM stg.product
    UNION
    SELECT TRY_CONVERT(BIGINT, product_id) FROM stg.comment
    UNION
    SELECT TRY_CONVERT(BIGINT, product_id) FROM stg.keifiat
),
ProductInfo AS (
    SELECT
        TRY_CONVERT(BIGINT, id) AS ProductID,
        MAX(NULLIF(TRIM(product_title_fa), N'')) AS ProductTitle,
        MAX(NULLIF(TRIM(category_title_fa), N'')) AS CategoryTitleFa,
        MAX(NULLIF(TRIM(brand_name_fa), N'')) AS BrandNameFa
    FROM stg.product
    WHERE TRY_CONVERT(BIGINT, id) IS NOT NULL
    GROUP BY TRY_CONVERT(BIGINT, id)
),
KeifiatInfo AS (
    SELECT
        TRY_CONVERT(BIGINT, product_id) AS ProductID,
        MAX(NULLIF(TRIM(product_title), N'')) AS ProductTitle,
        MAX(NULLIF(TRIM(title_en), N'')) AS ProductGroupCode
    FROM stg.keifiat
    WHERE TRY_CONVERT(BIGINT, product_id) IS NOT NULL
    GROUP BY TRY_CONVERT(BIGINT, product_id)
)
INSERT INTO dw.DimProduct (
    ProductID, ProductTitle, CategoryTitleFa, BrandNameFa,
    ProductGroupCode, TitleSource, CategorySource
)
SELECT
    ids.ProductID,
    COALESCE(p.ProductTitle, k.ProductTitle),
    p.CategoryTitleFa,
    p.BrandNameFa,
    k.ProductGroupCode,
    CASE
        WHEN p.ProductTitle IS NOT NULL THEN 'Products'
        WHEN k.ProductTitle IS NOT NULL THEN 'Keifiat'
        ELSE 'Unknown'
    END,
    CASE WHEN p.CategoryTitleFa IS NOT NULL THEN 'Products' ELSE 'Unknown' END
FROM AllProductIds AS ids
LEFT JOIN ProductInfo AS p ON p.ProductID = ids.ProductID
LEFT JOIN KeifiatInfo AS k ON k.ProductID = ids.ProductID
WHERE ids.ProductID IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dw.DimProduct AS existing
      WHERE existing.ProductID = ids.ProductID
  );

-- Include order-referenced product IDs even if no title/category was found.
;WITH OrderProducts AS (
    SELECT DISTINCT TRY_CONVERT(BIGINT, ID_Item) AS ProductID
    FROM stg.orders
)
INSERT INTO dw.DimProduct (
    ProductID, ProductTitle, CategoryTitleFa, BrandNameFa,
    ProductGroupCode, TitleSource, CategorySource
)
SELECT
    o.ProductID, NULL, NULL, NULL, NULL, 'Unknown', 'Unknown'
FROM OrderProducts AS o
WHERE o.ProductID IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dw.DimProduct AS p
      WHERE p.ProductID = o.ProductID
  );

-- 4) Date dimension — reconstructed, calendar span covers source data.
--    Earlier project used a 2013-09-27 .. 2018-12-11 span (1902 days).
--    Deriving bounds from the source makes this script reusable for other samples.
DECLARE @MinDate DATE, @MaxDate DATE;
SELECT
    @MinDate = MIN(CAST(DateTime_CartFinalize AS DATE)),
    @MaxDate = MAX(CAST(DateTime_CartFinalize AS DATE))
FROM stg.orders;

;WITH CalendarDays AS (
    SELECT @MinDate AS FullDate
    UNION ALL
    SELECT DATEADD(DAY, 1, FullDate)
    FROM CalendarDays
    WHERE FullDate < @MaxDate
)
INSERT INTO dw.DimDate (
    DateKey, FullDate, YearNumber, QuarterNumber, MonthNumber,
    MonthName, DayNumber, DayOfWeekNumber, IsWeekend
)
SELECT
    CONVERT(INT, CONVERT(CHAR(8), cd.FullDate, 112)),
    cd.FullDate,
    YEAR(cd.FullDate),
    DATEPART(QUARTER, cd.FullDate),
    MONTH(cd.FullDate),
    FORMAT(cd.FullDate, N'MMMM', N'en-US'),
    DAY(cd.FullDate),
    (DATEDIFF(DAY, CONVERT(DATE, '19000101'), cd.FullDate) % 7) + 1,
    CASE WHEN (DATEDIFF(DAY, CONVERT(DATE, '19000101'), cd.FullDate) % 7) + 1 = 5 THEN 1 ELSE 0 END
FROM CalendarDays AS cd
WHERE NOT EXISTS (
    SELECT 1 FROM dw.DimDate AS d
    WHERE d.FullDate = cd.FullDate
)
OPTION (MAXRECURSION 0);

-- Convert Persian/Arabic glyph digits (when present) to ASCII digits so the
-- fixed yyyy/MM/dd string can be converted to numeric year/month fields.
;WITH PersianDates AS (
    SELECT
        DateKey,
        TRANSLATE(
            FORMAT(FullDate, N'yyyy/MM/dd', N'fa-IR'),
            N'۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩',
            N'01234567890123456789'
        ) AS NormalizedPersianDate
    FROM dw.DimDate
)
UPDATE d
SET
    d.PersianDate = p.NormalizedPersianDate,
    d.PersianYear = TRY_CONVERT(SMALLINT, LEFT(p.NormalizedPersianDate, 4)),
    d.PersianMonthNumber = TRY_CONVERT(TINYINT, SUBSTRING(p.NormalizedPersianDate, 6, 2)),
    d.PersianMonthName = CASE TRY_CONVERT(INT, SUBSTRING(p.NormalizedPersianDate, 6, 2))
        WHEN 1 THEN N'فروردین' WHEN 2 THEN N'اردیبهشت'
        WHEN 3 THEN N'خرداد' WHEN 4 THEN N'تیر'
        WHEN 5 THEN N'مرداد' WHEN 6 THEN N'شهریور'
        WHEN 7 THEN N'مهر' WHEN 8 THEN N'آبان'
        WHEN 9 THEN N'آذر' WHEN 10 THEN N'دی'
        WHEN 11 THEN N'بهمن' WHEN 12 THEN N'اسفند'
    END,
    d.PersianQuarter = CASE
        WHEN TRY_CONVERT(INT, SUBSTRING(p.NormalizedPersianDate, 6, 2)) BETWEEN 1 AND 12
        THEN (TRY_CONVERT(INT, SUBSTRING(p.NormalizedPersianDate, 6, 2)) + 2) / 3
    END
FROM dw.DimDate AS d
JOIN PersianDates AS p ON p.DateKey = d.DateKey;

-- Guard against wrong calendar output from an incompatible runtime/locale.
IF EXISTS (
    SELECT 1 FROM dw.DimDate
    WHERE PersianDate IS NULL OR LEN(PersianDate) <> 10
       OR PersianYear NOT BETWEEN 1300 AND 1500
       OR PersianMonthNumber NOT BETWEEN 1 AND 12
       OR PersianQuarter NOT BETWEEN 1 AND 4
       OR PersianMonthName IS NULL
)
    THROW 51002, 'Persian calendar validation failed. Inspect FORMAT(..., fa-IR) before proceeding.', 1;

-- Quick overview (read-only):
SELECT N'DimCustomer' AS DimensionName, COUNT_BIG(*) AS RowCount FROM dw.DimCustomer
UNION ALL SELECT N'DimCity', COUNT_BIG(*) FROM dw.DimCity
UNION ALL SELECT N'DimProduct', COUNT_BIG(*) FROM dw.DimProduct
UNION ALL SELECT N'DimDate', COUNT_BIG(*) FROM dw.DimDate;
GO
