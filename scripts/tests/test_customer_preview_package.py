"""The offline package must contain genuine, unchanged Flutter build resources."""
import base64
import gzip
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'package-customer-preview.py'
SPEC = importlib.util.spec_from_file_location('package_preview', SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
ENGINE = '1' * 40


class PackagePreviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.build = Path(self.temp.name)
        self.write('flutter_bootstrap.js', '_flutter.buildConfig = ' + json.dumps({
            'engineRevision': ENGINE,
            'builds': [{'compileTarget': 'dart2js', 'renderer': 'canvaskit', 'mainJsPath': 'main.dart.js'}],
        }) + ';\n')
        self.write('flutter.js', '/* real Flutter loader fixture */')
        self.write('main.dart.js', '/* compiled preview fixture: customer-preview-ready customer-brand-update */')
        self.write('main.dart.js_1.part.js', '/* compiled deferred fixture */')
        self.write('canvaskit/canvaskit.js', 'export default function(){}')
        self.write('canvaskit/canvaskit.wasm', b'\0asm\x01\0\0\0')
        self.write('assets/AssetManifest.bin.json', '{}')
        self.write('assets/FontManifest.json', '[{"family":"Example","fonts":[]}]')
        self.write('assets/fonts/example.ttf', bytes(range(256)))
        self.write('assets/NOTICES', 'Flutter and font license notices')

    def write(self, path, data):
        target = self.build / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data.encode() if isinstance(data, str) else data)

    def test_round_trip_preserves_executable_assets_and_licenses(self):
        result = MODULE.package(self.build)
        self.assertEqual(result['engineRevision'], ENGINE)
        assets = {asset['path']: asset for asset in result['assets']}
        self.assertIn('main.dart.js_1.part.js', assets)
        self.assertIn('assets/NOTICES', assets)
        for path, asset in assets.items():
            raw = gzip.decompress(base64.b64decode(asset['data']))
            self.assertEqual(raw, (self.build / path).read_bytes())
            self.assertEqual(len(raw), asset['size'])
        self.assertEqual(assets['canvaskit/canvaskit.wasm']['mime'], 'application/wasm')
        self.assertEqual(assets['assets/fonts/example.ttf']['mime'], 'font/ttf')

    def test_package_is_deterministic_and_excludes_network_bootstrap_and_duplicates(self):
        self.write('assets/NOTICES.gz', b'not-a-useful-asset')
        self.write('assets/NOTICES.br', b'not-a-useful-asset')
        self.write('index.html', '<script src="https://external.example"></script>')
        self.write('flutter_service_worker.js', '// network worker')
        first = MODULE.package(self.build)
        self.assertEqual(first, MODULE.package(self.build))
        paths = [asset['path'] for asset in first['assets']]
        self.assertFalse(any(p.endswith(('.gz', '.br')) for p in paths))
        self.assertNotIn('index.html', paths)
        self.assertNotIn('flutter_bootstrap.js', paths)
        self.assertNotIn('flutter_service_worker.js', paths)

    def test_existing_versioned_canvaskit_build_is_supported(self):
        (self.build / 'canvaskit').rename(self.build / f'canvaskit-{ENGINE[:12]}')
        self.assertEqual(MODULE.package(self.build)['canvasKitJs'], f'canvaskit-{ENGINE[:12]}/canvaskit.js')

    def test_missing_full_renderer_fails(self):
        (self.build / 'canvaskit/canvaskit.wasm').unlink()
        with self.assertRaisesRegex(ValueError, 'full local CanvasKit'):
            MODULE.package(self.build)

    def test_wasm_only_build_is_rejected(self):
        self.write('flutter_bootstrap.js', '_flutter.buildConfig = ' + json.dumps({
            'engineRevision': ENGINE, 'builds': [{'compileTarget': 'dart2wasm', 'renderer': 'skwasm'}],
        }) + ';')
        with self.assertRaisesRegex(ValueError, 'JavaScript / CanvasKit'):
            MODULE.package(self.build)

    def test_brand_assets_include_images_fonts_and_licenses_but_no_config_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            brands = Path(directory)
            for name in ('logo.png', 'font.ttf', 'OFL.txt', 'firebase.json', 'config.plist', 'secret.env'):
                (brands / name).write_text(name)
            result = MODULE.package(self.build, brands)
            paths = [a['path'] for a in result['assets']]
            self.assertIn('assets/config/assets/logo.png', paths)
            self.assertIn('assets/config/assets/font.ttf', paths)
            self.assertIn('assets/config/assets/OFL.txt', paths)
            self.assertNotIn('assets/config/assets/firebase.json', paths)
            self.assertNotIn('assets/config/assets/config.plist', paths)
            self.assertNotIn('assets/config/assets/secret.env', paths)
            self.assertEqual(result, MODULE.package(self.build, brands))

    def test_identical_asset_deduplicates_but_conflicting_bytes_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            brands = Path(directory)
            (brands / 'license.txt').write_text('same')
            self.write('assets/config/assets/license.txt', 'same')
            assets = MODULE.package(self.build, brands)['assets']
            self.assertEqual(sum(a['path'] == 'assets/config/assets/license.txt' for a in assets), 1)
            (brands / 'license.txt').write_text('different')
            with self.assertRaisesRegex(ValueError, 'Conflicting duplicate'):
                MODULE.package(self.build, brands)

    def test_sdk_roboto_and_license_are_loaded_through_font_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            material = Path(directory)
            (material / 'Roboto-Regular.ttf').write_bytes(b'actual SDK font fixture')
            (material / 'Roboto_LICENSE.txt').write_text('Roboto license fixture')
            assets = {asset['path']: gzip.decompress(base64.b64decode(asset['data']))
                      for asset in MODULE.package(self.build, material_fonts_dir=material)['assets']}
            manifest = json.loads(assets['assets/FontManifest.json'])
            self.assertEqual(manifest[0]['family'], 'Example')
            roboto = next(family for family in manifest if family['family'] == 'Roboto')
            self.assertEqual(roboto['fonts'][0]['asset'], 'customer-preview/fonts/Roboto-Regular.ttf')
            self.assertEqual(assets['assets/customer-preview/fonts/Roboto-Regular.ttf'], b'actual SDK font fixture')
            self.assertIn('assets/customer-preview/fonts/Roboto_LICENSE.txt', assets)
            # Packaging changes only the embedded manifest; build files are untouched.
            self.assertNotIn('Roboto', (self.build / 'assets/FontManifest.json').read_text())

    def test_missing_sdk_roboto_fails_instead_of_using_network(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'Roboto-Regular.ttf'):
                MODULE.package(self.build, material_fonts_dir=Path(directory))

    def test_existing_roboto_family_is_preserved_without_substitution(self):
        manifest = '[{"family":"Roboto","fonts":[{"asset":"custom/roboto.ttf"}]}]'
        self.write('assets/FontManifest.json', manifest)
        with tempfile.TemporaryDirectory() as directory:
            assets = {asset['path']: gzip.decompress(base64.b64decode(asset['data']))
                      for asset in MODULE.package(self.build, material_fonts_dir=Path(directory))['assets']}
            self.assertEqual(assets['assets/FontManifest.json'].decode(), manifest)
            self.assertNotIn('assets/customer-preview/fonts/Roboto-Regular.ttf', assets)

    def test_symbols_fallback_registers_actual_font_and_aliases_compiled_engine_path(self):
        self.write('main.dart.js', (self.build / 'main.dart.js').read_text() +
                   '/* notosanssymbols/v43/actual-engine-font.woff2 */')
        with tempfile.TemporaryDirectory() as directory:
            fonts = Path(directory)
            (fonts / 'NotoSansSymbols.woff2').write_bytes(b'wOF2-font-fixture')
            (fonts / 'NotoSansSymbols-OFL.txt').write_text('SIL OFL fixture')
            payload = MODULE.package(self.build, fallback_fonts_dir=fonts)
            self.assertEqual(payload['aliases'], {
                'font-fallback/notosanssymbols/v43/actual-engine-font.woff2':
                    'assets/customer-preview/fonts/NotoSansSymbols.woff2',
            })
            assets = {asset['path']: gzip.decompress(base64.b64decode(asset['data']))
                      for asset in payload['assets']}
            manifest = json.loads(assets['assets/FontManifest.json'])
            self.assertIn('Noto Sans Symbols', [family['family'] for family in manifest])
            self.assertEqual(assets['assets/customer-preview/fonts/NotoSansSymbols.woff2'], b'wOF2-font-fixture')
            self.assertIn('assets/customer-preview/fonts/NotoSansSymbols-OFL.txt', assets)

    def test_missing_symbols_engine_path_fails_explicitly(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'Noto Sans Symbols fallback URL'):
                MODULE.package(self.build, fallback_fonts_dir=Path(directory))

    def test_production_entrypoint_is_rejected(self):
        self.write('main.dart.js', '/* normal application entrypoint */')
        with self.assertRaisesRegex(ValueError, 'customer preview entrypoint'):
            MODULE.package(self.build)

    def test_missing_manifest_fails(self):
        (self.build / 'assets/AssetManifest.bin.json').unlink()
        with self.assertRaisesRegex(ValueError, 'AssetManifest'):
            MODULE.package(self.build)

    def test_symlinked_asset_is_rejected(self):
        (self.build / 'assets/link.txt').symlink_to(self.build / 'assets/NOTICES')
        with self.assertRaisesRegex(ValueError, 'symlinked'):
            MODULE.package(self.build)

    def test_parent_symlink_outside_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / 'private.txt').write_text('private')
            (self.build / 'assets/outside').symlink_to(directory, target_is_directory=True)
            # pathlib intentionally does not recurse directory symlinks; no data is exposed.
            paths = [asset['path'] for asset in MODULE.package(self.build)['assets']]
            self.assertNotIn('assets/outside/private.txt', paths)


if __name__ == '__main__':
    unittest.main()
