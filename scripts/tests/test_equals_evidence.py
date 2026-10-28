import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'evidence' / 'evidence.py'
spec = importlib.util.spec_from_file_location('evidence', SCRIPT)
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class EvidenceTests(unittest.TestCase):
    def test_catalogue_covers_fifteen_boxes_and_hoppa_excludes_equals_cards(self):
        catalog = json.loads((SCRIPT.parent / 'requirements.json').read_text())
        self.assertEqual(len(catalog['requirements']), 15)
        self.assertEqual(len({row['id'] for row in catalog['requirements']}), 15)
        profile = json.loads((SCRIPT.parent / 'hoppa.json').read_text())
        self.assertFalse(profile['scope']['equals_cards'])
        self.assertFalse(profile['scope']['equals_online_cards'])

    def test_capture_stays_pending_and_hash_detects_modified_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'artifacts').mkdir()
            source = root / 'consent.json'
            source.write_text('{"synthetic_test":true}')
            data = {'profile': {'app': 'test', 'platform': 'test', 'environment': 'local'}, 'build': 'test',
                    'requirements': [{'id': '1.1', 'title': 'Test', 'scope': 'required', 'cases': ['happy', 'blocked']}], 'artifacts': []}
            artifact = evidence.register(root, data, '1.1', 'happy', 'document', source, 'unit test only', None)
            self.assertEqual(data['artifacts'][0]['review'], 'pending')
            evidence.report(root, data)
            self.assertIn('1/2', (root / 'INDEX.md').read_text())
            artifact.write_text('changed')
            evidence.report(root, data)
            self.assertIn('CHANGED OR MISSING', (root / 'INDEX.md').read_text())
            with self.assertRaises(ValueError):
                evidence.register(root, data, '1.1', 'invented-case', 'document', source, '', None)
            with self.assertRaises(ValueError):
                evidence.register(root, data, '1.1', 'happy', 'video', source, '', None)

    def test_out_of_scope_cannot_be_registered_as_evidence(self):
        data = {'requirements': [{'id': '3.4', 'scope': 'out_of_scope'}]}
        with self.assertRaises(ValueError):
            evidence.register(Path('/unused'), data, '3.4', 'happy', 'video', Path('/unused'), '', None)


if __name__ == '__main__':
    unittest.main()
