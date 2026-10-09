-- =============================================================================
-- Wide World Importers (WWI) - OLAP Data Transformation & Loading Script
-- Reads from normalized OLTP schemas (application, warehouse, sales)
-- Transforms and loads into Dimensional Model (olap schema)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. TRUNCATE OLAP TABLES (Facts first, then Dimensions)
-- -----------------------------------------------------------------------------
TRUNCATE TABLE 
    olap.fact_order,
    olap.fact_sale
CASCADE;

TRUNCATE TABLE 
    olap.dim_date,
    olap.dim_city,
    olap.dim_customer,
    olap.dim_employee,
    olap.dim_stock_item
CASCADE;

-- -----------------------------------------------------------------------------
-- 2. POPULATE DIMENSION: dim_date (Calendar & Fiscal Nov 1)
-- -----------------------------------------------------------------------------

-- Fallback unknown date
INSERT INTO olap.dim_date (
    date_key, calendar_date, day_number, day_name, weekday_number, is_weekend,
    calendar_month_number, calendar_month_name, calendar_quarter, calendar_year,
    fiscal_month_number, fiscal_quarter, fiscal_year
)
VALUES (0, '1900-01-01', 1, 'Unknown', 1, FALSE, 1, 'Unknown', 1, 1900, 1, 1, 1900)
ON CONFLICT (date_key) DO NOTHING;

