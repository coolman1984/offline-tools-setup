from pathlib import Path
import argparse, hashlib, json, sys
from pypdf import PdfReader
import fitz

def main():
 p=argparse.ArgumentParser();p.add_argument('pdf');p.add_argument('--expected-pages',type=int);p.add_argument('--render-sample',action='store_true');a=p.parse_args();f=Path(a.pdf);errors=[];info={}
 if not f.exists() or f.stat().st_size==0: errors.append('missing/empty PDF')
 if not errors:
  try:
   r=PdfReader(str(f));info['pages']=len(r.pages);info['encrypted']=bool(r.is_encrypted)
   if a.expected_pages is not None and len(r.pages)!=a.expected_pages: errors.append(f'expected {a.expected_pages} pages, got {len(r.pages)}')
   if a.render_sample and not r.is_encrypted and r.pages:
    doc=fitz.open(str(f)); page=doc.load_page(0); pix=page.get_pixmap(matrix=fitz.Matrix(1,1));info['sample_render']=[pix.width,pix.height];doc.close()
  except Exception as e: errors.append(f'PDF reopen/render failed: {e}')
 info.update(path=str(f.resolve()),sha256=hashlib.sha256(f.read_bytes()).hexdigest() if f.exists() else None,status='failed' if errors else 'passed',errors=errors);print(json.dumps(info,indent=2));return 2 if errors else 0
if __name__=='__main__':sys.exit(main())
