# Data Warehouse Implementation

## Overview

This repository documents an independent, educational Business Intelligence implementation built around historical sampled e-commerce data attributed to the DigiKala Open Data program. The database is named `DigikalaBI` and uses **two schemas inside one SQL Server database**:

- `stg`: four tables representing the imported CSV/XLSX source structures.
- `dw`: one fact table and four dimension tables, used for Power BI reporting.

**SQL Server and T-SQL performed the main transformation and dimensional loading work.** SSIS and SQL Server import utilities were supporting tools for initial source-file ingestion; the project did **not** implement the complete warehouse transformation pipeline as SSIS packages.

## Architecture

```mermaid
flowchart LR
  S[CSV / XLSX source extracts] --> I[SSIS and SQL Server import utilities]
  I --> STG[DigikalaBI.stg]
  STG --> SQL[T-SQL transformations and lookups]
  SQL --> DW[DigikalaBI.dw star schema]
  DW --> BI[Power BI semantic model]
  BI --> R[Persian RTL report]
```

### Staging tables

| Table | Role |
|---|---|
| `stg.orders` | Order-line observations: IDs, dates, city, quantity, recorded amount |
| `stg.product` | Product titles, brands and categories when available |
| `stg.keifiat` | Supplemental product titles and fields |
| `stg.comment` | Additional referenced product IDs |

### Star schema

| Table | Grain / key | Description |
|---|---|---|
| `dw.FactOrderLine` | **One source order line**; `OrderLineKey` | Quantity, recorded amount and four dimension FKs |
| `dw.DimCustomer` | Customer business key `CustomerID` | Surrogate `CustomerKey` |
| `dw.DimProduct` | Product business key `ProductID` | Surrogate `ProductKey`, descriptive attributes, provenance |
| `dw.DimCity` | Normalized Persian city name | Surrogate `CityKey` |
| `dw.DimDate` | One calendar day | Integer `DateKey=YYYYMMDD`, Gregorian and Persian attributes |

`OrderID` is **not** unique at the fact-line grain; count orders with `COUNT(DISTINCT OrderID)` rather than counting fact rows. Product title coverage is a share of fact order lines, not a share of unique products.

## Reconstructing the warehouse

The SQL files below are packaged in order:

1. `sql/01_create_database.sql` — creates the database and `stg`/`dw` schemas if missing.
2. `sql/02_create_tables.sql` — creates four staging tables, four dimensions, one fact and four foreign keys.
3. **Import the four original source files into the empty `stg` tables** using approved access to those source files. This manual ingestion step is not automated by the public SQL scripts.
4. `sql/03_load_dimensions.sql` — inserts customers, standardized cities, consolidated product references, missing order product IDs, and dates.
5. `sql/04_load_fact.sql` — checks staging-to-dimension coverage, then inserts fact order lines **only when the fact is empty**.
6. `sql/05_data_quality_checks.sql` — read-only audit queries to review mapping completeness and metrics.

### Safety requirements

- Use a **new test database / disposable SQL Server instance** when reproducing the solution. Do **not** run the package indiscriminately against the existing working database.
- The DDL files create missing objects and do not delete existing data, but reproducing the full process still requires a clean staging import and an empty fact.
- The fact loader refuses to run when `dw.FactOrderLine` already contains rows, since the source dataset does not expose a unique source line ID suitable for safe incremental upserts.
- The source datasets are not redistributed in this repository; review the original data-use conditions before obtaining or sharing them.
- The scripts have been **statically reviewed but not executed against a live SQL Server instance in the publication preparation environment**. SQL Server execution and parity with the original warehouse still require validation.

## Technical decisions

### Product identity and metadata

The metadata-load logic consolidates IDs from `stg.product`, `stg.comment` and `stg.keifiat`. Descriptive titles are prioritized from `stg.product`; if absent, `stg.keifiat` can provide a fallback. A second insert ensures that every product business key present in `stg.orders` has a matching `dw.DimProduct` row, even when all descriptive fields remain unknown.

This distinction is important:

- **Referential integrity** can be achieved without dropping order lines.
- **Metadata completeness** cannot be inferred from the presence of a matching `ProductKey`.

An initial project assessment estimated recoverable product titles for approximately 8% of fact order lines. The public SQL check calculates the coverage from the rebuilt warehouse; the historical estimate is not a substitute for a verified run.

### City standardization

The city load trims names and replaces Arabic Yeh/Kaf (`ي`,`ك`) with the Persian equivalents (`ی`,`ک`). The fact loader applies the same normalization in its city lookup.

### Date dimension

The original project discussion used a date series from `2013-09-27` to `2018-12-11` (1,902 consecutive days). The public reconstruction derives its minimum and maximum dates from `stg.orders` instead of hardcoding the period. It stores Gregorian fields and Persian calendar fields. Persian dates are generated using SQL Server `FORMAT(..., 'fa-IR')` and require environment-specific verification.

The reconstructed `DayOfWeekNumber` uses **Monday=1 through Sunday=7**, and `IsWeekend=1` for Friday. This explicit convention should be checked against the original Power BI model before reusing any weekday/weekend analytics.

### Fact loading and integrity checks

Before insertion, `04_load_fact.sql` audits missing customer, product, city and date lookups, as well as invalid numeric conversions. A mismatch blocks the load rather than silently dropping order lines through `INNER JOIN`s. The final source and inserted row counts must match.

The fact insert uses **`c.CustomerKey`** (surrogate key), not the `c.CustomerID` business key. This was corrected in the recovered Query Store history.

## Provenance of the SQL reconstruction

This publication is a cleaned **reconstruction**, not a claim that every line of SQL is an unchanged historical script.

| Section | Provenance |
|---|---|
| Database and table columns, data types and FKs | Extracted from supplied SSMS-generated `script.sql` |
| Product dimension merge and unknown-product insert | Recovered from supplied Query Store export, then made safer and readable |
| Customer dimension load | Recovered from supplied Query Store export |
| Fact-to-dimension lookup and insert | Recovered from supplied Query Store export; corrected version used |
| City normalization and load | Reconstructed from prior project conversation and corresponding fact lookup |
| Date sequence, Persian calendar update | Reconstructed from prior project conversation and actual `DimDate` schema |
| Read-only QA checks | Adapted from Query Store checks and expanded for validation |

Additional robustness measures in the reconstructed code (e.g. source-product deduplication, conditional inserts and preflight checks) may differ from the SQL originally run. Results should be checked against the working database before calling the build fully reproducible.

## Monetary-field caution

`stg.orders.Amount_Gross_Order` was imported as `FLOAT` and mapped to `dw.FactOrderLine.RecordedAmount` as `DECIMAL(19,2)`. The precise business semantics and currency unit of the original amount field are not established here. Do not label its sum as official revenue or GMV until independently validated. The file scripts do not resolve this uncertainty.

## Publication

No raw records, PBIX model with embedded original data, SQL Server credentials or secrets are included. Use approved/synthetic data for public demonstrations where appropriate. Attribution and permission for source data are separate from trademark/logo rights.
