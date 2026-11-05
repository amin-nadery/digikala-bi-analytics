/*
DigiKala BI Analytics — 05_data_quality_checks.sql
Read-only diagnostics. Does not alter the database.
Several checks were recovered from the user's Query Store export and
extended for reproducibility and source-coverage interpretation.
*/
USE [DigikalaBI];
GO

-- 1. Counts and grain: one fact row corresponds to one source order line.
SELECT
    (SELECT COUNT_BIG(*) FROM stg.orders) AS StagingOrderLines,
    (SELECT COUNT_BIG(*) FROM dw.FactOrderLine) AS FactOrderLines,
    (SELECT COUNT(DISTINCT ID_Order) FROM stg.orders) AS DistinctSourceOrders,
    (SELECT COUNT(DISTINCT OrderID) FROM dw.FactOrderLine) AS DistinctFactOrders;
GO

-- 2. Unmatched source keys, independent of Fact table.
SELECT
    COUNT_BIG(*) AS SourceOrderLines,
    SUM(CASE WHEN p.ProductKey IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END) AS MissingProducts,
    SUM(CASE WHEN c.CustomerKey IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END) AS MissingCustomers,
    SUM(CASE WHEN d.DateKey IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END) AS MissingDates,
    SUM(CASE WHEN city.CityKey IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END) AS MissingCities
FROM stg.orders AS o
LEFT JOIN dw.DimProduct AS p ON o.ID_Item = p.ProductID
LEFT JOIN dw.DimCustomer AS c ON o.ID_Customer = c.CustomerID
LEFT JOIN dw.DimDate AS d ON CAST(o.DateTime_CartFinalize AS DATE) = d.FullDate
LEFT JOIN dw.DimCity AS city
    ON REPLACE(REPLACE(TRIM(o.city_name_fa), N'ي', N'ی'), N'ك', N'ک') = city.CityNameFa;
GO

-- 3. TITLE coverage: denominator is FACT ORDER LINES, not unique products.
SELECT
    COUNT_BIG(*) AS FactOrderLines,
    SUM(CASE WHEN p.ProductTitle IS NOT NULL AND LEN(TRIM(p.ProductTitle)) > 0
             THEN CONVERT(BIGINT,1) ELSE 0 END) AS OrderLinesWithProductTitle,
    CAST(100.0 * SUM(CASE WHEN p.ProductTitle IS NOT NULL AND LEN(TRIM(p.ProductTitle)) > 0
                         THEN CONVERT(BIGINT,1) ELSE 0 END)
        / NULLIF(COUNT_BIG(*),0) AS DECIMAL(6,2)) AS ProductTitleCoveragePercent
FROM dw.FactOrderLine AS f
JOIN dw.DimProduct AS p ON p.ProductKey = f.ProductKey;
GO

-- 4. Source of available titles (counts are unique DIMENSION PRODUCTS).
SELECT TitleSource, COUNT_BIG(*) AS DimensionProducts
FROM dw.DimProduct
GROUP BY TitleSource
ORDER BY DimensionProducts DESC;
GO

-- 5. Referential integrity diagnostic. Should return zero rows.
SELECT TOP (100) f.OrderLineKey, f.CustomerKey, f.ProductKey, f.CityKey, f.DateKey
FROM dw.FactOrderLine AS f
LEFT JOIN dw.DimCustomer AS c ON c.CustomerKey = f.CustomerKey
LEFT JOIN dw.DimProduct AS p ON p.ProductKey = f.ProductKey
LEFT JOIN dw.DimCity AS city ON city.CityKey = f.CityKey
LEFT JOIN dw.DimDate AS d ON d.DateKey = f.DateKey
WHERE c.CustomerKey IS NULL OR p.ProductKey IS NULL
   OR city.CityKey IS NULL OR d.DateKey IS NULL;
GO

-- 6. Date calendar checks and example Persian dates.
SELECT MIN(FullDate) AS FirstDate, MAX(FullDate) AS LastDate,
       COUNT_BIG(*) AS DateRows,
       SUM(CASE WHEN PersianDate IS NULL OR PersianYear IS NULL
                    OR PersianMonthNumber IS NULL OR PersianMonthName IS NULL
                THEN CONVERT(BIGINT,1) ELSE 0 END) AS MissingPersianAttributes
FROM dw.DimDate;
SELECT TOP (10) FullDate, DateKey, PersianDate, PersianYear,
       PersianMonthNumber, PersianMonthName, PersianQuarter, DayOfWeekNumber, IsWeekend
FROM dw.DimDate
ORDER BY FullDate;
GO

-- 7. Inspect numeric conversion risks inherited from source imports.
SELECT
    SUM(CASE WHEN TRY_CONVERT(INT, Quantity_item) IS NULL
                  OR TRY_CONVERT(INT, Quantity_item) <> Quantity_item
             THEN CONVERT(BIGINT,1) ELSE 0 END) AS InvalidQuantities,
    SUM(CASE WHEN TRY_CONVERT(DECIMAL(19,2), Amount_Gross_Order) IS NULL
             THEN CONVERT(BIGINT,1) ELSE 0 END) AS InvalidAmounts
FROM stg.orders;
GO

-- 8. Potential duplicate product IDs in source references; if present,
--    reconstructed DimProduct load chooses a MAX nonempty value per field.
SELECT TRY_CONVERT(BIGINT, id) AS ProductID, COUNT_BIG(*) AS SourceRows
FROM stg.product
WHERE TRY_CONVERT(BIGINT, id) IS NOT NULL
GROUP BY TRY_CONVERT(BIGINT, id)
HAVING COUNT_BIG(*) > 1
ORDER BY SourceRows DESC;
GO
