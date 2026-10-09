-- =============================================================================
-- Wide World Importers (WWI) - Analytical Business Queries
-- Solves the 10 Business Questions defined in Section 7 of the Case Study
-- Target Schema: olap (Star Schema)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Question 1: What are total sales, quantity sold, and profit by month and fiscal year?
-- Note: WWI's fiscal year begins November 1.
-- -----------------------------------------------------------------------------
SELECT 
    d.fiscal_year,
    d.fiscal_month_number,
    d.calendar_year,
    d.calendar_month_name,
    COUNT(DISTINCT fs.invoice_id)               AS total_invoices,
    SUM(fs.quantity)                            AS total_quantity_sold,
    ROUND(SUM(fs.extended_price), 2)            AS total_sales_revenue,
    ROUND(SUM(fs.line_profit), 2)               AS total_profit
FROM olap.fact_sale fs
JOIN olap.dim_date d ON fs.invoice_date_key = d.date_key
GROUP BY d.fiscal_year, d.fiscal_month_number, d.calendar_year, d.calendar_month_name
ORDER BY d.fiscal_year, d.fiscal_month_number;


-- -----------------------------------------------------------------------------
-- Question 2: Which products and product categories generate the highest sales and profit?
-- -----------------------------------------------------------------------------
SELECT 
    ds.stock_item_name,
    ds.brand,
    ds.color_name,
    SUM(fs.quantity)                            AS total_quantity_sold,
    ROUND(SUM(fs.extended_price), 2)            AS total_revenue,
    ROUND(SUM(fs.line_profit), 2)               AS total_profit,
    ROUND((SUM(fs.line_profit) / NULLIF(SUM(fs.extended_price), 0)) * 100, 2) AS profit_margin_pct
FROM olap.fact_sale fs
JOIN olap.dim_stock_item ds ON fs.stock_item_key = ds.stock_item_key
GROUP BY ds.stock_item_name, ds.brand, ds.color_name
ORDER BY total_revenue DESC
LIMIT 15;


-- -----------------------------------------------------------------------------
-- Question 3: Which customers and customer categories contribute the most revenue?
-- -----------------------------------------------------------------------------
-- A. By Customer Category:
SELECT 
    dc.customer_category_name,
    COUNT(DISTINCT dc.customer_id)              AS customer_count,
    COUNT(fs.sale_key)                          AS invoice_lines_count,
    ROUND(SUM(fs.extended_price), 2)            AS total_revenue,
    ROUND(SUM(fs.line_profit), 2)               AS total_profit
FROM olap.fact_sale fs
JOIN olap.dim_customer dc ON fs.customer_key = dc.customer_key
GROUP BY dc.customer_category_name
ORDER BY total_revenue DESC;

-- B. Top 10 Individual Customers:
SELECT 
    dc.customer_name,
    dc.customer_category_name,
    ROUND(SUM(fs.extended_price), 2)            AS total_revenue,
    ROUND(SUM(fs.line_profit), 2)               AS total_profit
FROM olap.fact_sale fs
JOIN olap.dim_customer dc ON fs.customer_key = dc.customer_key
GROUP BY dc.customer_name, dc.customer_category_name
ORDER BY total_revenue DESC
LIMIT 10;


-- -----------------------------------------------------------------------------
-- Question 4: How do sales and profit vary by city, state or province, and sales territory?
-- -----------------------------------------------------------------------------
SELECT 
    dc.sales_territory,
    dc.state_province_name,
    COUNT(DISTINCT dc.city_id)                  AS cities_with_sales,
    SUM(fs.quantity)                            AS total_quantity_sold,
    ROUND(SUM(fs.extended_price), 2)            AS total_sales_revenue,
    ROUND(SUM(fs.line_profit), 2)               AS total_profit
FROM olap.fact_sale fs
JOIN olap.dim_city dc ON fs.delivery_city_key = dc.city_key
GROUP BY dc.sales_territory, dc.state_province_name
ORDER BY total_sales_revenue DESC
LIMIT 15;


