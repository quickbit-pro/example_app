#!/usr/bin/env python3
"""Root-side transactional activation. Stage and verify before touching current."""
import argparse, fcntl, json, os, shutil, subprocess, time, urllib.request
from pathlib import Path
from legacy_release import TARGETS, verify

def run(*args): subprocess.run(args,check=True)
def link(target,path):
 temporary=path.with_name(path.name+'.legacy-next')
 temporary.unlink(missing_ok=True);temporary.symlink_to(target);temporary.replace(path)
def main():
 p=argparse.ArgumentParser();p.add_argument('target',choices=TARGETS);p.add_argument('bundle',type=Path);a=p.parse_args()
 if os.geteuid()!=0: raise SystemExit('Run activation with sudo')
 cfg=TARGETS[a.target];bundle=a.bundle.resolve()
 lock=open('/run/lock/legacy-'+a.target+'.lock','w');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 components=[c for c in ('api','web','admin') if c in cfg]
 manifests={c:verify(bundle/c,a.target,c) for c in components}
 revisions={m['revision'] for m in manifests.values()}
 if len(revisions)!=1: raise ValueError('Mixed source revisions')
 revision=revisions.pop();release='legacy-'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())+'-'+revision[:12]
 destinations={};previous={}
 for c in components:
  root=Path(cfg[c]);previous[c]=(root/'current').resolve(strict=True);dest=root/'releases'/release
  if dest.exists(): raise ValueError('Release already exists')
  shutil.copytree(bundle/c,dest)
  if c=='api':
   # Retain the exact active environment overlays without printing their contents.
   for old in previous[c].glob('appsettings.*.json'):
    new=dest/old.name;new.unlink(missing_ok=True)
    if old.is_symlink(): new.symlink_to(old.resolve(strict=True))
    else: shutil.copy2(old,new)
   run('chown','-R',cfg['user']+':'+cfg['user'],str(dest))
  else: run('chown','-R','www-data:www-data',str(dest))
  verify(dest,a.target,c);destinations[c]=dest
 gate=Path('/usr/local/libexec/verify-legacy-app-release.py');gate.parent.mkdir(parents=True,exist_ok=True)
 shutil.copy2(Path(__file__).with_name('legacy_release.py'),gate);gate.chmod(0o755)
 dropdir=Path('/etc/systemd/system')/(cfg['service']+'.service.d');dropdir.mkdir(exist_ok=True)
 drop=dropdir/'90-legacy-contract.conf';old_drop=drop.read_bytes() if drop.exists() else None
 activated=False
 try:
  drop.write_text('[Service]\nExecStartPre=/usr/bin/python3 '+str(gate)+' '+a.target+' '+cfg['api']+'/current\n')
  run('systemctl','daemon-reload')
  for c in components: link(destinations[c],Path(cfg[c])/'current')
  activated=True;run('systemctl','restart',cfg['service'])
  for attempt in range(45):
   try:
    with urllib.request.urlopen('http://127.0.0.1:'+str(cfg['port'])+'/health/contract',timeout=3) as response: health=json.load(response)
    if health.get('platformContract')=='legacy-int-v1' and revision in health.get('revision',''): break
   except Exception: pass
   time.sleep(1)
  else: raise RuntimeError('New release contract health check failed')
  run('systemctl','is-active','--quiet',cfg['service'])
  with urllib.request.urlopen('http://127.0.0.1:'+str(cfg['port'])+'/health',timeout=10) as response:
   if response.status!=200: raise RuntimeError('Health check failed')
 except BaseException:
  if activated:
   for c in components: link(previous[c],Path(cfg[c])/'current')
  if old_drop is None: drop.unlink(missing_ok=True)
  else: drop.write_bytes(old_drop)
  run('systemctl','daemon-reload');run('systemctl','restart',cfg['service']);raise
 receipt=dict(target=a.target,revision=revision,release=release,previous={k:str(v) for k,v in previous.items()},current={k:str(v) for k,v in destinations.items()},contract=health)
 (destinations['api']/'activation.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print(json.dumps(receipt,indent=2))
if __name__=='__main__': main()
