#!/usr/bin/env python3
"""Check the customer export for accidental feature or credential imports."""
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
paths = subprocess.check_output(
    ['git', 'ls-files', '--cached', '--others', '--exclude-standard'],
    cwd=ROOT, text=True,
).splitlines()
issues = []
credential = re.compile(
    r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|'
    r'AIza[0-9A-Za-z_-]{35}|(?:gh[pousr]_|github_pat_)[A-Za-z0-9_]{30,}|'
    r'sk-(?:or-v1-)?[A-Za-z0-9_-]{24,}|AKIA[0-9A-Z]{16}|'
    r'SG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}|'
    r'eyJ[A-Za-z0-9_-]{15,}\.eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}'
)
secret_key = re.compile(r'(api.?key|signing.?key|secret|password|bearer.?token|private.?key)$', re.I)
split_feature = re.compile(r'BillSplits|SplitBill|SharedBill|TotalBill|bill_split|splitBill|total-bill|split-bill')

def check_config(value, filename, prefix=''):
    if isinstance(value, dict):
        for key, item in value.items():
            if secret_key.search(key) and isinstance(item, str) and item:
                issues.append(f'{filename}: nonempty credential field {prefix}{key}')
            check_config(item, filename, f'{prefix}{key}.')
    elif isinstance(value, list):
        for item in value:
            check_config(item, filename, prefix)

for filename in paths:
    path = ROOT / filename
    if not path.is_file():
        continue
    if path.name in {'google-services.json', 'GoogleService-Info.plist'} or path.suffix in {'.p12', '.pfx', '.jks', '.keystore'}:
        issues.append(f'{filename}: customer credential/signing file must not be exported')
    try:
        text = path.read_text(encoding='utf-8')
    except UnicodeError:
        continue
    # Privacy tests deliberately contain synthetic key-shaped strings.
    is_test = filename.startswith(('backend/tests/', 'mobile_flutter/test/', 'scripts/tests/'))
    if not is_test and credential.search(text):
        issues.append(f'{filename}: credential pattern detected (value withheld)')
    if filename.startswith(('backend/src/', 'mobile_flutter/lib/')) and split_feature.search(text):
        issues.append(f'{filename}: excluded bill-splitting functionality detected')
    if path.suffix == '.json' and ('appsettings' in filename or filename.startswith('mobile_flutter/config/')):
        check_config(json.loads(text), filename)

if issues:
    print('\n'.join(issues), file=sys.stderr)
    sys.exit(1)
print(f'Customer export checks passed: {len(paths)} files; no bill-splitting code or credential findings.')
