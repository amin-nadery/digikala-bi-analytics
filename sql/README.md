# SQL scripts — DigiKala BI Analytics

The files in this folder document the SQL Server warehouse model and its staged loads. **These are publication-ready reconstructions based on the supplied database schema, Query Store excerpts, and project discussions—not a verified database backup.**

## Run sequence

1. `01_create_database.sql`
2. `02_create_tables.sql`
3. Import the four source files into `stg.orders`, `stg.product`, `stg.keifiat`, `stg.comment` (separate manual step).
4. `03_load_dimensions.sql`
5. `04_load_fact.sql` — **only on an empty Fact table**.
6. `05_data_quality_checks.sql`.

Run each numbered file in SSMS using the SQL Server database connection. Each file contains `USE [DigikalaBI]` where necessary. An environment with SQL Server 2017+ T-SQL features is required; Persian date formatting should be validated on the target server.

**Do not run these scripts against the user's existing populated project database without planning.** Use a clean test database to verify the results first. The public repository does **not** redistribute source data and does not implement an automatic source-file import step. For provenance and interpretation, see [`../docs/data-warehouse.md`](../docs/data-warehouse.md).
