-- =============================================================================
-- Wide World Importers (WWI) - OLTP Data Ingestion Script
-- Loads raw CSV files into normalized PostgreSQL tables in dependency order
-- =============================================================================

SET datestyle = 'DMY';

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. CLEAN EXISTING DATA (CASCADE)
-- -----------------------------------------------------------------------------
TRUNCATE TABLE 
    sales.customer_transactions,
    sales.invoice_lines,
    sales.invoices,
    sales.order_lines,
    sales.orders,
    sales.customers,
    sales.buying_groups,
    sales.customer_categories,
    warehouse.stock_items,
    warehouse.package_types,
    warehouse.colors,
    application.cities,
    application.state_provinces,
    application.countries,
    application.people,
    application.delivery_methods,
    application.payment_methods,
    application.transaction_types
CASCADE;

-- -----------------------------------------------------------------------------
-- 2. APPLICATION SCHEMAS
-- -----------------------------------------------------------------------------

COPY application.countries (
    country_id, country_name, formal_name, latest_recorded_population,
    continent, region, subregion
)
FROM '/data/Application/Application.Countries.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY application.delivery_methods (
    delivery_method_id, delivery_method_name
)
FROM '/data/Application/Application.DeliveryMethods.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY application.payment_methods (
    payment_method_id, payment_method_name
)
FROM '/data/Application/Application.PaymentMethods.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY application.transaction_types (
    transaction_type_id, transaction_type_name
)
FROM '/data/Application/Application.TransactionTypes.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY application.people (
    person_id, full_name, preferred_name, search_name, is_employee, is_salesperson
)
FROM '/data/Application/Application.People.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY application.state_provinces (
    state_province_id, state_province_code, state_province_name,
    country_id, sales_territory, latest_recorded_population
)
FROM '/data/Application/Application.StateProvinces.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY application.cities (
    city_id, city_name, state_province_id, latitude, longitude, latest_recorded_population
)
FROM '/data/Application/Application.Cities.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

-- -----------------------------------------------------------------------------
-- 3. WAREHOUSE SCHEMAS
-- -----------------------------------------------------------------------------

COPY warehouse.colors (
    color_id, color_name
)
FROM '/data/Warehouse/Warehouse.Colors.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY warehouse.package_types (
    package_type_id, package_type_name
)
FROM '/data/Warehouse/Warehouse.PackageTypes.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY warehouse.stock_items (
    stock_item_id, stock_item_name, supplier_id, color_id, unit_package_id,
    outer_package_id, brand, size, lead_time_days, quantity_per_outer,
    is_chiller_stock, barcode, tax_rate, unit_price, recommended_retail_price,
    typical_weight_per_unit
)
FROM '/data/Warehouse/Warehouse.StockItems.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

-- -----------------------------------------------------------------------------
-- 4. SALES SCHEMAS
-- -----------------------------------------------------------------------------

COPY sales.buying_groups (
    buying_group_id, buying_group_name
)
FROM '/data/Sales/Sales.BuyingGroups.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY sales.customer_categories (
    customer_category_id, customer_category_name
)
FROM '/data/Sales/Sales.CustomerCategories.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY sales.customers (
    customer_id, customer_name, bill_to_customer_id, customer_category_id,
    buying_group_id, primary_contact_person_id, alternate_contact_person_id,
    delivery_method_id, delivery_city_id, credit_limit, account_opened_date,
    standard_discount_percentage, is_statement_sent, is_on_credit_hold,
    payment_days, phone_number, website_url, delivery_address_line,
    delivery_location_lat, delivery_location_long
)
FROM '/data/Sales/Sales.Customers.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY sales.orders (
    order_id, customer_id, salesperson_person_id, picked_by_person_id,
    contact_person_id, backorder_order_id, order_date, expected_delivery_date,
    customer_purchase_order_number, is_undersupply_backordered, picking_completed_when
)
FROM '/data/Sales/Sales.Orders.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY sales.order_lines (
    order_line_id, order_id, stock_item_id, description, package_type_id,
    quantity, unit_price, tax_rate, picked_quantity, picking_completed_when
)
FROM '/data/Sales/Sales.OrderLines.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY sales.invoices (
    invoice_id, customer_id, bill_to_customer_id, order_id,
    delivery_method_id, contact_person_id, accounts_person_id,
    salesperson_person_id, packed_by_person_id, invoice_date,
    customer_purchase_order_number, delivery_instructions,
    total_dry_items, total_chiller_items, confirmed_delivery_time, confirmed_received_by
)
FROM '/data/Sales/Sales.Invoices.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY sales.invoice_lines (
    invoice_line_id, invoice_id, stock_item_id, description, package_type_id,
    quantity, unit_price, tax_rate, tax_amount, line_profit, extended_price
)
FROM '/data/Sales/Sales.InvoiceLines.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

