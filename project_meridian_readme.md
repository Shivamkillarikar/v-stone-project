# Project Meridian: Retail Analytics (Package 08 - Returns)

**Trainee ID:** `t08`  
**Catalog:** `meridian_tnn`  
**Deployment Environment:** Databricks Free Edition (Serverless)  
**Reference Documents:** 
* `Project Meridian - Databricks Free Edition DE Problem Statement.pdf`
* `Package_08_returns.png`

## 1. Data Profile & Design Note (Phase 0)

**Source Data:** `samples.tpcds_sf1` (Store Returns, Reason, Store, Item, Customer, Store Sales)  
**Focus Area:** Returns abuse, loss, and pattern detection.

### Entities, Classification, and Grain

| Entity | Layer / Table | Type | Grain | Primary Key | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Store Returns** | `gold.fact_store_returns` | Fact | One record per item returned per transaction ticket | `(ticket_number, item_sk)` | Core transactional fact capturing returned merchandise, refund amounts, and operational flags. |
| **Customer** | `gold.dim_customer` | Dimension | One record per registered customer | `c_customer_sk` | Customer profile attributes, contact channels, and identity keys. |
| **Item** | `gold.dim_item` | Dimension | One record per product SKU/item | `i_item_sk` | Product metadata including item descriptions, categories, classes, and prices. |
| **Store** | `gold.dim_store` | Dimension | One record per physical retail location | `s_store_sk` | Store geography, location identifiers, and operational state divisions. |
| **Date** | `gold.dim_date` | Dimension | One record per calendar day | `d_date_sk` | Calendar dimension enabling time-intelligence aggregations (day, month, quarter, year). |
| **Return Reason** | `gold.dim_reason` | Dimension | One record per unique return reason | `r_reason_sk` | Reason definitions tracked via SCD Type 2; exposed as current active records (`__END_AT IS NULL`). |

---

## 2. Silver Contract (Phase 2)

Our Silver layer (`meridian_tnn.silver`) strictly enforces the following data contract before data is permitted to enter the Gold dimensional model:

1. **Naming:** All columns are renamed from raw system formats (e.g., `sr_item_sk`) to business-friendly formats (e.g., `item_sk`).
2. **Data Types:** Financial columns are explicitly cast to `decimal(10,2)`. Identifiers and keys are cast to `int`.
3. **Validity Rules (Quality Expectations):** 
   * `valid_quantity`: `return_quantity > 0`
   * `valid_item`: `item_sk IS NOT NULL`
   * `valid_refund`: `refunded_cash >= 0`
   * *Action:* Records failing these checks are dropped from the Silver stream and routed to `ops.quarantine_store_returns` for auditing.
4. **Uniqueness:** Duplicates are stripped from the stream using `.dropDuplicates(["ticket_number", "item_sk"])` to guarantee exactly one row per returned item.
5. **History Rules:** The `bronze_reason` table is historised as SCD Type 2 into `silver_reason_history`, sequenced by `batch_number`. Downstream Gold views filter for the currently active reason.

---

## 3. Key Performance Indicators (KPIs) (Phase 3)

KPIs are defined once in a Unity Catalog Metric View and consumed by AI/BI Dashboards, Genie Agents, and Power BI.

| KPI Name | Business Definition | Calculation / Logic |
| :--- | :--- | :--- |
| **Return Value** | Aggregate monetary volume disbursed for returned merchandise. | `SUM(refunded_cash)` |
| **Net Loss** | Total refund value minus salvaged value (where applicable). | `SUM(refunded_cash) - SUM(salvage_value)` |
| **Returns per Store** | Distinct volume of customer return transactions processed by location. | `COUNT(DISTINCT ticket_number) grouped by store_sk` |
| **High-Frequency Returner Count** | Distinct count of customers exceeding the parameterised return-frequency threshold. | `COUNT(DISTINCT customer_sk) WHERE return_count > threshold` |
| **Orphan Return Rate** | Percentage of returns without an associated Bronze sale record (fraud indicator). | `(COUNT_IF(is_orphan_return = True) / COUNT(*)) * 100` |

---

## 4. Security Model (Phase 4)

Governance is applied directly in Unity Catalog, ensuring uniform protection regardless of the consumption tool (Databricks SQL, Genie, or Power BI).

