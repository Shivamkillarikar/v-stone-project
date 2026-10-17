CREATE OR REPLACE VIEW meridian_tnn.gold.returns_metric_view (
    store_name COMMENT 'Dimension: Store name for analyzing returns per store (defaults to Unknown if unassigned)',
    store_state COMMENT 'Dimension: Store state code used for geographic slicing and row-level security',
    item_category COMMENT 'Dimension: Product category for category-level loss analytics',
    reason_desc COMMENT 'Dimension: Return reason description for top-reason analysis',
    -- Assigned KPI Measures
    total_return_value COMMENT 'KPI (Return Value): Total monetary value of refunds issued',
    total_returns_count COMMENT 'KPI (Returns per Store / Volume): Total count of return events',
    total_units_returned COMMENT 'KPI (Volume): Total quantity of items returned',
    refund_mix_ratio COMMENT 'KPI (Refund Mix - Ratio): Average refund cash per item returned',
    high_frequency_returners COMMENT 'KPI (High-Frequency Returner Count): Distinct customer count to identify return patterns'
)
COMMENT 'Governed metric view modeling returns abuse and loss KPIs across conformed dimensions'
AS
SELECT 
    COALESCE(d.s_store_name, 'Unknown') AS store_name,
    COALESCE(d.s_state, 'Unknown') AS store_state,
    COALESCE(i.i_category, 'Unknown') AS item_category,
    COALESCE(r.r_reason_desc, 'Unknown') AS reason_desc,
    -- 1. Return Value
    SUM(f.refunded_cash) AS total_return_value,
    -- 2. Returns per Store / Event Count
    COUNT(f.ticket_number) AS total_returns_count,
    -- 3. Total Items Returned
    SUM(f.return_quantity) AS total_units_returned,
    -- 4. Refund Mix (Ratio)
    ROUND(SUM(f.refunded_cash) / NULLIF(SUM(f.return_quantity), 0), 2) AS refund_mix_ratio,
    -- 5. High-Frequency Returner Count
    COUNT(DISTINCT f.customer_sk) AS high_frequency_returners

FROM meridian_tnn.gold.fact_store_returns f
LEFT JOIN meridian_tnn.gold.dim_store d 
    ON f.store_sk = d.s_store_sk
LEFT JOIN meridian_tnn.gold.dim_item i 
    ON f.item_sk = i.i_item_sk
LEFT JOIN (
    SELECT r_reason_sk, r_reason_desc 
    FROM meridian_tnn.gold.dim_reason 
    WHERE __END_AT IS NULL
) r 
    ON f.reason_sk = r.r_reason_sk
GROUP BY 
    COALESCE(d.s_store_name, 'Unknown'), 
    COALESCE(d.s_state, 'Unknown'),
    COALESCE(i.i_category, 'Unknown'),
    COALESCE(r.r_reason_desc, 'Unknown');

SELECT 
    'Metric View' AS calculation_source,
    SUM(total_return_value) AS total_return_value,
    SUM(total_units_returned) AS total_units_returned
FROM meridian_tnn.gold.returns_metric_view

UNION ALL

SELECT 
    'Gold Fact Table' AS calculation_source,
    SUM(refunded_cash) AS total_return_value,
    SUM(return_quantity) AS total_units_returned
FROM meridian_tnn.gold.fact_store_returns;