import importlib.util
from pathlib import Path
import tempfile
import unittest
from datetime import datetime, timezone

script = Path(__file__).resolve().parents[1] / 'write-app-build-info.py'
spec = importlib.util.spec_from_file_location('app_build_info', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class AppBuildInfoTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'mobile_flutter').mkdir()
        (self.root / 'mobile_flutter/pubspec.yaml').write_text('name: test_app\nversion: 0.1.7+11\n')

    def test_package_version_and_exact_source_revision(self):
        info = module.build_defines(self.root, [], {'APP_BUILD_REVISION': 'a' * 40})
        self.assertEqual(info, {'APP_VERSION': '0.1.7', 'APP_BUILD_NUMBER': '11', 'APP_BUILD_REVISION': 'a' * 7})

    def test_flutter_package_overrides_match_the_header(self):
        for args in [['--build-name=2.3.4', '--build-number=99'],
                     ['--build-name', '2.3.4', '--build-number', '99']]:
            info = module.build_defines(self.root, args, {'APP_BUILD_REVISION': 'abc1234'})
            self.assertEqual(info['APP_VERSION'], '2.3.4')
            self.assertEqual(info['APP_BUILD_NUMBER'], '99')

    def test_archived_source_uses_its_commit_manifest(self):
        (self.root / '.deploy-commit').write_text('b' * 40 + '\n')
        self.assertEqual(module.build_defines(self.root, [], {})['APP_BUILD_REVISION'], 'b' * 7)

    def test_source_without_git_still_gets_a_unique_build_identifier(self):
        info = module.build_defines(self.root, [], {}, datetime(2026, 11, 6, 14, 0, tzinfo=timezone.utc))
        self.assertEqual(info['APP_BUILD_REVISION'], 'b261106140000')

    def test_invalid_identifier_is_rejected(self):
        with self.assertRaises(ValueError):
            module.build_defines(self.root, [], {'APP_BUILD_REVISION': 'not a valid label'})

if __name__ == '__main__':
    unittest.main()
