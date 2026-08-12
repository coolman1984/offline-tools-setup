from pathlib import Path
import argparse, json, sys
from jsonschema import Draft202012Validator

def load(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
 p=argparse.ArgumentParser();p.add_argument('brain_root');a=p.parse_args();root=Path(a.brain_root);skill=Path(__file__).resolve().parents[1];errors=[]
 for d in ['facts','entities','decisions','sources','timeline','reports','skills']:
  if not (root/d).is_dir(): errors.append(f'missing directory: {d}')
 specs=[('facts',skill/'assets/fact.schema.json'),('decisions',skill/'assets/decision.schema.json')]
 ids=set()
 for folder,schema_path in specs:
  schema=load(schema_path)
  for f in (root/folder).glob('*.json') if (root/folder).exists() else []:
   try:data=load(f)
   except Exception as e: errors.append(f'{f}: invalid JSON: {e}');continue
   for e in Draft202012Validator(schema).iter_errors(data): errors.append(f'{f}: {e.message}')
   i=data.get('id')
   if i in ids: errors.append(f'duplicate record id: {i}')
   if i: ids.add(i)
 if errors:
  print('\n'.join('ERROR: '+e for e in errors));return 2
 print('Project Brain: VALID');return 0
if __name__=='__main__':sys.exit(main())