### Row-Level Security
* **Secured Dimension:** `dim_store` (`s_state`) / `fact_store_returns` (`store_state`)
* **Policy Rule:** Regional Analysts (`tn_analyst`) are restricted to viewing only records where `s_state = 'TN'`. 
* **Mechanism:** Unity Catalog SQL Row Filter applied via `IS_ACCOUNT_GROUP_MEMBER()`. Administrators (`admin`) have nationwide access.

### Sensitive Columns (Two-Tier Masking)
Dynamic column masking is applied to PII and financial data via a Unity Catalog UDF.
* **Full Identity (Unmasked):** `admin` and `tnn_pii_readers` see real values.
* **Partial Identity (Analysts):** Non-privileged users see partially masked values (`J*****` for first name, `D*****` for last name) allowing for pattern detection without exposing identity.
* **Redacted (Analysts):** `c_email_address` and `c_customer_id` are fully masked (`***@***.***`).

---

## 5. Tier 4: Advanced Implementations (Phase 10)

Per the project evaluation criteria, the advanced challenges are separated into Team and Individual achievements.

### A. Team Deliverables (Shared Architecture)
* **Databricks Asset Bundles (DABs):** Managed deployment via CI/CD using `databricks.yml`, utilizing multi-environment targeting.
* **Production Orchestration:** Implemented a scheduled Lakeflow Job running unattended, complete with email failure alerts and task dependencies (Governance -> Landing -> DLT -> Prep -> DQ Gate).
* **Concurrency Control:** Configured `max_concurrent_runs: 1` to strictly respect Free Edition serverless capacity limits.

### B. Individual Deliverables (Trainee: `tnn` / Package 08)
* **Orphan Returns Pattern Detection:** Implemented a broadcast `LEFT JOIN` against `store_sales` in the DLT pipeline to flag returns lacking a valid receipt (`is_orphan_return = True`), fulfilling Advanced Challenge 1.
* **Two-Tier Masking:** Authored a dynamic SQL UDF to provide partial visibility of customer identities to analysts for tracking repeat-offender patterns, fulfilling Advanced Challenge 3.
* **Power BI SSO DirectQuery:** Successfully configured a DirectQuery semantic model connecting to the 2X-Small Serverless Warehouse, proving the metric view and UC governance pass through cleanly to external BI tools via OAuth.

---

## 6. Architecture & Design Decisions

* **DAB Deployment to a Single Catalog (`meridian_tnn`):** In a standard enterprise, `dev` and `prod` targets would deploy to separate catalogs (e.g., `meridian_dev` and `meridian_prod`). However, due to Unity Catalog restrictions in the Free Edition (`PERMISSION_DENIED: Can not move tables across arclight catalogs`), the pipeline was engineered to deploy securely within `meridian_tnn`. 
* **DLT Auto Loader Schema Management:** Stripped the explicit `cloudFiles.schemaLocation` parameter from the streaming reads. DLT natively manages schema inference and checkpoints internally, preventing orphaned folder metadata collisions during full refreshes.
* **Data Quality Divert (Quarantine):** Rather than failing the pipeline on bad data, failed records are actively diverted to `ops.quarantine_store_returns` using `.filter("is_valid = False")` for data stewardship review.

---

## 7. Deviations from the Brief

* **Single Catalog usage for Prod:** As documented in the design decisions, the `prod` DAB target points to `meridian_tnn` instead of an isolated `meridian_prod` catalog. This was a mandatory deviation to accommodate Databricks Free Edition's inability to migrate Arclight staging tables across catalogs.
* **Resource Limits Workaround:** Encountered `CLUSTER_CREATION_RESOURCE_EXHAUSTED` due to overlapping job schedules and active Serverless SQL warehouses. Paused the schedule and enforced `max_concurrent_runs: 1` in the orchestrator YAML.

---

## 8. Official Documentation References

* [Databricks Asset Bundles (DABs)](https://docs.databricks.com/en/dev-tools/bundles/index.html)
* [Delta Live Tables (DLT) Python API](https://docs.databricks.com/en/delta-live-tables/python-ref.html)
* [Apply Changes API (SCD Type 2)](https://docs.databricks.com/en/delta-live-tables/python-ref.html#apply-changes)
* [Unity Catalog Row Filters & Column Masks](https://docs.databricks.com/en/data-governance/unity-catalog/row-and-column-filters.html)
* [Databricks Free Edition Limitations](https://docs.databricks.com/en/free-edition.html)
