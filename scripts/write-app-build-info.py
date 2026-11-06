#!/usr/bin/env python3
"""Embed the version of this exact Flutter build for support screenshots."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess


def build_defines(repository, flutter_args, environment=None, now=None):
    environment = os.environ if environment is None else environment
    repository = Path(repository)
    source = (repository / 'mobile_flutter/pubspec.yaml').read_text()
    match = re.search(r'(?m)^version:\s*[\"\']?([^\s\"\'#]+)', source)
    if not match:
        raise ValueError('The Flutter pubspec must declare an app version')
    version, _, number = match[1].partition('+')
    args = list(flutter_args)
    for index, value in enumerate(args):
        for option in ['--build-name', '--build-number']:
            override = value.split('=', 1)[1] if value.startswith(option + '=') else (
                args[index + 1] if value == option and index + 1 < len(args) else None)
            if override is not None:
                if option == '--build-name':
                    version = override
                else:
                    number = override
    revision = environment.get('APP_BUILD_REVISION', '').strip()
    if not revision and (repository / '.git').exists():
        result = subprocess.run(['git', '-C', str(repository), 'rev-parse', '--short=7', 'HEAD'],
                                capture_output=True, text=True)
        if result.returncode == 0:
            revision = result.stdout.strip()
    if not revision and (repository / '.deploy-commit').is_file():
        revision = (repository / '.deploy-commit').read_text().strip()
    if not revision:
        revision = 'b' + (now or datetime.now(timezone.utc)).strftime('%y%m%d%H%M%S')
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,64}', revision):
        raise ValueError('Invalid APP_BUILD_REVISION')
    if re.fullmatch(r'[0-9a-fA-F]{40}', revision):
        revision = revision[:7]
    return {'APP_VERSION': version, 'APP_BUILD_NUMBER': number, 'APP_BUILD_REVISION': revision}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('flutter_args', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        data = build_defines(args.repository, args.flutter_args)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(data, indent=2) + '\n')
        print(f"App version: v{data['APP_VERSION']}+{data['APP_BUILD_NUMBER']} · {data['APP_BUILD_REVISION']}")
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == '__main__':
    main()
