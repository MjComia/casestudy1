"""Demonstrate SCD Type 2 pipeline processing across two loads with point-in-time fact resolution."""

import subprocess
import sys


def run_sql(query: str, description: str) -> None:
    print(f"\n>>> {description}...")
    cmd = ["docker", "exec", "-i", "wwi_postgres", "psql", "-U", "admin", "-d", "wwi_db", "-c", query]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"ERROR: {description} failed!")
        print(res.stderr)
        sys.exit(1)
    print(res.stdout.strip())


def run_file(filepath: str, description: str) -> None:
    print(f"\n>>> {description}...")
    cmd = ["docker", "exec", "-i", "wwi_postgres", "psql", "-U", "admin", "-d", "wwi_db", "-f", filepath]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"ERROR: {description} failed!")
        print(res.stderr)
        sys.exit(1)
    print(res.stdout.strip())


def main() -> None:
    print("==================================================================")
    print("Wide World Importers - Phase 4: SCD Type 2 Demonstration")
    print("==================================================================")

    # 1. Inspect initial state (Load 1)
    run_sql(
        """
        SELECT customer_key, customer_id, customer_name, customer_category_name, credit_limit, valid_from, valid_to, is_current
        FROM olap.dim_customer
        WHERE customer_id = 832;
        """,
        "State 1: Initial Customer Record (Before Change)",
    )

    # 2. Simulate source operational change in OLTP (Batch 2)
    # Customer 832 category changed to Wholesaler (category_id = 2), credit limit increased
    run_sql(
        """
        UPDATE sales.customers
        SET customer_category_id = 2,
            credit_limit = 5000.00,
            delivery_address_line = 'Suite 100, 1345 Jun Avenue'
        WHERE customer_id = 832;
        """,
        "State 2: Operational Event in OLTP (Customer 832 upgraded to Wholesaler on 2015-01-01)",
    )

    # 3. Execute SCD2 ETL Pipeline
    run_file(
        "/sql/05_scd2_customer_update.sql",
        "State 3: Executing Automated SCD2 Pipeline (sql/05_scd2_customer_update.sql)",
    )

    # 4. Verify Dimension History (Both versions exist)
    run_sql(
        """
        SELECT 
            customer_key, 
            customer_id, 
            customer_name, 
            customer_category_name, 
            credit_limit, 
            valid_from, 
            valid_to, 
            is_current
        FROM olap.dim_customer
        WHERE customer_id = 832
        ORDER BY customer_key;
        """,
        "Verification 1: Customer Dimension History (Version 1 Closed, Version 2 Active)",
    )

    # 5. Verify Point-in-Time Fact Resolution
    run_sql(
        """
        SELECT 
            dc.customer_key,
            dc.customer_category_name,
            dc.valid_from,
            dc.valid_to,
            COUNT(fs.sale_key) AS total_invoices,
            MIN(d.calendar_date) AS earliest_sale,
            MAX(d.calendar_date) AS latest_sale,
            ROUND(SUM(fs.extended_price), 2) AS total_revenue
        FROM olap.fact_sale fs
        JOIN olap.dim_customer dc ON fs.customer_key = dc.customer_key
        JOIN olap.dim_date d ON fs.invoice_date_key = d.date_key
        WHERE dc.customer_id = 832
        GROUP BY dc.customer_key, dc.customer_category_name, dc.valid_from, dc.valid_to
        ORDER BY dc.customer_key;
        """,
        "Verification 2: Point-in-Time Fact Resolution (Sales mapped to historical version active at transaction date)",
    )

    print("\n[SUCCESS] SCD Type 2 processing across two loads demonstrated successfully!")


if __name__ == "__main__":
    main()
