import importlib.util,json,subprocess,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('legacy_guard',ROOT/'scripts/verify-legacy-contract.py');guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
class BoundaryTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
  for f in ['platform-contract.json',*guard.CHECKS]:
   p=self.root/f;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((ROOT/f).read_bytes())
 def tearDown(self): self.temp.cleanup()
 def test_legacy_source_passes(self): guard.validate(self.root,check_origin=False)
 def test_uuid_conversion_is_rejected(self):
  p=self.root/'backend/src/NeoBanking.Application/DTOs/Cards/CardDtos.cs';p.write_text(p.read_text().replace('public int? CardId','public Guid? CardId'))
  with self.assertRaises(ValueError): guard.validate(self.root,check_origin=False)
 def test_newplatform_origin_is_rejected(self):
  with patch.object(subprocess,'check_output',return_value='https://github.com/quickbit-pro/UserApp.git\n'):
   with self.assertRaises(ValueError): guard.validate(self.root)
 def test_wrong_target_is_rejected(self):
  with self.assertRaises(ValueError): guard.validate(self.root,'newplatform',False)
 def test_missing_manifest_is_rejected(self):
  (self.root/'platform-contract.json').unlink()
  with self.assertRaises(OSError): guard.validate(self.root,check_origin=False)
 def test_forged_family_is_rejected(self):
  p=self.root/'platform-contract.json';m=json.loads(p.read_text());m['family']='newplatform-uuid-v1';p.write_text(json.dumps(m))
  with self.assertRaises(ValueError): guard.validate(self.root,check_origin=False)
if __name__=='__main__': unittest.main()