COPY sales.customer_transactions (
    customer_transaction_id, customer_id, transaction_type_id, invoice_id,
    payment_method_id, transaction_date, amount_excluding_tax, tax_amount,
    transaction_amount, outstanding_balance, finalization_date, is_finalized
)
FROM '/data/Sales/Sales.CustomerTransactions.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ';', NULL 'NULL', ENCODING 'UTF8');

-- -----------------------------------------------------------------------------
-- 5. AUDIT LOGGING
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_run_id VARCHAR(100) := 'RUN-' || to_char(CURRENT_TIMESTAMP, 'YYYYMMDD-HH24MISS');
BEGIN
    INSERT INTO application.ingestion_log (pipeline_run_id, source_filename, target_table, records_loaded, status)
    VALUES
        (v_run_id, 'Application.Countries.csv', 'application.countries', (SELECT count(*) FROM application.countries), 'SUCCESS'),
        (v_run_id, 'Application.DeliveryMethods.csv', 'application.delivery_methods', (SELECT count(*) FROM application.delivery_methods), 'SUCCESS'),
        (v_run_id, 'Application.PaymentMethods.csv', 'application.payment_methods', (SELECT count(*) FROM application.payment_methods), 'SUCCESS'),
        (v_run_id, 'Application.TransactionTypes.csv', 'application.transaction_types', (SELECT count(*) FROM application.transaction_types), 'SUCCESS'),
        (v_run_id, 'Application.People.csv', 'application.people', (SELECT count(*) FROM application.people), 'SUCCESS'),
        (v_run_id, 'Application.StateProvinces.csv', 'application.state_provinces', (SELECT count(*) FROM application.state_provinces), 'SUCCESS'),
        (v_run_id, 'Application.Cities.csv', 'application.cities', (SELECT count(*) FROM application.cities), 'SUCCESS'),
        (v_run_id, 'Warehouse.Colors.csv', 'warehouse.colors', (SELECT count(*) FROM warehouse.colors), 'SUCCESS'),
        (v_run_id, 'Warehouse.PackageTypes.csv', 'warehouse.package_types', (SELECT count(*) FROM warehouse.package_types), 'SUCCESS'),
        (v_run_id, 'Warehouse.StockItems.csv', 'warehouse.stock_items', (SELECT count(*) FROM warehouse.stock_items), 'SUCCESS'),
        (v_run_id, 'Sales.BuyingGroups.csv', 'sales.buying_groups', (SELECT count(*) FROM sales.buying_groups), 'SUCCESS'),
        (v_run_id, 'Sales.CustomerCategories.csv', 'sales.customer_categories', (SELECT count(*) FROM sales.customer_categories), 'SUCCESS'),
        (v_run_id, 'Sales.Customers.csv', 'sales.customers', (SELECT count(*) FROM sales.customers), 'SUCCESS'),
        (v_run_id, 'Sales.Orders.csv', 'sales.orders', (SELECT count(*) FROM sales.orders), 'SUCCESS'),
        (v_run_id, 'Sales.OrderLines.csv', 'sales.order_lines', (SELECT count(*) FROM sales.order_lines), 'SUCCESS'),
        (v_run_id, 'Sales.Invoices.csv', 'sales.invoices', (SELECT count(*) FROM sales.invoices), 'SUCCESS'),
        (v_run_id, 'Sales.InvoiceLines.csv', 'sales.invoice_lines', (SELECT count(*) FROM sales.invoice_lines), 'SUCCESS'),
        (v_run_id, 'Sales.CustomerTransactions.csv', 'sales.customer_transactions', (SELECT count(*) FROM sales.customer_transactions), 'SUCCESS');
END $$;

COMMIT;
