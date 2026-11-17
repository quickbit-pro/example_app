import importlib.util, json, tempfile, unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('release',Path(__file__).resolve().parents[1]/'legacy_release.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class ReleaseTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
  for name in ['Api','Application','Infrastructure','Domain']:(self.root/('NeoBanking.'+name+'.dll')).write_bytes(b'test artifact')
  m.stamp(self.root,'cardeo-prod','api','a'*40,'quickbit-pro/hoppa_demo_app')
 def mutate(self,key,value):
  p=self.root/'legacy-release.json';d=json.loads(p.read_text());d[key]=value;p.write_text(json.dumps(d))
 def test_valid(self): m.verify(self.root,'cardeo-prod')
 def test_missing_manifest(self):
  (self.root/'legacy-release.json').unlink()
  with self.assertRaises(OSError):m.verify(self.root,'cardeo-prod')
 def test_newplatform(self):
  self.mutate('repository','quickbit-pro/UserApp')
  with self.assertRaises(ValueError):m.verify(self.root,'cardeo-prod')
 def test_wrong_app(self):
  with self.assertRaises(ValueError):m.verify(self.root,'hoppa')
 def test_wrong_family(self):
  self.mutate('platformContract','uuid-v1')
  with self.assertRaises(ValueError):m.verify(self.root,'cardeo-prod')
 def test_tampered_artifact(self):
  (self.root/'NeoBanking.Application.dll').write_bytes(b'UUID build')
  with self.assertRaises(ValueError):m.verify(self.root,'cardeo-prod')
 def test_missing_assembly(self):
  (self.root/'NeoBanking.Application.dll').unlink()
  with self.assertRaises(ValueError):m.verify(self.root,'cardeo-prod')
 def test_invalid_revision(self):
  self.mutate('revision','main')
  with self.assertRaises(ValueError):m.verify(self.root,'cardeo-prod')
if __name__=='__main__':unittest.main()
