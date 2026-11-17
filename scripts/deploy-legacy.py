#!/usr/bin/env python3
"""Build an immutable legacy release and optionally activate it on its fixed host."""
import argparse, importlib.util, json, os, re, shutil, subprocess, sys, tarfile, tempfile
from pathlib import Path
from legacy_release import TARGETS, stamp, digest

def run(args,cwd=None,env=None): subprocess.run([str(x) for x in args],cwd=cwd,env=env,check=True)
def output(args,cwd): return subprocess.check_output(args,cwd=cwd,text=True).strip()
def main():
 p=argparse.ArgumentParser();p.add_argument('target',choices=TARGETS);p.add_argument('--deploy',action='store_true');p.add_argument('--output',type=Path);a=p.parse_args()
 root=Path(__file__).resolve().parents[1];cfg=TARGETS[a.target]
 run([sys.executable,root/'scripts/verify-legacy-contract.py','--target',a.target])
 if output(['git','status','--porcelain','--untracked-files=no'],root): raise SystemExit('Commit tracked changes before deployment')
 revision=output(['git','rev-parse','HEAD'],root)
 run(['dotnet','test',root/'backend/tests/NeoBanking.Api.Tests/NeoBanking.Api.Tests.csproj','-m:1','-p:UseSharedCompilation=false','--filter','FullyQualifiedName~LegacyPlatformContractTests|FullyQualifiedName~MobileCardsControllerTests|FullyQualifiedName~MobileTiersControllerTests|FullyQualifiedName~PaymentConfirmationTests','--verbosity','quiet'])
 work=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='legacy-'+a.target+'-'))
 work.mkdir(parents=True,exist_ok=True);source=work/'source';source.mkdir();bundle=work/'bundle';bundle.mkdir()
 archive=work/'source.tar';run(['git','archive','--format=tar','-o',archive,revision],root)
 with tarfile.open(archive) as tar: tar.extractall(source,filter='data')
 (source/'.deploy-commit').write_text(revision+'\n')
 run([sys.executable,source/'scripts/verify-legacy-contract.py','--archive','--target',a.target])
 run(['dotnet','publish',source/'backend/src/NeoBanking.Api/NeoBanking.Api.csproj','-c','Release','-r','linux-x64','--self-contained','false','-m:1','-p:UseSharedCompilation=false','-p:InformationalVersion=1.0.0+'+revision,'-o',bundle/'api'])
 if 'web' in cfg:
  mobile=source/'mobile_flutter'
  flags=['--release','--no-wasm-dry-run','--dart-define=API_BASE_URL='+cfg['url'],'--dart-define=APP_BUILD_REVISION='+revision[:7]]
  if a.target.startswith('cardeo-'):
   flags+=['--dart-define=APP_FLAVOR='+('staging' if a.target=='cardeo-dev' else 'prod'),'--dart-define=APP_NAME=Cardeo','--dart-define=APP_BRAND_ID=cardeo','--dart-define=SUPPORT_EMAIL=support@cardeo.pro','--dart-define=ACCOUNT_TRANSFER_DASHBOARD_URL=https://cards.cardeo.pro','--dart-define=SPLIT_BILL_VISIBLE=true']
   run(['flutter','build','web',*flags],mobile)
   web=mobile/'build/web';worker=web/'cardeo_service_worker.js';text=worker.read_text()
   if text.count('cardeo-app-v2')!=1: raise ValueError('Cardeo cache marker missing')
   worker.write_text(text.replace('cardeo-app-v2','cardeo-app-'+revision[:12]))
   boot=web/'flutter_bootstrap.js';text=boot.read_text();engine=re.search(r'"engineRevision":"([0-9a-f]+)"',text);marker="var base = 'canvaskit/'; // CANVASKIT_BASE"
   if not engine or marker not in text: raise ValueError('CanvasKit marker missing')
   runtime='canvaskit-'+engine[1][:12];(web/'canvaskit').rename(web/runtime);boot.write_text(text.replace(marker,"var base = '"+runtime+"/';"))
   (web/'flutter_service_worker.js').unlink(missing_ok=True)
   html=web/'index.html';html.write_text(html.read_text().replace('<!-- CARDEO_PRECONNECT -->','<link rel="preconnect" href="'+cfg['url']+'" crossorigin>'))
  else:
   config=mobile/'config'/dict(hoppa='hoppa.json',songs='songs.production.json',fibi='fibi.production.json')[a.target]
   brand=json.loads(config.read_text())
   if brand.get('flutterDefines',{}).get('API_BASE_URL')!=cfg['url']: raise ValueError('Brand API does not match target')
   run(['bash',source/'scripts/build-mobile-branded.sh','web',config,*flags],source)
   web=mobile/'build/web'
   if a.target=='hoppa': run([sys.executable,source/'scripts/prepare-hoppa-pwa.py',web,'--commit',revision,'--config',config])
  # The independent release marker is retrievable without API credentials.
  manifest=json.loads((web/'deployment.json').read_text()) if (web/'deployment.json').exists() else {}
  manifest.update(commit=revision,platformContract='legacy-int-v1',target=a.target,apiBaseUrl=cfg['url'],mainJsSha256=digest(web/'main.dart.js'))
  (web/'deployment.json').write_text(json.dumps(manifest,indent=2)+'\n')
  for suffix in ['.gz','.br']: (web/('deployment.json'+suffix)).unlink(missing_ok=True)
  shutil.copytree(web,bundle/'web')
 if 'admin' in cfg:
  admin=source/'admin_vue';env=os.environ.copy();env['VITE_BACKEND_API_BASE_URL']=cfg['url']
  run(['npm','ci','--no-audit','--no-fund'],admin,env);run(['npm','run','build'],admin,env);shutil.copytree(admin/'dist',bundle/'admin')
 for component in ['api','web','admin']:
  if component in cfg: stamp(bundle/component,a.target,component,revision,'quickbit-pro/'+cfg['repo'])
 for script in ['activate-legacy.py','legacy_release.py']: shutil.copy2(source/'scripts'/script,bundle/script)
 print('Verified release bundle: '+str(bundle),flush=True)
 if a.deploy:
  host='rokkogovsek@20.52.4.175';ssh=['ssh'];socket=Path('/tmp/codex-game-ssh')
  if socket.exists(): ssh+=['-S',str(socket)]
  ssh+=['-o','BatchMode=yes'];remote='/tmp/legacy-'+a.target+'-'+revision
  run([*ssh,host,'mkdir','-p',remote]);run(['rsync','-az','-e',' '.join(ssh),str(bundle)+'/',host+':'+remote+'/'])
  run([*ssh,host,'sudo','python3',remote+'/activate-legacy.py',a.target,remote])
if __name__=='__main__': main()
