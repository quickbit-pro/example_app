#!/usr/bin/env python3
"""Package a genuine Flutter web build for the offline, single-file customer guide.

The app is compiled separately from lib/customer_preview_main.dart. This tool
packages its unchanged JavaScript and CanvasKit WASM with Flutter assets. The
embedded font manifest additionally registers the SDK Roboto fallback to avoid
Google Fonts requests. No application UI is rendered or reimplemented here.
"""
import argparse
import base64
import gzip
import hashlib
import json
import mimetypes
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / 'scripts/customer-guide/generated/flutter-preview.json'
BRAND_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.ttf', '.otf', '.txt'}
MIME_TYPES = {
    '.js': 'application/javascript', '.wasm': 'application/wasm',
    '.json': 'application/json', '.bin': 'application/octet-stream',
    '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff': 'font/woff',
    '.woff2': 'font/woff2', '.frag': 'application/octet-stream',
}


def package(build_dir: Path, brand_assets_dir: Path | None = None,
            material_fonts_dir: Path | None = None,
            fallback_fonts_dir: Path | None = None) -> dict:
    """Return a deterministic JSON-compatible bundle of executable build files."""
    build_dir = Path(build_dir).resolve()
    bootstrap = build_dir / 'flutter_bootstrap.js'
    if not bootstrap.is_file():
        raise ValueError('Build directory does not contain flutter_bootstrap.js')
    match = re.search(r'_flutter\.buildConfig\s*=\s*(\{[^\n]+\})\s*;', bootstrap.read_text())
    if not match:
        raise ValueError('Cannot read the Flutter build configuration')
    config = json.loads(match.group(1))
    builds = config.get('builds', [])
    if not any(b.get('compileTarget') == 'dart2js' and b.get('renderer') == 'canvaskit'
               and b.get('mainJsPath', 'main.dart.js') == 'main.dart.js' for b in builds):
        raise ValueError('Preview requires a standard JavaScript / CanvasKit Flutter build')
    main_js = build_dir / 'main.dart.js'
    if not main_js.is_file():
        raise ValueError('Build is missing main.dart.js')
    main_text = main_js.read_text()
    if not all(marker in main_text for marker in ('customer-preview-ready', 'customer-brand-update')):
        raise ValueError('Build is not the customer preview entrypoint; build lib/customer_preview_main.dart')
    engine = config.get('engineRevision', '')
    if not re.fullmatch(r'[0-9a-f]{40}', engine):
        raise ValueError('Invalid Flutter engine revision')
    canvas_candidates = [build_dir / 'canvaskit', build_dir / f'canvaskit-{engine[:12]}']
    canvas = next((p for p in canvas_candidates
                   if (p / 'canvaskit.js').is_file() and (p / 'canvaskit.wasm').is_file()), None)
    if canvas is None:
        raise ValueError('Build must include the full local CanvasKit JS and WASM renderer')
    paths = [build_dir / 'flutter.js', build_dir / 'main.dart.js',
             canvas / 'canvaskit.js', canvas / 'canvaskit.wasm']
    paths.extend(sorted(build_dir.glob('main.dart.js_*.part.js')))
    asset_dir = build_dir / 'assets'
    if not (asset_dir / 'AssetManifest.bin.json').is_file():
        raise ValueError('Build is missing Flutter AssetManifest.bin.json')
    paths.extend(sorted(p for p in asset_dir.rglob('*')
                        if p.is_file() and p.suffix not in {'.gz', '.br'}))
    entries = [(path, path.relative_to(build_dir).as_posix(), build_dir) for path in paths]
    if brand_assets_dir is not None:
        brand_dir = Path(brand_assets_dir).resolve()
        if not brand_dir.is_dir():
            raise ValueError('Brand asset directory does not exist')
        entries.extend((path, 'assets/config/assets/' + path.relative_to(brand_dir).as_posix(), brand_dir)
                       for path in sorted(brand_dir.rglob('*'))
                       if path.is_file() and path.suffix.lower() in BRAND_EXTENSIONS)
    replacement_bytes = {}
    aliases = {}
    if material_fonts_dir is not None or fallback_fonts_dir is not None:
        manifest_path = build_dir / 'assets/FontManifest.json'
        if not manifest_path.is_file():
            raise ValueError('Build is missing FontManifest.json')
        font_manifest = json.loads(manifest_path.read_text())
        if not isinstance(font_manifest, list):
            raise ValueError('Invalid Flutter FontManifest.json')
        # Flutter's CanvasKit engine downloads Roboto from Google when no
        # Roboto family is present. Include the actual SDK font and its license
        # in the embedded manifest before the engine initializes.
        if material_fonts_dir is not None and not any(family.get('family') == 'Roboto' for family in font_manifest):
            material_dir = Path(material_fonts_dir).resolve()
            font_manifest.append({'family': 'Roboto', 'fonts': [
                {'asset': 'customer-preview/fonts/Roboto-Regular.ttf', 'weight': 400},
            ]})
            entries.extend((material_dir / name, 'assets/customer-preview/fonts/' + name, material_dir)
                           for name in ('Roboto-Regular.ttf', 'Roboto_LICENSE.txt'))
        if fallback_fonts_dir is not None:
            fallback_dir = Path(fallback_fonts_dir).resolve()
            font_path = 'assets/customer-preview/fonts/NotoSansSymbols.woff2'
            if not any(family.get('family') == 'Noto Sans Symbols' for family in font_manifest):
                font_manifest.append({'family': 'Noto Sans Symbols', 'fonts': [
                    {'asset': 'customer-preview/fonts/NotoSansSymbols.woff2'},
                ]})
            entries.extend((fallback_dir / name, 'assets/customer-preview/fonts/' + name, fallback_dir)
                           for name in ('NotoSansSymbols.woff2', 'NotoSansSymbols-OFL.txt'))
            fallback_paths = set(re.findall(r'notosanssymbols/v[0-9]+/[A-Za-z0-9_-]+\.woff2', main_text))
            if not fallback_paths:
                raise ValueError('Cannot locate the Noto Sans Symbols fallback URL in compiled Flutter')
            for fallback_path in fallback_paths:
                aliases['font-fallback/' + fallback_path] = font_path
        replacement_bytes['assets/FontManifest.json'] = json.dumps(
            font_manifest, separators=(',', ':')).encode()
    assets = []
    seen = {}
    for path, relative, permitted_root in entries:
        if not path.is_file() or path.is_symlink():
            raise ValueError(f'Missing or symlinked build file: {path.name}')
        # Reject parent-directory symlinks as well as direct symlinked files.
        try:
            path.resolve().relative_to(permitted_root)
        except ValueError as error:
            raise ValueError(f'Build asset escapes build directory: {path.name}') from error
        raw = replacement_bytes.get(relative, path.read_bytes())
        digest = hashlib.sha256(raw).hexdigest()
        if relative in seen:
            if seen[relative] == digest:
                continue  # A bundled font license can also appear in source brand assets.
            raise ValueError(f'Conflicting duplicate packaged asset path: {relative}')
        seen[relative] = digest
        mime = MIME_TYPES.get(path.suffix, mimetypes.guess_type(path.name)[0] or 'application/octet-stream')
        assets.append({'path': relative, 'mime': mime, 'size': len(raw),
                       'sha256': digest,
                       'data': base64.b64encode(gzip.compress(raw, compresslevel=9, mtime=0)).decode('ascii')})
    return {'schemaVersion': 1, 'compression': 'gzip', 'engineRevision': engine,
            'entrypoint': 'main.dart.js', 'loader': 'flutter.js',
            'canvasKitJs': (canvas / 'canvaskit.js').relative_to(build_dir).as_posix(),
            'canvasKitWasm': (canvas / 'canvaskit.wasm').relative_to(build_dir).as_posix(),
            'aliases': aliases, 'assets': assets}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('build_dir', type=Path)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--brand-assets-dir', type=Path, default=ROOT / 'mobile_flutter/config/assets',
                        help='Public image, font and license sources for bundled brand presets')
    flutter_executable = shutil.which('flutter')
    material_fonts_dir = (Path(flutter_executable).resolve().parents[1] / 'bin/cache/artifacts/material_fonts'
                          if flutter_executable else None)
    parser.add_argument('--material-fonts-dir', type=Path, default=material_fonts_dir,
                        help='Flutter SDK material_fonts cache containing authentic Roboto and its license')
    parser.add_argument('--fallback-fonts-dir', type=Path, default=ROOT / 'scripts/customer-guide/assets',
                        help='Vendored Noto Sans Symbols font and license for offline glyph fallback')
    args = parser.parse_args()
    try:
        if args.material_fonts_dir is None:
            raise ValueError('Flutter is not on PATH; pass --material-fonts-dir for its material_fonts cache')
        payload = package(args.build_dir, args.brand_assets_dir, args.material_fonts_dir, args.fallback_fonts_dir)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, separators=(',', ':')))
    print(f'Packaged {len(payload["assets"])} Flutter files into {args.output} '
          f'({args.output.stat().st_size:,} bytes)')


if __name__ == '__main__':
    main()
