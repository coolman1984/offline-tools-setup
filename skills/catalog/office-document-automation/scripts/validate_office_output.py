from pathlib import Path
import argparse, hashlib, json, zipfile, sys

EXPECTED={'xlsx':['[Content_Types].xml','xl/workbook.xml'],'docx':['[Content_Types].xml','word/document.xml'],'pptx':['[Content_Types].xml','ppt/presentation.xml']}

def main():
 p=argparse.ArgumentParser();p.add_argument('path');p.add_argument('--kind',choices=list(EXPECTED));p.add_argument('--receipt');a=p.parse_args();f=Path(a.path)
 problems=[]
 if not f.exists() or f.stat().st_size==0: problems.append('output is missing or empty')
 kind=a.kind or f.suffix.lower().lstrip('.')
 if not problems and kind in EXPECTED:
  try:
   with zipfile.ZipFile(f) as z:
    names=set(z.namelist())
    for req in EXPECTED[kind]:
     if req not in names: problems.append(f'missing package part: {req}')
    bad=z.testzip()
    if bad: problems.append(f'corrupt package member: {bad}')
  except zipfile.BadZipFile: problems.append('invalid Office Open XML package')
 digest=hashlib.sha256(f.read_bytes()).hexdigest() if f.exists() else None
 result={'path':str(f.resolve()),'kind':kind,'sha256':digest,'status':'failed' if problems else 'passed','problems':problems}
 print(json.dumps(result,indent=2))
 if a.receipt: Path(a.receipt).write_text(json.dumps(result,indent=2),encoding='utf-8')
 return 2 if problems else 0
if __name__=='__main__':sys.exit(main())
