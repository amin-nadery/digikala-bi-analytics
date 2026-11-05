# DigiKala BI Analytics

**An end-to-end business intelligence portfolio project using SQL Server, SSIS, dimensional modeling, DAX, and Power BI.**

**داشبورد تحلیلی فارسی و راست‌به‌چپ دیجی‌کالا** — پروژه‌ای مستقل برای نمایش فرایند آماده‌سازی داده، طراحی انبار داده و ساخت گزارش‌های تعاملی هوش تجاری.

> **Project status:** Work in progress · **Report language:** Persian (RTL) · **Visual theme:** Graphite & Coral  
> **Live dashboard:** Not publicly available yet. A public link will be added only if the applicable data-use and hosting requirements are satisfied.

## 1. Overview

This project explores historical, sampled e-commerce data attributed to the DigiKala Open Data Mining Program. It demonstrates a practical BI workflow—from source-file assessment and ETL to a dimensional data warehouse, analytical measures, and an interactive Power BI report.

**Main areas of work**

- Data profiling, quality checks, and source reconciliation
- Data ingestion with SQL Server Integration Services (**SSIS**)
- SQL Server **staging** and **data warehouse** layers
- Star-schema design, surrogate keys, and fact–dimension relationships
- Power BI semantic modeling and **DAX** measures
- Persian, **right-to-left (RTL)** dashboard design and interactive reporting

This is an **independent educational/portfolio project**, not an official DigiKala product or a report of DigiKala's total operational performance.

## 2. Dataset source, attribution, and permitted use

### Data provenance

The source files were downloaded from a third-party public repository:

