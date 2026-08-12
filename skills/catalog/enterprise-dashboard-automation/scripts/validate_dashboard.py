from pathlib import Path
import argparse, json, sys
from jsonschema import Draft202012Validator


def main() -> int:
    p=argparse.ArgumentParser(); p.add_argument("spec"); p.add_argument("--data")
    a=p.parse_args(); root=Path(__file__).resolve().parents[1]
    schema=json.loads((root/'assets/dashboard-spec.schema.json').read_text(encoding='utf-8'))
    spec=json.loads(Path(a.spec).read_text(encoding='utf-8-sig'))
    errors=list(Draft202012Validator(schema).iter_errors(spec))
    if a.data:
        d=json.loads(Path(a.data).read_text(encoding='utf-8-sig'))
        periods=d.get('periods',[])
        if len(periods)!=len(set(periods)): errors.append(Exception('duplicate periods in analysis result'))
        active=d.get('active_period')
        if active is not None and active not in periods: errors.append(Exception('active period is not present in periods'))
    if errors:
        for e in errors: print('ERROR:', getattr(e,'message',str(e)))
        return 2
    print('Dashboard contracts: VALID'); return 0
if __name__=='__main__': sys.exit(main())
