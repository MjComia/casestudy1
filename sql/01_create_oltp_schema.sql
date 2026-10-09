-- =============================================================================
-- Wide World Importers (WWI) - OLTP Database Schema DDL
-- Target Engine: PostgreSQL 15+
-- =============================================================================

-- 1. Create schemas
CREATE SCHEMA IF NOT EXISTS application;
CREATE SCHEMA IF NOT EXISTS warehouse;
CREATE SCHEMA IF NOT EXISTS sales;

-- -----------------------------------------------------------------------------
-- 2. APPLICATION SCHEMA
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS application.countries (
    country_id                  INT PRIMARY KEY,
    country_name                VARCHAR(60) NOT NULL,
    formal_name                 VARCHAR(60) NOT NULL,
    latest_recorded_population  BIGINT,
    continent                   VARCHAR(30) NOT NULL,
    region                      VARCHAR(30) NOT NULL,
    subregion                   VARCHAR(30) NOT NULL
);

CREATE TABLE IF NOT EXISTS application.state_provinces (
    state_province_id           INT PRIMARY KEY,
    state_province_code         VARCHAR(5) NOT NULL,
    state_province_name         VARCHAR(50) NOT NULL,
    country_id                  INT NOT NULL REFERENCES application.countries(country_id),
    sales_territory             VARCHAR(50) NOT NULL,
    latest_recorded_population  BIGINT
);

CREATE TABLE IF NOT EXISTS application.cities (
    city_id                     INT PRIMARY KEY,
    city_name                   VARCHAR(50) NOT NULL,
    state_province_id           INT NOT NULL REFERENCES application.state_provinces(state_province_id),
    latitude                    VARCHAR(50),
    longitude                   VARCHAR(50),
    latest_recorded_population  BIGINT
);

