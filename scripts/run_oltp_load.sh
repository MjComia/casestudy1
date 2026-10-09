#!/usr/bin/env bash
# ==============================================================================
# Pipeline Step: Ingest Raw CSV files into PostgreSQL OLTP Layer
# ==============================================================================
set -euo pipefail

echo "=================================================="
echo "Step 1: Applying OLTP Schema DDL..."
echo "=================================================="
docker exec -i wwi_postgres psql -U admin -d wwi_db -f /sql/01_create_oltp_schema.sql

echo "=================================================="
echo "Step 2: Loading CSV Data into OLTP Tables..."
echo "=================================================="
docker exec -i wwi_postgres psql -U admin -d wwi_db -f /sql/02_load_oltp_data.sql

echo "=================================================="
echo "OLTP Load Completed Successfully! Ingestion Log:"
echo "=================================================="
docker exec -i wwi_postgres psql -U admin -d wwi_db -c "
SELECT target_table, records_loaded, status, ingested_at 
FROM application.ingestion_log 
ORDER BY log_id DESC 
LIMIT 18;
"