-- Date generator 2012 through 2017
INSERT INTO olap.dim_date (
    date_key, calendar_date, day_number, day_name, weekday_number, is_weekend,
    calendar_month_number, calendar_month_name, calendar_quarter, calendar_year,
    fiscal_month_number, fiscal_quarter, fiscal_year
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT AS date_key,
    d::DATE AS calendar_date,
    EXTRACT(DAY FROM d)::INT AS day_number,
    TRIM(TO_CHAR(d, 'Day')) AS day_name,
    EXTRACT(ISODOW FROM d)::INT AS weekday_number,
    CASE WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN TRUE ELSE FALSE END AS is_weekend,
    EXTRACT(MONTH FROM d)::INT AS calendar_month_number,
    TRIM(TO_CHAR(d, 'Month')) AS calendar_month_name,
    EXTRACT(QUARTER FROM d)::INT AS calendar_quarter,
    EXTRACT(YEAR FROM d)::INT AS calendar_year,
    -- Fiscal calendar calculation (starts Nov 1)
    CASE 
        WHEN EXTRACT(MONTH FROM d) >= 11 THEN EXTRACT(MONTH FROM d)::INT - 10 
        ELSE EXTRACT(MONTH FROM d)::INT + 2 
    END AS fiscal_month_number,
    CASE 
        WHEN EXTRACT(MONTH FROM d) IN (11, 12, 1) THEN 1
        WHEN EXTRACT(MONTH FROM d) IN (2, 3, 4) THEN 2
        WHEN EXTRACT(MONTH FROM d) IN (5, 6, 7) THEN 3
        ELSE 4
    END AS fiscal_quarter,
    CASE 
        WHEN EXTRACT(MONTH FROM d) >= 11 THEN EXTRACT(YEAR FROM d)::INT + 1 
        ELSE EXTRACT(YEAR FROM d)::INT 
    END AS fiscal_year
FROM GENERATE_SERIES('2012-01-01'::DATE, '2017-12-31'::DATE, INTERVAL '1 day') AS s(d)
ON CONFLICT (date_key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3. POPULATE DIMENSION: dim_employee
-- -----------------------------------------------------------------------------

-- Unknown employee
INSERT INTO olap.dim_employee (employee_key, person_id, full_name, preferred_name, is_employee, is_salesperson)
OVERRIDING SYSTEM VALUE
VALUES (0, 0, 'Unknown / Not Applicable', 'Unknown', FALSE, FALSE)
ON CONFLICT (employee_key) DO NOTHING;

-- Operational employees & salespeople
INSERT INTO olap.dim_employee (person_id, full_name, preferred_name, is_employee, is_salesperson)
SELECT 
    person_id,
    full_name,
    preferred_name,
    is_employee,
    is_salesperson
FROM application.people
ORDER BY person_id;

-- -----------------------------------------------------------------------------
-- 4. POPULATE DIMENSION: dim_city
-- -----------------------------------------------------------------------------

-- Unknown city
INSERT INTO olap.dim_city (
    city_key, city_id, city_name, state_province_code, state_province_name, country_name,
    continent, sales_territory, region, subregion, latitude, longitude, latest_recorded_population
)
OVERRIDING SYSTEM VALUE
VALUES (0, 0, 'Unknown City', 'NA', 'Unknown State', 'Unknown Country', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 0.0, 0.0, 0)
ON CONFLICT (city_key) DO NOTHING;

-- Cleaned geographic hierarchy
INSERT INTO olap.dim_city (
    city_id, city_name, state_province_code, state_province_name, country_name,
    continent, sales_territory, region, subregion, latitude, longitude, latest_recorded_population
)
SELECT 
    c.city_id,
    c.city_name,
    sp.state_province_code,
    sp.state_province_name,
    co.country_name,
    co.continent,
    sp.sales_territory,
    co.region,
    co.subregion,
    NULLIF(REPLACE(c.latitude, ',', '.'), '')::NUMERIC(10, 7),
    NULLIF(REPLACE(c.longitude, ',', '.'), '')::NUMERIC(10, 7),
    c.latest_recorded_population
FROM application.cities c
JOIN application.state_provinces sp ON c.state_province_id = sp.state_province_id
JOIN application.countries co ON sp.country_id = co.country_id
ORDER BY c.city_id;

-- -----------------------------------------------------------------------------
-- 5. POPULATE DIMENSION: dim_stock_item
-- -----------------------------------------------------------------------------

-- Unknown product
INSERT INTO olap.dim_stock_item (
    stock_item_key, stock_item_id, stock_item_name, supplier_id, color_name,
    unit_package_type, outer_package_type, brand, size, lead_time_days,
    quantity_per_outer, is_chiller_stock, barcode, tax_rate, unit_price,
    recommended_retail_price, typical_weight_per_unit
)
OVERRIDING SYSTEM VALUE
VALUES (0, 0, 'Unknown Product', NULL, 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 0, 0, FALSE, NULL, 0.0, 0.0, 0.0, 0.0)
ON CONFLICT (stock_item_key) DO NOTHING;

-- Flattened product attributes
INSERT INTO olap.dim_stock_item (
    stock_item_id, stock_item_name, supplier_id, color_name,
    unit_package_type, outer_package_type, brand, size, lead_time_days,
    quantity_per_outer, is_chiller_stock, barcode, tax_rate, unit_price,
    recommended_retail_price, typical_weight_per_unit
)
SELECT 
    s.stock_item_id,
    s.stock_item_name,
    s.supplier_id,
    c.color_name,
    upt.package_type_name AS unit_package_type,
    opt.package_type_name AS outer_package_type,
    COALESCE(s.brand, 'N/A') AS brand,
    COALESCE(s.size, 'N/A') AS size,
    s.lead_time_days,
    s.quantity_per_outer,
    s.is_chiller_stock,
    s.barcode,
    s.tax_rate,
    s.unit_price,
    s.recommended_retail_price,
    s.typical_weight_per_unit
FROM warehouse.stock_items s
LEFT JOIN warehouse.colors c ON s.color_id = c.color_id
LEFT JOIN warehouse.package_types upt ON s.unit_package_id = upt.package_type_id
LEFT JOIN warehouse.package_types opt ON s.outer_package_id = opt.package_type_id
ORDER BY s.stock_item_id;

-- -----------------------------------------------------------------------------
-- 6. POPULATE DIMENSION: dim_customer (SCD Type 2 Initial Load)
-- -----------------------------------------------------------------------------

-- Unknown customer
INSERT INTO olap.dim_customer (
    customer_key, customer_id, customer_name, customer_category_name, buying_group_name,
    delivery_city_name, delivery_state_province_name, credit_limit, account_opened_date,
    standard_discount_percentage, payment_days, phone_number, website_url,
    delivery_address_line, valid_from, valid_to, is_current
)
OVERRIDING SYSTEM VALUE
VALUES (0, 0, 'Unknown Customer', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 0.0, '1900-01-01', 0.0, 0, 'Unknown', 'Unknown', 'Unknown', '1900-01-01', '9999-12-31', TRUE)
ON CONFLICT (customer_key) DO NOTHING;

-- Initial SCD2 customers active from account_opened_date
INSERT INTO olap.dim_customer (
    customer_id, customer_name, customer_category_name, buying_group_name,
    delivery_city_name, delivery_state_province_name, credit_limit, account_opened_date,
    standard_discount_percentage, payment_days, phone_number, website_url,
    delivery_address_line, valid_from, valid_to, is_current
)
SELECT 
    c.customer_id,
    c.customer_name,
    cat.customer_category_name,
    COALESCE(bg.buying_group_name, 'N/A') AS buying_group_name,
    ct.city_name AS delivery_city_name,
    sp.state_province_name AS delivery_state_province_name,
    c.credit_limit,
    c.account_opened_date,
    c.standard_discount_percentage,
    c.payment_days,
    c.phone_number,
    c.website_url,
    c.delivery_address_line,
    c.account_opened_date AS valid_from,
    '9999-12-31'::DATE AS valid_to,
    TRUE AS is_current
FROM sales.customers c
JOIN sales.customer_categories cat ON c.customer_category_id = cat.customer_category_id
LEFT JOIN sales.buying_groups bg ON c.buying_group_id = bg.buying_group_id
LEFT JOIN application.cities ct ON c.delivery_city_id = ct.city_id
LEFT JOIN application.state_provinces sp ON ct.state_province_id = sp.state_province_id
ORDER BY c.customer_id;

-- -----------------------------------------------------------------------------
-- 7. POPULATE FACT: fact_order (Grain: One row per Order Line)
-- -----------------------------------------------------------------------------

INSERT INTO olap.fact_order (
    order_id, order_line_id, customer_purchase_order_number,
    order_date_key, customer_key, stock_item_key,
    salesperson_key, picked_by_key, delivery_city_key,
    quantity, unit_price, tax_rate, picked_quantity,
    is_undersupply_backordered, backorder_order_id, picking_completed_when
)
SELECT 
    o.order_id,
    ol.order_line_id,
    o.customer_purchase_order_number,
    TO_CHAR(o.order_date, 'YYYYMMDD')::INT AS order_date_key,
    COALESCE(dc.customer_key, 0) AS customer_key,
    COALESCE(ds.stock_item_key, 0) AS stock_item_key,
    COALESCE(de_sp.employee_key, 0) AS salesperson_key,
    COALESCE(de_pb.employee_key, 0) AS picked_by_key,
    COALESCE(dcity.city_key, 0) AS delivery_city_key,
    ol.quantity,
    ol.unit_price,
    ol.tax_rate,
    ol.picked_quantity,
    o.is_undersupply_backordered,
    o.backorder_order_id,
    ol.picking_completed_when
FROM sales.orders o
JOIN sales.order_lines ol ON o.order_id = ol.order_id
JOIN sales.customers c ON o.customer_id = c.customer_id
-- Resolve SCD2 Customer Dimension active on order date
LEFT JOIN olap.dim_customer dc 
    ON o.customer_id = dc.customer_id 
    AND o.order_date >= dc.valid_from 
    AND o.order_date <= dc.valid_to
LEFT JOIN olap.dim_stock_item ds ON ol.stock_item_id = ds.stock_item_id
LEFT JOIN olap.dim_employee de_sp ON o.salesperson_person_id = de_sp.person_id
LEFT JOIN olap.dim_employee de_pb ON o.picked_by_person_id = de_pb.person_id
LEFT JOIN olap.dim_city dcity ON c.delivery_city_id = dcity.city_id;

-- -----------------------------------------------------------------------------
-- 8. POPULATE FACT: fact_sale (Grain: One row per Invoice Line)
-- -----------------------------------------------------------------------------

INSERT INTO olap.fact_sale (
    invoice_id, invoice_line_id, order_id, customer_purchase_order_number,
    invoice_date_key, customer_key, stock_item_key, salesperson_key,
    delivery_city_key, quantity, unit_price, tax_rate, tax_amount,
    line_profit, extended_price, days_order_to_invoice,
    days_invoice_to_delivery, confirmed_delivery_time
)
SELECT 
    inv.invoice_id,
    il.invoice_line_id,
    inv.order_id,
    inv.customer_purchase_order_number,
    TO_CHAR(inv.invoice_date, 'YYYYMMDD')::INT AS invoice_date_key,
    COALESCE(dc.customer_key, 0) AS customer_key,
    COALESCE(ds.stock_item_key, 0) AS stock_item_key,
    COALESCE(de_sp.employee_key, 0) AS salesperson_key,
    COALESCE(dcity.city_key, 0) AS delivery_city_key,
    il.quantity,
    il.unit_price,
    il.tax_rate,
    il.tax_amount,
    il.line_profit,
    il.extended_price,
    CASE WHEN o.order_date IS NOT NULL THEN (inv.invoice_date - o.order_date) ELSE NULL END AS days_order_to_invoice,
    CASE 
        WHEN inv.confirmed_delivery_time IS NOT NULL 
        THEN EXTRACT(DAY FROM (inv.confirmed_delivery_time - inv.invoice_date::timestamp))::INT 
        ELSE NULL 
    END AS days_invoice_to_delivery,
    inv.confirmed_delivery_time
FROM sales.invoices inv
JOIN sales.invoice_lines il ON inv.invoice_id = il.invoice_id
LEFT JOIN sales.orders o ON inv.order_id = o.order_id
JOIN sales.customers c ON inv.customer_id = c.customer_id
-- Resolve SCD2 Customer Dimension active on invoice date
LEFT JOIN olap.dim_customer dc 
    ON inv.customer_id = dc.customer_id 
    AND inv.invoice_date >= dc.valid_from 
    AND inv.invoice_date <= dc.valid_to
LEFT JOIN olap.dim_stock_item ds ON il.stock_item_id = ds.stock_item_id
LEFT JOIN olap.dim_employee de_sp ON inv.salesperson_person_id = de_sp.person_id
LEFT JOIN olap.dim_city dcity ON c.delivery_city_id = dcity.city_id;

COMMIT;
