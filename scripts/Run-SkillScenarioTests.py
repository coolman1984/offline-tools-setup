from pathlib import Path
import json, os, subprocess, sys, tempfile, zipfile
ROOT=Path(__file__).resolve().parents[1]
PY=sys.executable

def run(*args):
    print('>', ' '.join(map(str,args)))
    subprocess.run([str(x) for x in args],check=True,cwd=ROOT)

def make_office_fixture(path:Path):
    with zipfile.ZipFile(path,'w') as z:
        z.writestr('[Content_Types].xml','<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
        z.writestr('xl/workbook.xml','<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"/>')

def make_pdf(path:Path):
    from pypdf import PdfWriter
    w=PdfWriter();w.add_blank_page(width=595,height=842)
    with path.open('wb') as f:w.write(f)

def main():
    run(PY,ROOT/'scripts/Test-SkillExecutionPacks.py')
    with tempfile.TemporaryDirectory() as td:
        t=Path(td)
        db=t/'sample.duckdb'
        run(PY,ROOT/'skills/catalog/enterprise-excel-automation/scripts/create_sample_duckdb.py',db)
        if not db.exists() or db.stat().st_size==0: raise RuntimeError('sample DuckDB was not created')
        run(PY,ROOT/'skills/catalog/enterprise-dashboard-automation/scripts/validate_dashboard.py',ROOT/'skills/fixtures/dashboard-spec.example.json','--data',ROOT/'skills/fixtures/analysis-result.example.json')
        x=t/'sample.xlsx';make_office_fixture(x)
        run(PY,ROOT/'skills/catalog/office-document-automation/scripts/validate_office_output.py',x,'--kind','xlsx')
        pdf=t/'sample.pdf';make_pdf(pdf)
        run(PY,ROOT/'skills/catalog/pdf-document-automation/scripts/validate_pdf_output.py',pdf,'--expected-pages','1','--render-sample')
        run(PY,ROOT/'skills/catalog/second-brain-project-memory/scripts/validate_brain.py',ROOT/'skills/fixtures/project-brain')
        run(PY,ROOT/'skills/catalog/skill-authoring-governance/scripts/validate_skill_package.py',ROOT/'skills/catalog/enterprise-excel-automation')
    print('Skill scenario tests: PASS')
    return 0
if __name__=='__main__':sys.exit(main())
