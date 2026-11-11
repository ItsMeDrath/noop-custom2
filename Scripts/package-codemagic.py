#!/usr/bin/env python3
"""Create a flat, complete iOS build upload with fewer than 100 browser-upload files."""
from pathlib import Path
import hashlib,json,zipfile

ROOT=Path(__file__).resolve().parent.parent
files=[]
for folder in ['App','Core','Tests','Configuration','WHOOP.xcodeproj','LiveActivityWidget']:
    files.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and
                 not any(part in {'xcuserdata','__pycache__'} for part in p.relative_to(ROOT).parts))
files.extend(ROOT/p for p in ['Package.swift','codemagic.yaml','.gitattributes','.gitignore',
    'README-CODEMAGIC.md','Scripts/package-ipa-on-mac.sh','Scripts/validate-ipa.py',
    'Scripts/tests/test_validate_ipa.py','Scripts/validate-nutrition-resource.py','lib/nutrition/calc.ts'])
files=sorted(set(files))
assert all(p.is_file() for p in files)
assert len(files)+1<100, 'Keep this package under the GitHub browser upload batch limit.'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest={'scope':'Complete iOS unsigned cloud-build inputs, not a compiled IPA. No credentials or backend deployment.',
          'files':[{'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in files]}
archive=ROOT.parent/'WHOOP-Codemagic.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as output:
    for p in files:output.write(p,str(p.relative_to(ROOT)))
    output.writestr('CLOUD-BUILD-MANIFEST.json',json.dumps(manifest,indent=2)+'\n')
with zipfile.ZipFile(archive) as output:
    assert output.testzip() is None
    for entry in manifest['files']:
        assert hashlib.sha256(output.read(entry['path'])).hexdigest()==entry['sha256']
archive.with_suffix('.zip.sha256').write_text(sha(archive)+'  '+archive.name+'\n')
print(json.dumps({'archive':str(archive),'files':len(files)+1,'bytes':archive.stat().st_size,'sha256':sha(archive)},indent=2))
