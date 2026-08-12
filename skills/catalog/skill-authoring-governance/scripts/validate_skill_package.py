from pathlib import Path
import argparse,re,sys
NAME=re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*$'); BAD=['pip install','npm install','winget install','choco install','scoop install','invoke-webrequest','curl ','wget ','git clone']
def main():
 p=argparse.ArgumentParser();p.add_argument('skill_dir');a=p.parse_args();root=Path(a.skill_dir);errors=[];warnings=[];md=root/'SKILL.md'
 if not md.exists():errors.append('missing SKILL.md')
 else:
  text=md.read_text(encoding='utf-8-sig');m=re.search(r'^name:\s*([^\r\n]+)',text,re.M);d=re.search(r'^description:\s*([^\r\n]+)',text,re.M)
  name=m.group(1).strip(' "\'') if m else ''
  if not NAME.fullmatch(name):errors.append('invalid/missing name')
  if name and name!=root.name:errors.append('name must match directory')
  if not d or len(d.group(1).strip())<20:errors.append('description is missing/too short')
 for f in root.rglob('*'):
  if f.is_file() and f.suffix.lower() in {'.ps1','.cmd','.bat','.sh','.py','.js','.ts','.mjs','.cjs'}:
   txt=f.read_text(encoding='utf-8',errors='ignore').lower()
   for marker in BAD:
    if marker in txt:warnings.append(f'{f.relative_to(root)} contains {marker!r}')
 print('\n'.join('ERROR: '+x for x in errors));print('\n'.join('WARN: '+x for x in warnings));return 2 if errors else 0
if __name__=='__main__':sys.exit(main())
