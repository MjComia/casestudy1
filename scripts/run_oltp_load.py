"""Run OLTP DDL and ingestion scripts inside PostgreSQL container."""

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
    print("Wide World Importers - Phase 2: OLTP Ingestion")
    print("==================================================")

    # 1. Apply Schema
    run_command(
        ["docker", "exec", "-i", "wwi_postgres", "psql", "-U", "admin", "-d", "wwi_db", "-f", "/sql/01_create_oltp_schema.sql"],
        "Step 1: Applying OLTP Schema DDL",
    )

    # 2. Load Data
    run_command(
        ["docker", "exec", "-i", "wwi_postgres", "psql", "-U", "admin", "-d", "wwi_db", "-f", "/sql/02_load_oltp_data.sql"],
        "Step 2: Loading CSV Data into OLTP Tables",
    )

    # 3. Print verification
    run_command(
        [
            "docker", "exec", "-i", "wwi_postgres", "psql", "-U", "admin", "-d", "wwi_db", "-c",
            "SELECT target_table, records_loaded, status, ingested_at FROM application.ingestion_log ORDER BY log_id DESC LIMIT 18;"
        ],
        "Step 3: Verification of Ingestion Log",
    )

    print("\n[SUCCESS] OLTP Layer created and populated successfully!")


if __name__ == "__main__":
    main()
