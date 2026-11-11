#!/usr/bin/env python3
"""Fail a native build if its offline nutrition bundle no longer matches calc.ts."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parent.parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
metadata=json.loads((root/'App/Resources/nutrition-calc-provenance.json').read_text())
assert metadata['source']=='lib/nutrition/calc.ts'
assert sha(root/metadata['source'])==metadata['source_sha256'], 'Run npm ci && npm run build to regenerate the nutrition resource.'
assert sha(root/'App/Resources/nutrition-calc.js')==metadata['bundle_sha256'], 'The generated nutrition bundle was changed.'
print('Offline native nutrition bundle matches the canonical TypeScript calculator.')