CREATE TABLE IF NOT EXISTS application.delivery_methods (
    delivery_method_id          INT PRIMARY KEY,
    delivery_method_name        VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS application.payment_methods (
    payment_method_id           INT PRIMARY KEY,
    payment_method_name         VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS application.people (
    person_id                   INT PRIMARY KEY,
    full_name                   VARCHAR(50) NOT NULL,
    preferred_name              VARCHAR(50),
    search_name                 VARCHAR(100),
    is_employee                 BOOLEAN NOT NULL,
    is_salesperson              BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS application.transaction_types (
    transaction_type_id         INT PRIMARY KEY,
    transaction_type_name       VARCHAR(50) NOT NULL
);

-- -----------------------------------------------------------------------------
-- 3. WAREHOUSE SCHEMA
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS warehouse.colors (
    color_id                    INT PRIMARY KEY,
    color_name                  VARCHAR(20) NOT NULL
);

CREATE TABLE IF NOT EXISTS warehouse.package_types (
    package_type_id             INT PRIMARY KEY,
    package_type_name           VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS warehouse.stock_items (
    stock_item_id               INT PRIMARY KEY,
    stock_item_name             VARCHAR(100) NOT NULL,
    supplier_id                 INT,
    color_id                    INT REFERENCES warehouse.colors(color_id),
    unit_package_id             INT REFERENCES warehouse.package_types(package_type_id),
    outer_package_id            INT REFERENCES warehouse.package_types(package_type_id),
    brand                       VARCHAR(50),
    size                        VARCHAR(20),
    lead_time_days              INT,
    quantity_per_outer          INT,
    is_chiller_stock            BOOLEAN,
    barcode                     VARCHAR(50),
    tax_rate                    NUMERIC(18, 3),
    unit_price                  NUMERIC(18, 2),
    recommended_retail_price    NUMERIC(18, 2),
    typical_weight_per_unit     NUMERIC(18, 3)
);

-- -----------------------------------------------------------------------------
-- 4. SALES SCHEMA
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS sales.buying_groups (
    buying_group_id             INT PRIMARY KEY,
    buying_group_name           VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS sales.customer_categories (
    customer_category_id        INT PRIMARY KEY,
    customer_category_name      VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS sales.customers (
    customer_id                 INT PRIMARY KEY,
    customer_name               VARCHAR(100) NOT NULL,
    bill_to_customer_id         INT,
    customer_category_id        INT NOT NULL REFERENCES sales.customer_categories(customer_category_id),
    buying_group_id             INT REFERENCES sales.buying_groups(buying_group_id),
    primary_contact_person_id   INT REFERENCES application.people(person_id),
    alternate_contact_person_id INT REFERENCES application.people(person_id),
    delivery_method_id          INT REFERENCES application.delivery_methods(delivery_method_id),
    delivery_city_id            INT NOT NULL REFERENCES application.cities(city_id),
    credit_limit                NUMERIC(18, 2),
    account_opened_date         DATE NOT NULL,
    standard_discount_percentage NUMERIC(18, 3),
    is_statement_sent           BOOLEAN,
    is_on_credit_hold           BOOLEAN,
    payment_days                INT,
    phone_number                VARCHAR(20),
    website_url                 VARCHAR(256),
    delivery_address_line       VARCHAR(100),
    delivery_location_lat       VARCHAR(50),
    delivery_location_long      VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS sales.orders (
    order_id                    INT PRIMARY KEY,
    customer_id                 INT NOT NULL REFERENCES sales.customers(customer_id),
    salesperson_person_id       INT NOT NULL REFERENCES application.people(person_id),
    picked_by_person_id         INT REFERENCES application.people(person_id),
    contact_person_id           INT NOT NULL REFERENCES application.people(person_id),
    backorder_order_id          INT,
    order_date                  DATE NOT NULL,
    expected_delivery_date      DATE NOT NULL,
    customer_purchase_order_number VARCHAR(20),
    is_undersupply_backordered  BOOLEAN,
    picking_completed_when      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sales.order_lines (
    order_line_id               INT PRIMARY KEY,
    order_id                    INT NOT NULL REFERENCES sales.orders(order_id),
    stock_item_id               INT NOT NULL REFERENCES warehouse.stock_items(stock_item_id),
    description                 VARCHAR(100) NOT NULL,
    package_type_id             INT NOT NULL REFERENCES warehouse.package_types(package_type_id),
    quantity                    INT NOT NULL,
    unit_price                  NUMERIC(18, 2) NOT NULL,
    tax_rate                    NUMERIC(18, 3) NOT NULL,
    picked_quantity             INT,
    picking_completed_when      TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sales.invoices (
    invoice_id                  INT PRIMARY KEY,
    customer_id                 INT NOT NULL REFERENCES sales.customers(customer_id),
    bill_to_customer_id         INT NOT NULL REFERENCES sales.customers(customer_id),
    order_id                    INT REFERENCES sales.orders(order_id),
    delivery_method_id          INT NOT NULL REFERENCES application.delivery_methods(delivery_method_id),
    contact_person_id           INT NOT NULL REFERENCES application.people(person_id),
    accounts_person_id          INT NOT NULL REFERENCES application.people(person_id),
    salesperson_person_id       INT NOT NULL REFERENCES application.people(person_id),
    packed_by_person_id         INT REFERENCES application.people(person_id),
    invoice_date                DATE NOT NULL,
    customer_purchase_order_number VARCHAR(20),
    delivery_instructions       TEXT,
    total_dry_items             INT,
    total_chiller_items         INT,
    confirmed_delivery_time     TIMESTAMP,
    confirmed_received_by       VARCHAR(4000)
);

CREATE TABLE IF NOT EXISTS sales.invoice_lines (
    invoice_line_id             INT PRIMARY KEY,
    invoice_id                  INT NOT NULL REFERENCES sales.invoices(invoice_id),
    stock_item_id               INT NOT NULL REFERENCES warehouse.stock_items(stock_item_id),
    description                 VARCHAR(100) NOT NULL,
    package_type_id             INT NOT NULL REFERENCES warehouse.package_types(package_type_id),
    quantity                    INT NOT NULL,
    unit_price                  NUMERIC(18, 2) NOT NULL,
    tax_rate                    NUMERIC(18, 3) NOT NULL,
    tax_amount                  NUMERIC(18, 2) NOT NULL,
    line_profit                 NUMERIC(18, 2) NOT NULL,
    extended_price              NUMERIC(18, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS sales.customer_transactions (
    customer_transaction_id     INT PRIMARY KEY,
    customer_id                 INT NOT NULL REFERENCES sales.customers(customer_id),
    transaction_type_id         INT NOT NULL REFERENCES application.transaction_types(transaction_type_id),
    invoice_id                  INT REFERENCES sales.invoices(invoice_id),
    payment_method_id           INT REFERENCES application.payment_methods(payment_method_id),
    transaction_date            DATE NOT NULL,
    amount_excluding_tax        NUMERIC(18, 2) NOT NULL,
    tax_amount                  NUMERIC(18, 2) NOT NULL,
    transaction_amount          NUMERIC(18, 2) NOT NULL,
    outstanding_balance         NUMERIC(18, 2) NOT NULL,
    finalization_date           DATE,
    is_finalized                BOOLEAN
);

-- -----------------------------------------------------------------------------
-- 5. AUDIT / INGESTION METADATA LOG
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS application.ingestion_log (
    log_id                      SERIAL PRIMARY KEY,
    pipeline_run_id             VARCHAR(100) NOT NULL,
    source_filename             VARCHAR(255) NOT NULL,
    target_table                VARCHAR(100) NOT NULL,
    records_loaded              INT NOT NULL,
    status                      VARCHAR(20) NOT NULL,
    ingested_at                 TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
