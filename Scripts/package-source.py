#!/usr/bin/env python3
"""Package the complete source tree, without generated build caches or signing material."""
from pathlib import Path
import hashlib,json,re,zipfile
from urllib.parse import unquote
ROOT=Path(__file__).resolve().parent.parent
excluded={'.git','.build','.swiftpm','DerivedData','build','xcuserdata','__pycache__','node_modules'}
def include(p):
 rel=p.relative_to(ROOT)
 if not p.is_file() or any(part in excluded for part in rel.parts):return False
 if p.name=='SOURCE-MANIFEST.json':return False
 if p.name.startswith('.env') and p.name!='.env.example':return False
 if rel.parts[:2]==('Server','data'):return False
 if p.suffix.lower() in {'.p12','.pfx','.key','.pem','.mobileprovision'}:return False
 return True
files=[p for p in sorted(ROOT.rglob('*')) if include(p)]
for path in files:
 if path.suffix!='.md':continue
 for raw in re.findall(r'\]\(([^)]+)\)',path.read_text()):
  raw=raw.strip('<>').split('#')[0]
  if not raw or '://' in raw or raw.startswith('mailto:'):continue
  target=(path.parent/unquote(raw)).resolve()
  assert target.exists(),(path,raw)
  target.relative_to(ROOT)
manifest={'scope':'WHOOP with personalized profile, saved-data highlights, Live camera and measurement export in the existing iOS project, with legacy reconstruction source retained. No signed iPhone binary or account credentials.','files':[{'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]}
manifest_path=ROOT/'SOURCE-MANIFEST.json';manifest_path.write_text(json.dumps(manifest,indent=2));files.append(manifest_path)
archive=ROOT.parent/'WHOOP-iOS-source.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as output:
 for path in files:output.write(path,str(Path(ROOT.name)/path.relative_to(ROOT)))
with zipfile.ZipFile(archive) as output:
 assert output.testzip() is None
 for entry in manifest['files']:
  assert hashlib.sha256(output.read(ROOT.name+'/'+entry['path'])).hexdigest()==entry['sha256']
digest=hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.zip.sha256').write_text(digest+'  '+archive.name+'\n')
print(json.dumps({'archive':str(archive),'files':len(files),'bytes':archive.stat().st_size,'sha256':digest},indent=2))
