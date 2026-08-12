from pathlib import Path
import argparse
import duckdb


def main() -> int:
    parser = argparse.ArgumentParser(description="Create the deterministic sample analytics DuckDB used by the Excel automation skill.")
    parser.add_argument("output", nargs="?", default="sample-analytics.duckdb")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sql = (root / "assets" / "sample-analytics.sql").read_text(encoding="utf-8")
    out = Path(args.output).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(out))
    try:
        con.execute(sql)
        rows = con.execute("select * from v_period_summary").fetchall()
        if len(rows) != 2:
            raise RuntimeError(f"unexpected sample summary row count: {len(rows)}")
    finally:
        con.close()
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
