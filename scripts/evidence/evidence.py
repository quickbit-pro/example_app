#!/usr/bin/env python3
"""Local evidence catalogue, browser captures and hash-verified handoff. No approval claims."""
import argparse
import datetime as dt
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess

HERE = Path(__file__).resolve().parent

def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def save(run, data):
    temp = run / 'manifest.tmp'
    temp.write_text(json.dumps(data, indent=2) + '\n')
    temp.replace(run / 'manifest.json')

def label(value):
    if not re.fullmatch(r'[a-zA-Z0-9_.-]+', value):
        raise ValueError('Use letters, digits, dot, underscore or hyphen in capture names.')
    return value

def register(run, data, requirement, case, kind, source, note, url):
    row = next(r for r in data['requirements'] if r['id'] == requirement)
    if row['scope'] == 'out_of_scope':
        raise ValueError('This requirement is out of scope in this run.')
    if case not in row['cases']:
        raise ValueError('Choose a case from requirements.json; do not silently omit a path.')
    source = Path(source).resolve()
    if not source.is_file() or source.stat().st_size == 0:
        raise ValueError('Capture file is missing or empty.')
    suffixes = {'video': {'.mp4', '.webm', '.mov'}, 'screenshot': {'.png', '.jpg', '.jpeg', '.webp'},
                'document': {'.pdf', '.json', '.txt', '.md', '.csv'}}
    if source.suffix.lower() not in suffixes[kind]:
        raise ValueError('File extension does not match the evidence type.')
    filename = f'{label(requirement)}-{label(case)}-{len(data["artifacts"])+1}{source.suffix.lower()}'
    destination = run / 'artifacts' / filename
    shutil.copyfile(source, destination)
    data['artifacts'].append({'requirement': requirement, 'case': case, 'kind': kind,
        'file': 'artifacts/' + filename, 'sha256': digest(destination), 'recordedAt': now(),
        'sourceUrl': url, 'note': note, 'review': 'pending'})
    save(run, data)
    return destination

def report(run, data):
    lines = [f'# {data["profile"]["app"]} evidence index', '',
        'Internal capture inventory only. Recorded media is not a compliance approval.', '',
        f'Build: `{data["build"]}`; platform: {data["profile"]["platform"]}; environment: {data["profile"]["environment"]}.', '',
        '| Evidence | Scope | Captured cases | Pending cases |', '| --- | --- | --- | --- |']
    for row in data['requirements']:
        captured = {a['case'] for a in data['artifacts'] if a['requirement'] == row['id']}
        pending = [c for c in row['cases'] if c not in captured]
        lines.append(f'| {row["id"]} {row["title"]} | {row["scope"]} | {len(captured)}/{len(row["cases"])} | {", ".join(pending)} |')
    lines += ['', '## Files', '']
    for a in data['artifacts']:
        path = run / a['file']
        integrity = 'verified' if path.is_file() and digest(path) == a['sha256'] else 'CHANGED OR MISSING'
        lines.append(f'- [{a["requirement"]} / {a["case"]} / {a["kind"]}]({a["file"]}) — hash {integrity}; review {a["review"]}. URL: {a["sourceUrl"] or "not recorded"}')
    (run / 'INDEX.md').write_text('\n'.join(lines) + '\n')
    body = html.escape('\n'.join(lines))
    (run / 'INDEX.html').write_text('<!doctype html><meta charset="utf-8"><title>Evidence inventory</title><style>body{font:15px system-ui;margin:32px;max-width:1200px}pre{white-space:pre-wrap;line-height:1.6}</style><h1>Evidence inventory</h1><pre>' + body + '</pre>')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['init', 'add', 'screenshot', 'video-start', 'video-stop', 'report'])
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--profile', type=Path, default=HERE / 'example.json')
    parser.add_argument('--guidance', type=Path)
    parser.add_argument('--build')
    parser.add_argument('--requirement')
    parser.add_argument('--case')
    parser.add_argument('--kind', choices=['video', 'screenshot', 'document'])
    parser.add_argument('--file', type=Path)
    parser.add_argument('--note', default='')
    parser.add_argument('--url')
    args = parser.parse_args()
    run = args.run.resolve()
    if args.action == 'init':
        if not args.build or not args.guidance or not args.guidance.is_file():
            parser.error('init requires --build and an existing --guidance PDF')
        profile = json.loads(args.profile.read_text())
        if profile['environment'] not in ['staging', 'local']:
            raise ValueError('Only staging or local captures are supported.')
        catalog = json.loads((HERE / 'requirements.json').read_text())
        run.mkdir(parents=True, exist_ok=False)
        (run / 'artifacts').mkdir()
        (run / '.gitignore').write_text('*\n')
        data = {'createdAt': now(), 'build': args.build, 'profile': profile,
            'source': dict(catalog['source'], sha256=digest(args.guidance)),
            'session': label('evidence-' + run.name), 'artifacts': [], 'requirements': catalog['requirements']}
        for row in data['requirements']:
            scope = True if row['appliesWhen'] == 'all' else profile['scope'].get(row['appliesWhen'])
            row['scope'] = 'required' if scope is True else 'out_of_scope' if scope is False else 'scope_unconfirmed'
            if row['id'] in ['4.2', '4.3'] and scope is True:
                row['scope'] = 'deferred_in_supplied_v12_guidance_confirm_with_Equals'
        save(run, data)
    else:
        data = json.loads((run / 'manifest.json').read_text())
        if args.action in ['add', 'screenshot', 'video-start']:
            if not args.requirement or not args.case:
                parser.error('Specify --requirement and --case')
            row = next(r for r in data['requirements'] if r['id'] == args.requirement)
            if args.case not in row['cases'] or row['scope'] == 'out_of_scope':
                raise ValueError('Case is unknown or out of scope.')
        if args.action == 'add':
            if not args.file or not args.kind:
                parser.error('add requires --file and --kind')
            register(run, data, args.requirement, args.case, args.kind, args.file, args.note, args.url)
        elif args.action in ['screenshot', 'video-start', 'video-stop']:
            cli = shlex.split(os.environ.get('EVIDENCE_PLAYWRIGHT_CLI', 'playwright-cli'))
            command = cli + ['-s=' + data['session']]
            if args.action == 'video-stop':
                active = data.get('activeVideo')
                if not active:
                    raise ValueError('No recording was started for this run.')
                subprocess.run(command + ['video-stop'], check=True)
                register(run, data, active['requirement'], active['case'], 'video', run / active['file'], active['note'], active['url'])
                del data['activeVideo']
            else:
                if args.action == 'video-start' and data.get('activeVideo'):
                    raise ValueError('Stop the existing recording before starting another.')
                filename = label(args.requirement + '-' + args.case) + ('-' + dt.datetime.now().strftime('%H%M%S%f')) + ('.webm' if args.action == 'video-start' else '.png')
                capture = run / filename
                if args.action == 'video-start':
                    subprocess.run(command + ['video-start', str(capture), '--size=1280x900'], check=True)
                    data['activeVideo'] = {'file': filename, 'requirement': args.requirement, 'case': args.case, 'note': args.note, 'url': args.url}
                else:
                    subprocess.run(command + ['screenshot', '--filename=' + str(capture)], check=True)
                    register(run, data, args.requirement, args.case, 'screenshot', capture, args.note, args.url)
            save(run, data)
    report(run, data)
    print(run / 'INDEX.md')

if __name__ == '__main__':
    main()
