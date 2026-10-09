-- =============================================================================
-- Wide World Importers (WWI) - SCD Type 2 Customer Pipeline Update
-- Compares source OLTP customer attributes against current OLAP dimension records,
-- expires modified records, inserts new versions, and aligns facts.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. IDENTIFY CHANGED CUSTOMERS (STAGING TEMP TABLE)
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE tmp_changed_customers ON COMMIT DROP AS
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
    -- Default effective change date (2015-01-01 for the simulated batch)
    COALESCE(c.account_opened_date, '2015-01-01'::DATE) AS change_date
FROM sales.customers c
JOIN sales.customer_categories cat ON c.customer_category_id = cat.customer_category_id
LEFT JOIN sales.buying_groups bg ON c.buying_group_id = bg.buying_group_id
LEFT JOIN application.cities ct ON c.delivery_city_id = ct.city_id
LEFT JOIN application.state_provinces sp ON ct.state_province_id = sp.state_province_id
JOIN olap.dim_customer curr 
    ON c.customer_id = curr.customer_id 
    AND curr.is_current = TRUE
WHERE 
    -- Detect changes in tracked historical attributes
    curr.customer_name              IS DISTINCT FROM c.customer_name
    OR curr.customer_category_name  IS DISTINCT FROM cat.customer_category_name
    OR curr.buying_group_name       IS DISTINCT FROM COALESCE(bg.buying_group_name, 'N/A')
    OR curr.credit_limit            IS DISTINCT FROM c.credit_limit
    OR curr.delivery_address_line   IS DISTINCT FROM c.delivery_address_line;

-- -----------------------------------------------------------------------------
-- 2. EXPIRE PREVIOUS VERSIONS (CLOSE OLD RECORDS)
-- -----------------------------------------------------------------------------
UPDATE olap.dim_customer dc
SET 
    valid_to   = '2014-12-31'::DATE,
    is_current = FALSE
FROM tmp_changed_customers chg
WHERE dc.customer_id = chg.customer_id
  AND dc.is_current = TRUE;

-- -----------------------------------------------------------------------------
-- 3. INSERT NEW VERSION OF CHANGED CUSTOMERS
-- -----------------------------------------------------------------------------
INSERT INTO olap.dim_customer (
    customer_id,
    customer_name,
    customer_category_name,
    buying_group_name,
    delivery_city_name,
    delivery_state_province_name,
    credit_limit,
    account_opened_date,
    standard_discount_percentage,
    payment_days,
    phone_number,
    website_url,
    delivery_address_line,
    valid_from,
    valid_to,
    is_current
)
SELECT 
    chg.customer_id,
    chg.customer_name,
    chg.customer_category_name,
    chg.buying_group_name,
    chg.delivery_city_name,
    chg.delivery_state_province_name,
    chg.credit_limit,
    chg.account_opened_date,
    chg.standard_discount_percentage,
    chg.payment_days,
    chg.phone_number,
    chg.website_url,
    chg.delivery_address_line,
    '2015-01-01'::DATE AS valid_from,
    '9999-12-31'::DATE AS valid_to,
    TRUE AS is_current
FROM tmp_changed_customers chg;

-- -----------------------------------------------------------------------------
-- 4. POINT-IN-TIME RE-ALIGNMENT FOR FACTS
-- Ensures orders and sales map to the version active on their transaction date
-- -----------------------------------------------------------------------------

-- Align Fact Order customer foreign keys
UPDATE olap.fact_order fo
SET customer_key = dc.customer_key
FROM olap.dim_customer dc
JOIN sales.orders o ON dc.customer_id = o.customer_id
WHERE fo.order_id = o.order_id
  AND o.order_date >= dc.valid_from
  AND o.order_date <= dc.valid_to
  AND fo.customer_key <> dc.customer_key;

-- Align Fact Sale customer foreign keys
UPDATE olap.fact_sale fs
SET customer_key = dc.customer_key
FROM olap.dim_customer dc
JOIN sales.invoices inv ON dc.customer_id = inv.customer_id
WHERE fs.invoice_id = inv.invoice_id
  AND inv.invoice_date >= dc.valid_from
  AND inv.invoice_date <= dc.valid_to
  AND fs.customer_key <> dc.customer_key;

COMMIT;
