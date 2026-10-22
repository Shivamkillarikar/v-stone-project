# Dimensional Model Design Note: Meridian Retail Analytics

## 1. Entities, Classification, and Grain

| Entity | Layer / Table | Type | Grain | Primary Key | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Store Returns** | `gold.fact_store_returns` | Fact | One record per item returned per transaction ticket | `(ticket_number, item_sk)` | Core transactional fact capturing returned merchandise, refund amounts, and operational flags. |
| **Customer** | `gold.dim_customer` | Dimension | One record per registered customer | `c_customer_sk` | Customer profile attributes, contact channels, and identity keys. |
| **Item** | `gold.dim_item` | Dimension | One record per product SKU/item | `i_item_sk` | Product metadata including item descriptions, categories, classes, and prices. |
| **Store** | `gold.dim_store` | Dimension | One record per physical retail location | `s_store_sk` | Store geography, location identifiers, and operational state divisions. |
| **Date** | `gold.dim_date` | Dimension | One record per calendar day | `d_date_sk` | Calendar dimension enabling time-intelligence aggregations (day, month, quarter, year). |
| **Return Reason** | `gold.dim_reason` | Dimension | One record per unique return reason | `r_reason_sk` | Reason definitions tracked via SCD Type 2; exposed as current active records (`__END_AT IS NULL`). |

---

## 2. Row-Filter Dimension

* **Secured Dimension:** `dim_store` (`s_state`) / `fact_store_returns` (`store_state`)
* **Policy Rule:** Row-level security restricts non-administrative users to regional territory records:
  * **Regional Analysts (`tn_analyst`):** Filtered strictly to `s_state = 'TN'`.
  * **Administrators / National Viewers (`admin` / `p08`):** Full nationwide access without row restrictions.
* **Mechanism:** Unity Catalog SQL Row Filter applied via `IS_ACCOUNT_GROUP_MEMBER('admin')`.

---

## 3. Sensitive Columns & Governance

Dynamic column masking is applied at the consumption layer (`gold.dim_customer`) using a Unity Catalog SQL UDF (`customer_pii_mask`) to protect personally identifiable information (PII):

| Target Column | Entity | Sensitivity Type | Masking Behavior |
| :--- | :--- | :--- | :--- |
| `c_first_name` | `dim_customer` | PII (Direct Identifier) | Unmasked for `p08`/`admin`; partial mask (`J*****`) for analysts. |
| `c_last_name` | `dim_customer` | PII (Direct Identifier) | Unmasked for `p08`/`admin`; partial mask (`D*****`) for analysts. |
| `c_email_address` | `dim_customer` | PII (Contact Info) | Masked entirely (`***@***.***`) for unauthorized querying groups. |

---

## 4. Key Performance Indicators (KPIs)

| KPI Name | Business Definition | Calculation / Logic |
| :--- | :--- | :--- |
| **Total Refund Value** | Aggregate monetary volume disbursed for returned merchandise. | `SUM(refunded_cash)` |
| **Total Return Tickets** | Distinct volume of customer return transactions processed. | `COUNT(DISTINCT ticket_number)` |
| **Total Units Returned** | Aggregate quantity of physical product units returned to stores. | `SUM(return_quantity)` |
| **Average Refund per Ticket** | Mean financial payout per discrete return transaction. | `Total Refund Value / Total Return Tickets` |
| **Orphan Return Rate** | Percentage of returns without an associated Bronze sale record. | `(COUNT_IF(is_orphan_return = True) / COUNT(*)) * 100` |
