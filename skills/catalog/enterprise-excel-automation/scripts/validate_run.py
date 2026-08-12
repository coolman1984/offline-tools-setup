from pathlib import Path
import argparse, hashlib, json, sys
from jsonschema import Draft202012Validator


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def validate(instance_path: Path, schema_path: Path) -> list[str]:
    schema = load(schema_path)
    errors = Draft202012Validator(schema).iter_errors(load(instance_path))
    return [f"{'.'.join(map(str, e.absolute_path)) or '$'}: {e.message}" for e in errors]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("run_dir")
    args = p.parse_args()
    run = Path(args.run_dir)
    root = Path(__file__).resolve().parents[1]
    contracts = {
        "source-receipt.json": root / "assets/source-receipt.schema.json",
        "workbook-manifest.json": root / "assets/workbook-manifest.schema.json",
        "analysis-result.json": root / "assets/analysis-result.schema.json",
    }
    problems = []
    for filename, schema in contracts.items():
        target = run / filename
        if not target.exists(): problems.append(f"missing {filename}"); continue
        problems += [f"{filename}: {x}" for x in validate(target, schema)]
    receipt = run / "source-receipt.json"
    if receipt.exists():
        data = load(receipt); source = Path(data.get("source", {}).get("path", ""))
        expected = data.get("source", {}).get("sha256")
        if source.exists() and expected:
            actual = hashlib.sha256(source.read_bytes()).hexdigest()
            if actual.lower() != expected.lower(): problems.append("source hash no longer matches receipt")
    if problems:
        print("\n".join(f"ERROR: {p}" for p in problems)); return 2
    print("Excel automation run contract: VALID")
    return 0


if __name__ == "__main__": sys.exit(main())