- **Dataset repository (maintained by Farshad):** [farshadnp/DigiKalaDataSet](https://github.com/farshadnp/DigiKalaDataSet)
- **Original DigiKala Open Data program reference:** [digikala.com/opendata](https://www.digikala.com/opendata/)

The repository maintainer states that the data was originally obtained from DigiKala's Open Data program. **I did not crawl, scrape, collect, or originally publish these datasets.** My work concerns the subsequent examination, preparation, integration, modeling, and analysis of the downloaded files.

The source program requests the following acknowledgment:

> This publication was supported by the Digikala Open Data Mining Program.

This acknowledgment is reproduced as requested by the original data program; it **does not imply** that DigiKala sponsors, endorses, or is affiliated with this independent project.

### Data-use disclaimer

The original program documentation, as reproduced in the source repository, restricts **direct or indirect commercial use without written permission**. Availability of the files on GitHub should not be interpreted as a blanket license to redistribute or commercially use the underlying data.

**The raw source datasets are intentionally excluded from this repository.** Publication of any PBIX file, semantic model, or publicly accessible dashboard that exposes the original data is subject to verifying the necessary permissions. A public portfolio demo may instead use an independently generated synthetic dataset.

Please consult the original program and dataset maintainer for current usage conditions. This project's SQL, reporting logic, and documentation are distinct from ownership of the source data.

## 3. Source files

| File | Contents used in this project |
| --- | --- |
| `orders.csv` | Sampled order lines, order/customer/product IDs, dates, cities, quantities, and recorded amounts |
| `product.xlsx` | Product titles, brands, and categories where available |
| `keifiat.xlsx` | Product-related evaluations and additional product descriptors |
| `comment.xlsx` | Product-related customer comments and identifiers |

**Important:** These files are sampled extracts, not a complete and consistently linked transactional database. They must not be treated as a comprehensive representation of the DigiKala marketplace.

## 4. Solution architecture

```mermaid
flowchart LR
    A[Source files] --> B[SSIS ingestion]
    B --> C[SQL Server: stg schema]
    C --> D[T-SQL transformations and quality checks]
    D --> E[SQL Server: dw star schema]
    E --> F[Power BI semantic model]
    F --> G[Persian RTL dashboards]
```

### Staging layer

The four source datasets were imported into SQL Server under the `stg` schema. This layer keeps the original source structure separate from downstream warehouse transformations.

### Dimensional warehouse

The analytical warehouse is built in the `dw` schema:

| Object | Purpose |
| --- | --- |
| `dw.FactOrderLine` | Order-line grain, quantities, recorded amounts, and dimension foreign keys |
| `dw.DimDate` | Gregorian and Persian calendar attributes |
| `dw.DimCustomer` | Distinct customer business keys mapped to surrogate keys |
| `dw.DimCity` | Normalized city names and city surrogate keys |
| `dw.DimProduct` | Product identifiers and available descriptive attributes |

The fact table retains the **order-line grain**. Distinct orders must therefore be counted using `OrderID`, rather than simply counting fact rows. Dimension surrogate keys are resolved through business-key lookups during the fact-loading process.

The repository is intended to include the reviewed SQL scripts and sanitized SSIS packages. A dedicated technical document describing schemas, loading logic, key mapping, and validation queries will be added separately.

## 5. Key data-integration challenge: missing product metadata

A significant issue appeared when joining the orders dataset to the product reference datasets. Many `orders.ID_Item` values **did not have a corresponding product title or category** in the available product metadata.

Initial profiling of roughly **200,000 order-line records** indicated that descriptive product titles could be recovered for only about **7.96% of order lines** by combining the relevant available metadata sources. In other words, around **92.04%** of sampled order lines still lacked a recoverable product title. These are approximate profiling results and should be revalidated using the final SQL checks before being treated as final published statistics.

### How the issue was handled

1. **Detected unmatched keys:** Used SQL joins, including anti-join checks, to assess the overlap of product IDs across source tables.
2. **Consolidated available product references:** Built the product dimension from a union of distinct product identifiers drawn from the relevant sources; preferred existing product-table descriptions and used other available descriptors where appropriate.
3. **Included order-referenced product IDs:** Added `ID_Item` values appearing in `orders` even if their descriptive metadata was missing.
4. **Mapped valid surrogate keys:** Resolved `ProductKey` for fact rows via `DimProduct.ProductID`, preserving fact-to-dimension referential integrity rather than dropping valid transactions with unmatched metadata.
5. **Preserved missing descriptions:** Left unavailable titles/categories/brands unknown instead of fabricating attributes.
6. **Restricted interpretation:** Kept order-, customer-, and city-level analyses on valid fact records, while limiting product/category-level claims to records with adequate descriptive coverage.

### What was—and was not—resolved

**Resolved:** Coverage of the fact's product business keys in `DimProduct` and the associated warehouse foreign-key mapping.  
**Not resolved:** The underlying absence of descriptive product metadata.

This illustrates the distinction between **referential integrity** (a fact row points to a valid dimension record) and **metadata completeness** (that record actually has a trustworthy title, category, or brand).

Product/category insights must **not** be presented as representative of all sampled orders when most order lines lack product descriptors.

## 6. Power BI report

The report uses a custom **Graphite & Coral** visual style, Persian labels, and an **RTL layout**.

| Page | Analytical purpose | Status |
| --- | --- | --- |
| **Executive Overview** | Headline KPIs, order trends, top-city order share, and customer behavior | Implemented; final QA in progress |
| **Sales Analytics** | Monthly/annual trends, monetary measures, and calendar-based activity | In development |
| **Customer Intelligence** | Purchase frequency, repeat purchases, and observed new/returning activity | In development / planned |
| **Geographic Insights** | City-level contributions and comparisons | Planned |
| **Product Explorer** | Product exploration within reliable metadata coverage | Planned; constrained by missing metadata |

### Interaction and design

Features implemented or planned across report pages include date/city slicers, navigation buttons, bookmarks for filter-panel visibility, cross-filtering, field parameters, drill-through, and report tooltips. A feature is not considered complete until implemented and tested in the report.

<!-- Add a screenshot here after reviewing the final report image:
![Executive Overview](assets/screenshots/executive-overview.png)
-->

## 7. Analytical measures

| Metric | Definition / interpretation |
| --- | --- |
| **Total Orders** | Distinct count of recorded `OrderID` values |
| **Total Customers** | Distinct count of customers with recorded order activity |
| **Total Units** | Sum of recorded order-line quantities |
| **Repeat Customers** | Customers with at least two distinct orders in the current filter context |
| **Repeat Purchase Rate** | Repeat Customers ÷ Total Customers |
| **Orders per Customer** | Total Orders ÷ Total Customers |
| **Units per Order** | Total Units ÷ Total Orders |
| **City Order Share** | Orders in a city ÷ orders across all cities, while retaining applicable non-city filters |
| **AOV** | Recorded monetary amount ÷ distinct orders, **only after validating the monetary field's meaning** |

**Metric caveats:** A customer first seen in this sample is not necessarily a genuinely new DigiKala customer. Repeat-purchase measures are also limited to observed transactions. The monetary field (`Amount_Gross_Order` / warehouse `RecordedAmount`) must be validated to establish whether it represents a unit amount, line amount, or another definition before asserting GMV, revenue, or AOV as reliable business metrics. Currency units should also be confirmed.

## 8. Repository organization

```text
digikala-bi-analytics/
├── README.md
├── docs/
│   ├── data-warehouse.md          # Detailed DW documentation (forthcoming)
│   └── metric-definitions.md      # Measure definitions (forthcoming)
├── sql/
│   ├── 01_create_schemas.sql
│   ├── 02_create_dimensions.sql
│   ├── 03_create_fact.sql
│   ├── 04_load_dimensions.sql
│   ├── 05_load_fact.sql
│   └── 06_data_quality_checks.sql
├── etl/
│   └── ssis/                      # Sanitized SSIS packages
├── powerbi/
│   └── themes/                    # Theme JSON
└── assets/
    └── screenshots/              # Report previews
```

> **Structure note:** This is the target structure. Files will be added after reviewing and organizing the working SQL scripts, SSIS packages, theme, and report screenshots. The repository does not contain the original source datasets.

## 9. Reproducibility and publication

A future technical guide will document the supported local build sequence: obtain the source files under their applicable usage terms, load staging data, create and populate dimensional tables, run quality checks, and connect the Power BI semantic model.

For portfolio viewing, this repository will provide screenshots and technical documentation. A **live Power BI Service link** will be added only if the dataset's public use is authorized and the report can be hosted with suitable access and licensing. A time-limited Microsoft Fabric trial is **not assumed to provide permanent public hosting**.

## 10. Scope and limitations

- Source data consists of **historical samples**, not all DigiKala transactions.
- Product datasets have **limited overlap** with the orders dataset.
- Missing product titles/categories reduce the scope of reliable product-level analysis.
- An order can have multiple order lines; measures must respect their correct grain.
- Customer purchase histories may be incomplete; observed first purchase and repeat activity are sample-based.
- Monetary measures require confirmation of the amount field's definition and currency.
- No official company-wide operational, profitability, conversion, or customer-acquisition claims are made.

## 11. Credits

- **Original data program:** DigiKala Open Data Mining Program
- **Third-party source repository:** [farshadnp/DigiKalaDataSet](https://github.com/farshadnp/DigiKalaDataSet)
- **BI solution implementation:** Independent portfolio work covering SQL Server, SSIS, dimensional modeling, DAX, and Power BI

> This publication was supported by the Digikala Open Data Mining Program.

**Disclaimer:** This repository is not affiliated with, endorsed by, or officially sponsored by DigiKala. Attribution does not constitute permission to redistribute or commercially use the underlying data.
