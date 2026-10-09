-- =============================================================================
-- Wide World Importers (WWI) - Data Quality & Integrity Test Suite
-- Validates:
-- 1. Primary Keys are not null
-- 2. Business Keys expected to be unique do not contain duplicates
-- 3. Foreign key referential integrity
-- 4. Quantity and monetary values meet validity rules
-- 5. Transaction date sequences are valid
-- 6. Fact records resolve to required dimensions
-- 7. SCD2 exactly one current record per business key
-- 8. SCD2 effective-date ranges do not overlap
-- =============================================================================

CREATE TABLE IF NOT EXISTS olap.dq_test_results (
    test_run_id         VARCHAR(100) NOT NULL,
    check_name          VARCHAR(100) NOT NULL,
    failure_count       BIGINT NOT NULL,
    status              VARCHAR(20) NOT NULL,
    executed_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
DECLARE
    v_run_id VARCHAR(100) := 'DQ-' || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD-HH24MISS');
    v_total_failures INT;
BEGIN
    -- Execute all checks and store results
    INSERT INTO olap.dq_test_results (test_run_id, check_name, failure_count, status)
    WITH dq_checks AS (
        -- 1. Primary Keys Not Null
        SELECT 'fact_order_null_pk' AS check_name, count(*) AS failure_count FROM olap.fact_order WHERE order_line_key IS NULL
        UNION ALL SELECT 'fact_sale_null_pk', count(*) FROM olap.fact_sale WHERE sale_key IS NULL
        UNION ALL SELECT 'dim_customer_null_pk', count(*) FROM olap.dim_customer WHERE customer_key IS NULL
        UNION ALL SELECT 'dim_stock_item_null_pk', count(*) FROM olap.dim_stock_item WHERE stock_item_key IS NULL
        UNION ALL SELECT 'dim_city_null_pk', count(*) FROM olap.dim_city WHERE city_key IS NULL
        UNION ALL SELECT 'dim_employee_null_pk', count(*) FROM olap.dim_employee WHERE employee_key IS NULL
        UNION ALL SELECT 'dim_date_null_pk', count(*) FROM olap.dim_date WHERE date_key IS NULL

        -- 2. Business Key Uniqueness (in active dimensions)
        UNION ALL SELECT 'dim_customer_duplicate_active_bk', count(*) FROM (SELECT customer_id FROM olap.dim_customer WHERE is_current = TRUE GROUP BY customer_id HAVING count(*) > 1) t
        UNION ALL SELECT 'dim_stock_item_duplicate_bk', count(*) FROM (SELECT stock_item_id FROM olap.dim_stock_item WHERE stock_item_id > 0 GROUP BY stock_item_id HAVING count(*) > 1) t
        UNION ALL SELECT 'dim_city_duplicate_bk', count(*) FROM (SELECT city_id FROM olap.dim_city WHERE city_id > 0 GROUP BY city_id HAVING count(*) > 1) t
        UNION ALL SELECT 'dim_employee_duplicate_bk', count(*) FROM (SELECT person_id FROM olap.dim_employee WHERE person_id > 0 GROUP BY person_id HAVING count(*) > 1) t

        -- 3. Referential Integrity (Facts point to valid Dimensions)
        UNION ALL SELECT 'fact_order_invalid_customer_fk', count(*) FROM olap.fact_order fo LEFT JOIN olap.dim_customer dc ON fo.customer_key = dc.customer_key WHERE dc.customer_key IS NULL
        UNION ALL SELECT 'fact_order_invalid_stock_fk', count(*) FROM olap.fact_order fo LEFT JOIN olap.dim_stock_item ds ON fo.stock_item_key = ds.stock_item_key WHERE ds.stock_item_key IS NULL
        UNION ALL SELECT 'fact_order_invalid_date_fk', count(*) FROM olap.fact_order fo LEFT JOIN olap.dim_date d ON fo.order_date_key = d.date_key WHERE d.date_key IS NULL
        UNION ALL SELECT 'fact_sale_invalid_customer_fk', count(*) FROM olap.fact_sale fs LEFT JOIN olap.dim_customer dc ON fs.customer_key = dc.customer_key WHERE dc.customer_key IS NULL
        UNION ALL SELECT 'fact_sale_invalid_stock_fk', count(*) FROM olap.fact_sale fs LEFT JOIN olap.dim_stock_item ds ON fs.stock_item_key = ds.stock_item_key WHERE ds.stock_item_key IS NULL
        UNION ALL SELECT 'fact_sale_invalid_date_fk', count(*) FROM olap.fact_sale fs LEFT JOIN olap.dim_date d ON fs.invoice_date_key = d.date_key WHERE d.date_key IS NULL

        -- 4. Quantity & Monetary Rules
        UNION ALL SELECT 'fact_order_negative_quantity', count(*) FROM olap.fact_order WHERE quantity <= 0
        UNION ALL SELECT 'fact_order_negative_price', count(*) FROM olap.fact_order WHERE unit_price < 0
        UNION ALL SELECT 'fact_sale_negative_quantity', count(*) FROM olap.fact_sale WHERE quantity <= 0
        UNION ALL SELECT 'fact_sale_negative_price', count(*) FROM olap.fact_sale WHERE unit_price < 0 OR extended_price < 0

        -- 5. Reasonable Transaction Date Sequences
        UNION ALL SELECT 'fact_sale_negative_days_to_invoice', count(*) FROM olap.fact_sale WHERE days_order_to_invoice < 0
        UNION ALL SELECT 'fact_order_invalid_expected_delivery', count(*) FROM sales.orders WHERE expected_delivery_date < order_date

        -- 6. Completeness: No NULL foreign keys
        UNION ALL SELECT 'fact_order_null_fk', count(*) FROM olap.fact_order WHERE order_date_key IS NULL OR customer_key IS NULL OR stock_item_key IS NULL OR delivery_city_key IS NULL
        UNION ALL SELECT 'fact_sale_null_fk', count(*) FROM olap.fact_sale WHERE invoice_date_key IS NULL OR customer_key IS NULL OR stock_item_key IS NULL OR delivery_city_key IS NULL

        -- 7. SCD2 Exactly One Current Record
        UNION ALL SELECT 'scd2_multiple_current_records', count(*) FROM (SELECT customer_id FROM olap.dim_customer WHERE is_current = TRUE GROUP BY customer_id HAVING count(*) > 1) t

        -- 8. SCD2 Non-Overlapping Dates
        UNION ALL SELECT 'scd2_invalid_date_range', count(*) FROM olap.dim_customer WHERE valid_from > valid_to
        UNION ALL SELECT 'scd2_overlapping_ranges', count(*) FROM (SELECT a.customer_id FROM olap.dim_customer a JOIN olap.dim_customer b ON a.customer_id = b.customer_id AND a.customer_key < b.customer_key WHERE a.valid_from <= b.valid_to AND a.valid_to >= b.valid_from AND a.customer_id > 0) t
    )
    SELECT 
        v_run_id,
        check_name,
        failure_count,
        CASE WHEN failure_count = 0 THEN 'PASSED' ELSE 'FAILED' END
    FROM dq_checks;

    -- Check if any critical check failed
    SELECT COALESCE(SUM(failure_count), 0) INTO v_total_failures
    FROM olap.dq_test_results
    WHERE test_run_id = v_run_id;

    IF v_total_failures > 0 THEN
        RAISE EXCEPTION 'Data Quality Suite Failed! Total anomalies detected: %', v_total_failures;
    ELSE
        RAISE NOTICE 'Data Quality Suite PASSED! All assertions verified with 0 anomalies.';
    END IF;
END $$;

-- Summary Output
SELECT check_name, failure_count, status 
FROM olap.dq_test_results 
WHERE test_run_id = (SELECT MAX(test_run_id) FROM olap.dq_test_results)
ORDER BY check_name;
