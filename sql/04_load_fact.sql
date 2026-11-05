/*
DigiKala BI Analytics — 04_load_fact.sql
Core INSERT recovered from Query Store export, 2026-10-25 13:43:13 UTC.
IMPORTANT: Correct version uses c.CustomerKey (NOT c.CustomerID).
Extra validation checks have been added for safe, reproducible publishing.

Run ONLY on a newly created EMPTY dw.FactOrderLine after loading stg.* and
running 03_load_dimensions.sql. This script deliberately refuses to re-run on
an existing populated Fact table because source orders have no unique line ID.
No deletes, truncates, or destructive overwrites are performed.
*/
USE [DigikalaBI];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF NOT EXISTS (SELECT 1 FROM stg.orders)
    THROW 51010, 'stg.orders is empty; import source data first.', 1;
IF EXISTS (SELECT 1 FROM dw.FactOrderLine)
    THROW 51011, 'dw.FactOrderLine is not empty. Stop: loading again may create duplicate order lines. Use a fresh test database.', 1;

-- Preflight quality checks: do not silently discard source rows in INNER JOINs.
DECLARE
    @ExpectedRows BIGINT,
    @MissingCustomers BIGINT,
    @MissingProducts BIGINT,
    @MissingCities BIGINT,
    @MissingDates BIGINT,
    @InvalidQuantities BIGINT,
    @InvalidAmounts BIGINT;

SELECT
    @ExpectedRows = COUNT_BIG(*),
    @MissingCustomers = COALESCE(SUM(CASE WHEN c.CustomerKey IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END), 0),
    @MissingProducts = COALESCE(SUM(CASE WHEN p.ProductKey IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END), 0),
    @MissingCities = COALESCE(SUM(CASE WHEN city.CityKey IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END), 0),
    @MissingDates = COALESCE(SUM(CASE WHEN d.DateKey IS NULL THEN CONVERT(BIGINT,1) ELSE 0 END), 0),
    @InvalidQuantities = COALESCE(SUM(CASE WHEN TRY_CONVERT(INT, o.Quantity_item) IS NULL
                                      OR TRY_CONVERT(INT, o.Quantity_item) <> o.Quantity_item
                                THEN CONVERT(BIGINT,1) ELSE 0 END), 0),
    @InvalidAmounts = COALESCE(SUM(CASE WHEN TRY_CONVERT(DECIMAL(19,2), o.Amount_Gross_Order) IS NULL
                                THEN CONVERT(BIGINT,1) ELSE 0 END), 0)
FROM stg.orders AS o
LEFT JOIN dw.DimCustomer AS c ON o.ID_Customer = c.CustomerID
LEFT JOIN dw.DimProduct AS p ON o.ID_Item = p.ProductID
LEFT JOIN dw.DimCity AS city
    ON REPLACE(REPLACE(TRIM(o.city_name_fa), N'ي', N'ی'), N'ك', N'ک') = city.CityNameFa
LEFT JOIN dw.DimDate AS d ON CAST(o.DateTime_CartFinalize AS DATE) = d.FullDate;

SELECT @ExpectedRows AS SourceOrderLines, @MissingCustomers AS MissingCustomers,
       @MissingProducts AS MissingProducts, @MissingCities AS MissingCities,
       @MissingDates AS MissingDates, @InvalidQuantities AS InvalidQuantities,
       @InvalidAmounts AS InvalidAmounts;

IF @MissingCustomers > 0 OR @MissingProducts > 0 OR @MissingCities > 0
   OR @MissingDates > 0 OR @InvalidQuantities > 0 OR @InvalidAmounts > 0
    THROW 51012, 'Fact load blocked by unmatched dimension keys or invalid values. Inspect preflight counts.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO dw.FactOrderLine (
        OrderID, CustomerKey, ProductKey, CityKey, DateKey,
        OrderFinalizedAt, Quantity, RecordedAmount
    )
    SELECT
        o.ID_Order,
        c.CustomerKey,
        p.ProductKey,
        city.CityKey,
        d.DateKey,
        TRY_CONVERT(DATETIME2, o.DateTime_CartFinalize),
        TRY_CONVERT(INT, o.Quantity_item),
        TRY_CONVERT(DECIMAL(19,2), o.Amount_Gross_Order)
    FROM stg.orders AS o
    INNER JOIN dw.DimCustomer AS c ON o.ID_Customer = c.CustomerID
    INNER JOIN dw.DimProduct AS p ON o.ID_Item = p.ProductID
    INNER JOIN dw.DimCity AS city
        ON REPLACE(REPLACE(TRIM(o.city_name_fa), N'ي', N'ی'), N'ك', N'ک') = city.CityNameFa
    INNER JOIN dw.DimDate AS d ON CAST(o.DateTime_CartFinalize AS DATE) = d.FullDate;

    DECLARE @InsertedRows BIGINT = @@ROWCOUNT;
    DECLARE @SourceRows BIGINT = (SELECT COUNT_BIG(*) FROM stg.orders);
    IF @InsertedRows <> @SourceRows
        THROW 51013, 'Inserted fact row count differs from staging order-line count. Transaction rolled back.', 1;

    COMMIT TRANSACTION;
    SELECT @SourceRows AS ExpectedOrderLines, @InsertedRows AS InsertedFactRows;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
