"""Run OLAP Dimensional Model DDL and transformation scripts inside PostgreSQL container."""

import subprocess
import sys


def run_command(cmd: list[str], description: str) -> None:
    print(f"\n>>> {description}...")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR: {description} failed!")
        print(result.stderr)
        sys.exit(1)
    if result.stdout.strip():
        print(result.stdout.strip())


def main() -> None:
    print("==================================================")
    print("Wide World Importers - Phase 3: OLAP Transformation")
    print("==================================================")

    # 1. Apply OLAP Schema DDL
    run_command(
        ["docker", "exec", "-i", "wwi_postgres", "psql", "-U", "admin", "-d", "wwi_db", "-f", "/sql/03_create_olap_schema.sql"],
        "Step 1: Applying OLAP Schema DDL (olap schema)",
    )

    # 2. Transform & Load OLAP Data
    run_command(
        ["docker", "exec", "-i", "wwi_postgres", "psql", "-U", "admin", "-d", "wwi_db", "-f", "/sql/04_load_olap_data.sql"],
        "Step 2: Transforming OLTP into OLAP Dimensions and Facts",
    )

    # 3. Print verification
    run_command(
        [
            "docker", "exec", "-i", "wwi_postgres", "psql", "-U", "admin", "-d", "wwi_db", "-c",
            """
            SELECT 'dim_date' AS table_name, count(*) AS total_rows FROM olap.dim_date UNION ALL
            SELECT 'dim_employee', count(*) FROM olap.dim_employee UNION ALL
            SELECT 'dim_city', count(*) FROM olap.dim_city UNION ALL
            SELECT 'dim_stock_item', count(*) FROM olap.dim_stock_item UNION ALL
            SELECT 'dim_customer', count(*) FROM olap.dim_customer UNION ALL
            SELECT 'fact_order', count(*) FROM olap.fact_order UNION ALL
            SELECT 'fact_sale', count(*) FROM olap.fact_sale;
            """
        ],
        "Step 3: Verification of OLAP Table Row Counts",
    )

    print("\n[SUCCESS] OLAP Dimensional Model created and populated successfully!")


if __name__ == "__main__":
    main()
