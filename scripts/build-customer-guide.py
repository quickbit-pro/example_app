#!/usr/bin/env python3
"""Build the single-file, offline customer setup guide from repository sources."""
import base64
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'scripts/customer-guide'
OUTPUT = ROOT / 'docs/customer-onboarding.html'


def build():
    configs = {name: json.loads((ROOT / f'mobile_flutter/config/{name}.json').read_text())
               for name in ('sample', 'hoppa', 'sunrise')}
    paths = set(configs['sample']['design']['assets'].values()) | {configs['sample']['native']['icon']}
    assets = [{'path': path, 'data': base64.b64encode((ROOT / 'mobile_flutter/config' / path).read_bytes()).decode(),
               'mime': 'image/png', 'example': True} for path in sorted(paths)]
    data = {'configs': configs, 'assets': assets, 'schemaVersion': 1}
    replacements = {'__GUIDE_DATA__': json.dumps(data, separators=(',', ':')).replace('<', '\\u003c')}
    preview = json.loads((SOURCE / 'generated/flutter-preview.json').read_text())
    replacements['__FLUTTER_PREVIEW_DATA__'] = json.dumps(preview, separators=(',', ':')).replace('<', '\\u003c')
    for key, name in [('__CONFIG_ENGINE__', 'config-engine.js'), ('__FILE_TOOLS__', 'file-tools.js'),
                      ('__SERVER_GUIDE__', 'server-guide.js'), ('__FLUTTER_EMBED__', 'flutter-embed.js'), ('__APP_JS__', 'app.js')]:
        replacements[key] = (SOURCE / name).read_text().replace('</script', '<\\/script')
    html = (SOURCE / 'template.html').read_text()
    for key, value in replacements.items():
        assert html.count(key) == 1, f'Expected exactly one {key}'
        html = html.replace(key, value)
    OUTPUT.write_text(html)
    print(f'Built {OUTPUT} ({OUTPUT.stat().st_size:,} bytes)')


if __name__ == '__main__':
    build()
