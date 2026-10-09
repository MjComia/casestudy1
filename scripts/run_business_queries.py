"""Execute all 10 Business Analytical Queries and export formatted output results."""

from pathlib import Path
import subprocess
import sys


def main() -> None:
    output_dir = Path("output")
    output_dir.mkdir(exist_ok=True)
    output_file = output_dir / "business_query_results.txt"

    print("==================================================================")
    print("Wide World Importers - Phase 6: Analytical Business Queries")
    print("==================================================================")

    cmd = ["docker", "exec", "-i", "wwi_postgres", "psql", "-U", "admin", "-d", "wwi_db", "-f", "/sql/07_business_queries.sql"]
    res = subprocess.run(cmd, capture_output=True, text=True)

    if res.returncode != 0:
        print("ERROR running business queries:")
        print(res.stderr)
        sys.exit(1)

    # Save to output file
    output_file.write_text(res.stdout, encoding="utf-8")
    print(res.stdout)
    print(f"\n[SUCCESS] All 10 queries executed! Full output saved to: {output_file}")


if __name__ == "__main__":
    main()
