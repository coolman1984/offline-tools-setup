from pathlib import Path
import json, py_compile, sys
ROOT=Path(__file__).resolve().parents[1]
REQUIRED={
'enterprise-excel-automation':['assets/source-receipt.schema.json','assets/workbook-manifest.schema.json','assets/analysis-result.schema.json','assets/sample-analytics.sql','scripts/create_sample_duckdb.py','scripts/validate_run.py','scenarios/README.md'],
'enterprise-dashboard-automation':['assets/dashboard-spec.schema.json','templates/dashboard-shell.html','scripts/validate_dashboard.py','scenarios/README.md'],
'internal-server-reporting':['assets/job-status.schema.json','templates/server-pipeline.py','scenarios/README.md'],
'office-document-automation':['assets/document-job.schema.json','scripts/validate_office_output.py','scenarios/README.md'],
'pdf-document-automation':['assets/pdf-job.schema.json','scripts/validate_pdf_output.py','scenarios/README.md'],
'fullstack-internal-webapp':['assets/internal-app-contract.schema.json','templates/project-layout.md','scenarios/README.md'],
'second-brain-project-memory':['assets/fact.schema.json','assets/decision.schema.json','scripts/validate_brain.py','scenarios/README.md'],
'automation-governance':['assets/run-receipt.schema.json','scenarios/README.md'],
'skill-authoring-governance':['assets/skill-package.schema.json','scripts/validate_skill_package.py','scenarios/README.md']}
errors=[]
for skill,items in REQUIRED.items():
 base=ROOT/'skills/catalog'/skill
 for rel in items:
  p=base/rel
  if not p.exists(): errors.append(f'{skill}: missing {rel}');continue
  if p.suffix=='.json':
   try:
    d=json.loads(p.read_text(encoding='utf-8-sig'))
    if '$schema' in d and 'json-schema.org' not in d['$schema']: errors.append(f'{p}: unexpected schema dialect')
   except Exception as e:errors.append(f'{p}: invalid JSON: {e}')
  if p.suffix=='.py':
   try:py_compile.compile(str(p),doraise=True)
   except Exception as e:errors.append(f'{p}: Python syntax: {e}')
if errors:
 print('\n'.join('ERROR: '+x for x in errors));sys.exit(2)
print(f'Skill execution packs: VALID ({len(REQUIRED)} skills)')
