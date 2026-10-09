"""Master End-to-End Data Pipeline Entry Point for Wide World Importers.

Executes all 9 stages in dependency order:
1. Validate source CSV files
2. Create/prepare OLTP database schema
3. Ingest CSV files into OLTP tables
4. Validate OLTP load
5. Create/prepare OLAP schema
6. Load dimensions & execute SCD2 processing
7. Load fact tables
8. Run final data quality checks
9. Record pipeline execution result
"""

from __future__ import annotations

import datetime
from pathlib import Path
import subprocess
import sys
import time

REQUIRED_FILES = [
    Path("data/Application/Application.Countries.csv"),
    Path("data/Application/Application.StateProvinces.csv"),
    Path("data/Application/Application.Cities.csv"),
    Path("data/Application/Application.DeliveryMethods.csv"),
    Path("data/Application/Application.PaymentMethods.csv"),
    Path("data/Application/Application.People.csv"),
    Path("data/Application/Application.TransactionTypes.csv"),
    Path("data/Warehouse/Warehouse.Colors.csv"),
    Path("data/Warehouse/Warehouse.PackageTypes.csv"),
    Path("data/Warehouse/Warehouse.StockItems.csv"),
    Path("data/Sales/Sales.BuyingGroups.csv"),
    Path("data/Sales/Sales.CustomerCategories.csv"),
    Path("data/Sales/Sales.Customers.csv"),
    Path("data/Sales/Sales.Orders.csv"),
    Path("data/Sales/Sales.OrderLines.csv"),
    Path("data/Sales/Sales.Invoices.csv"),
    Path("data/Sales/Sales.InvoiceLines.csv"),
    Path("data/Sales/Sales.CustomerTransactions.csv"),
]


def execute_sql(command_type: str, target: str, description: str) -> str:
    """Run SQL query or file inside the PostgreSQL container."""
    flag = "-f" if command_type == "file" else "-c"
    cmd = ["docker", "exec", "-i", "wwi_postgres", "psql", "-U", "admin", "-d", "wwi_db", flag, target]
    print(f"\n[{datetime.datetime.now().strftime('%H:%M:%S')}] >>> {description}...")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"FAILED: {description}")
        print(res.stderr)
        raise RuntimeError(f"Step failed: {description}\n{res.stderr}")
    return res.stdout.strip()


def stage_1_validate_source_files() -> None:
    print("\n-------------------------------------------------------------")
    print("Stage 1: Validating Source CSV Files Availability")
    print("-------------------------------------------------------------")
    missing = []
    for file_path in REQUIRED_FILES:
        if not file_path.exists() or file_path.stat().st_size == 0:
            missing.append(str(file_path))
        else:
            print(f"  [OK] Found: {file_path} ({file_path.stat().st_size:,} bytes)")
    if missing:
        raise FileNotFoundError(f"Missing or empty source files: {missing}")
    print("[SUCCESS] All 18 required source files are verified!")


def stage_2_prepare_oltp() -> None:
    print("\n-------------------------------------------------------------")
    print("Stage 2: Preparing OLTP Database Schemas & Tables")
    print("-------------------------------------------------------------")
    execute_sql("file", "/sql/01_create_oltp_schema.sql", "Applying OLTP DDL")


def stage_3_ingest_oltp() -> None:
    print("\n-------------------------------------------------------------")
    print("Stage 3: Ingesting Raw CSVs into OLTP Tables")
    print("-------------------------------------------------------------")
    execute_sql("file", "/sql/02_load_oltp_data.sql", "Executing OLTP COPY Ingestion")


def stage_4_validate_oltp() -> None:
    print("\n-------------------------------------------------------------")
    print("Stage 4: Validating OLTP Ingestion Row Counts")
    print("-------------------------------------------------------------")
    output = execute_sql(
        "query",
        "SELECT target_table, records_loaded, status FROM application.ingestion_log ORDER BY log_id DESC LIMIT 18;",
        "Checking OLTP Ingestion Log",
    )
    print(output)


def stage_5_prepare_olap() -> None:
    print("\n-------------------------------------------------------------")
    print("Stage 5: Preparing OLAP Schemas & Staging Tables")
    print("-------------------------------------------------------------")
    execute_sql("file", "/sql/03_create_olap_schema.sql", "Applying OLAP Schema DDL")


def stage_6_and_7_load_dimensions_and_facts() -> None:
    print("\n-------------------------------------------------------------")
    print("Stage 6 & 7: Loading Dimensions, SCD2 Processing & Facts")
    print("-------------------------------------------------------------")
    execute_sql("file", "/sql/04_load_olap_data.sql", "Loading Dimensions and Fact Tables")
    execute_sql("file", "/sql/05_scd2_customer_update.sql", "Processing SCD Type 2 & Point-in-Time Fact Alignment")


def stage_8_data_quality_checks() -> None:
    print("\n-------------------------------------------------------------")
    print("Stage 8: Running Data-Quality & Integrity Checks")
    print("-------------------------------------------------------------")
    output = execute_sql("file", "/sql/06_data_quality_checks.sql", "Executing Automated Data Quality Suite")
    print(output)


def stage_9_record_pipeline_result(start_time: float, run_id: str) -> None:
    print("\n-------------------------------------------------------------")
    print("Stage 9: Recording Pipeline Execution Result")
    print("-------------------------------------------------------------")
    duration_sec = round(time.time() - start_time, 2)
    record_sql = f"""
    CREATE TABLE IF NOT EXISTS olap.pipeline_runs (
        run_id          VARCHAR(100) PRIMARY KEY,
        status          VARCHAR(20) NOT NULL,
        duration_sec    NUMERIC(10, 2) NOT NULL,
        completed_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    INSERT INTO olap.pipeline_runs (run_id, status, duration_sec)
    VALUES ('{run_id}', 'SUCCESS', {duration_sec});
    SELECT * FROM olap.pipeline_runs WHERE run_id = '{run_id}';
    """
    output = execute_sql("query", record_sql, "Logging Pipeline Run Summary")
    print(output)
    print(f"\n=============================================================")
    print(f"[PIPELINE COMPLETED SUCCESSFULLY in {duration_sec}s]")
    print(f"=============================================================")


def main() -> None:
    start_time = time.time()
    run_id = f"RUN-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}"

    print("=============================================================")
    print(f"  Wide World Importers: Automated Master Data Pipeline")
    print(f"  Run Identifier: {run_id}")
    print("=============================================================")

    try:
        stage_1_validate_source_files()
        stage_2_prepare_oltp()
        stage_3_ingest_oltp()
        stage_4_validate_oltp()
        stage_5_prepare_olap()
        stage_6_and_7_load_dimensions_and_facts()
        stage_8_data_quality_checks()
        stage_9_record_pipeline_result(start_time, run_id)
    except Exception as exc:
        print(f"\n[PIPELINE ABORTED] Critical Error encountered: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
