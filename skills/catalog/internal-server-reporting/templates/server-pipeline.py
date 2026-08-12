from __future__ import annotations
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, os, tempfile, uuid
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse

ROOT=Path(os.environ.get('REPORT_SERVER_ROOT', r'C:\ReportServer')).resolve(); STAGING=ROOT/'staging'; STATE=ROOT/'state'; PUBLISH=ROOT/'publish'
for d in (STAGING,STATE,PUBLISH): d.mkdir(parents=True,exist_ok=True)
app=FastAPI(title='Internal Reporting Pipeline',version='1.0')

def now(): return datetime.now(timezone.utc).isoformat()
def state_path(job): return STATE/f'{job}.json'
def write_state(job, **patch):
    p=state_path(job); current=json.loads(p.read_text()) if p.exists() else {'schema_version':'1.0','job_id':job,'created_at_utc':now(),'warnings':[],'result':None,'error':None}
    current.update(patch); current['updated_at_utc']=now(); tmp=p.with_suffix('.tmp'); tmp.write_text(json.dumps(current,indent=2),encoding='utf-8'); tmp.replace(p); return current

@app.post('/api/v1/uploads')
async def upload(file: UploadFile=File(...)):
    job=str(uuid.uuid4()); target=STAGING/f'{job}.upload'; h=hashlib.sha256(); size=0
    with target.open('wb') as out:
        while chunk:=await file.read(1024*1024):
            size+=len(chunk)
            if size>750*1024*1024: target.unlink(missing_ok=True); raise HTTPException(413,'file too large')
            h.update(chunk); out.write(chunk)
    status=write_state(job,state='received',stage='upload-received',progress=100,upload={'original_name':Path(file.filename or 'upload').name,'sha256':h.hexdigest(),'size_bytes':size})
    return JSONResponse(status,status_code=202)

@app.get('/api/v1/jobs/{job_id}')
def job(job_id:str):
    p=state_path(job_id)
    if not p.exists(): raise HTTPException(404,'unknown job')
    return json.loads(p.read_text(encoding='utf-8'))

# Production worker rule: claim jobs outside the request process, validate the report family,
# invoke the document-specific automation skill, write staging data, calculate deterministically,
# then atomically replace versioned presentation JSON only after validation passes.