-- -----------------------------------------------------------------------------
-- Question 5: Which employees or salespeople manage the highest-value orders and sales?
-- -----------------------------------------------------------------------------
SELECT 
    de.person_id,
    de.full_name                                AS salesperson_name,
    COUNT(DISTINCT fs.invoice_id)               AS total_invoices_managed,
    SUM(fs.quantity)                            AS total_units_sold,
    ROUND(SUM(fs.extended_price), 2)            AS total_sales_value,
    ROUND(SUM(fs.line_profit), 2)               AS total_profit_generated
FROM olap.fact_sale fs
JOIN olap.dim_employee de ON fs.salesperson_key = de.employee_key
WHERE de.employee_key > 0
GROUP BY de.person_id, de.full_name
ORDER BY total_sales_value DESC;


-- -----------------------------------------------------------------------------
-- Question 6: What proportion of ordered quantities is later invoiced?
-- -----------------------------------------------------------------------------
WITH order_totals AS (
    SELECT SUM(quantity) AS total_ordered_qty FROM olap.fact_order
),
invoice_totals AS (
    SELECT SUM(quantity) AS total_invoiced_qty FROM olap.fact_sale
)
SELECT 
    ot.total_ordered_qty,
    it.total_invoiced_qty,
    ROUND((it.total_invoiced_qty::NUMERIC / ot.total_ordered_qty) * 100, 2) AS proportion_invoiced_pct,
    ROUND(((ot.total_ordered_qty - it.total_invoiced_qty)::NUMERIC / ot.total_ordered_qty) * 100, 2) AS proportion_uninvoiced_pct
FROM order_totals ot, invoice_totals it;


-- -----------------------------------------------------------------------------
-- Question 7: How long does it take, on average, for an order to be invoiced?
-- -----------------------------------------------------------------------------
SELECT 
    ROUND(AVG(days_order_to_invoice), 2)        AS avg_days_order_to_invoice,
    MIN(days_order_to_invoice)                  AS min_days,
    MAX(days_order_to_invoice)                  AS max_days,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_order_to_invoice) AS median_days_order_to_invoice
FROM olap.fact_sale
WHERE days_order_to_invoice IS NOT NULL;


-- -----------------------------------------------------------------------------
-- Question 8: Which orders contain backordered items, and what is their business impact?
-- -----------------------------------------------------------------------------
SELECT 
    COUNT(DISTINCT order_id)                    AS total_backordered_orders,
    SUM(quantity)                               AS backordered_quantity,
    ROUND(SUM(quantity * unit_price), 2)        AS backordered_revenue_value
FROM olap.fact_order
WHERE is_undersupply_backordered = TRUE OR backorder_order_id IS NOT NULL;


-- -----------------------------------------------------------------------------
-- Question 9: How have tracked customer or product attributes changed over time?
-- -----------------------------------------------------------------------------
SELECT 
    customer_id,
    customer_name,
    COUNT(*)                                    AS total_versions,
    STRING_AGG(
        customer_category_name || ' [Valid: ' || valid_from || ' to ' || valid_to || ']',
        '  ==>  ' 
        ORDER BY valid_from
    ) AS attribute_history
FROM olap.dim_customer
WHERE customer_id > 0
GROUP BY customer_id, customer_name
HAVING COUNT(*) > 1;


-- -----------------------------------------------------------------------------
-- Question 10: What were the correct historical dimension attributes associated with 
-- transactions before and after an SCD change?
-- -----------------------------------------------------------------------------
SELECT 
    dc.customer_id,
    dc.customer_name,
    dc.customer_category_name                   AS historical_category,
    dc.credit_limit,
    dc.valid_from,
    dc.valid_to,
    dc.is_current,
    COUNT(fs.sale_key)                          AS invoice_lines_count,
    ROUND(SUM(fs.extended_price), 2)            AS revenue_under_this_version
FROM olap.fact_sale fs
JOIN olap.dim_customer dc ON fs.customer_key = dc.customer_key
WHERE dc.customer_id = 832
GROUP BY dc.customer_id, dc.customer_name, dc.customer_category_name, dc.credit_limit, dc.valid_from, dc.valid_to, dc.is_current
ORDER BY dc.valid_from;
