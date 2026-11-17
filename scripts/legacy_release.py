#!/usr/bin/env python3
"""Release identity and digest validation, also installed as a systemd startup gate."""
import argparse, hashlib, json, re
from pathlib import Path
TARGETS = {
 'cardeo-prod': dict(repo='hoppa_demo_app',api='/opt/cardeo/prod/api',web='/var/www/cardeo/prod/app',admin='/var/www/cardeo/prod/admin',service='cardeo-api@prod',port=5200,url='https://cardeo-api.roks.dev',public='https://my.cardeo.pro',user='cardeo'),
 'cardeo-dev': dict(repo='hoppa_demo_app',api='/opt/cardeo/dev/api',web='/var/www/cardeo/dev/app',admin='/var/www/cardeo/dev/admin',service='cardeo-api@dev',port=5201,url='https://cardeo-api-dev.roks.dev',public='https://cardeo-dev.roks.dev',user='cardeo'),
 'hoppa': dict(repo='sample_mobile_app',api='/opt/cardeo/hoppa/api',web='/var/www/cardeo/hoppa/app',admin='/var/www/cardeo/hoppa/admin',service='cardeo-api@hoppa',port=5202,url='https://hoppa-api.roks.dev',public='https://app.hoppa.global',user='cardeo'),
 'songs': dict(repo='songs-wallet',api='/opt/songs/api',web='/var/www/songs',service='songs-api',port=5203,url='https://api-app.songswallet.com',public='https://accounts.songswallet.com',user='songs'),
 'fibi': dict(repo='fibi-electronic',api='/opt/fibi/api',web='/var/www/fibi',service='fibi-api',port=5214,url='https://fibi-api.roks.dev',public='https://fibi.roks.dev',user='fibi'),
 'demo': dict(repo='example_app',api='/opt/neobanking/api',admin='/var/www/neobanking-admin',service='neobanking-api',port=5188,url='https://demo-api.roks.dev',public='https://demo-admin.roks.dev',user='neobanking'),
}
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def files(root,component):
 if component=='api':
  return sorted(p.name for p in root.glob('NeoBanking.*.dll'))
 return sorted(str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() and p.name!='legacy-release.json')
def stamp(root,target,component,revision,repository):
 if not re.fullmatch('[0-9a-f]{40}',revision): raise ValueError('Full source revision required')
 if repository!='quickbit-pro/'+TARGETS[target]['repo']: raise ValueError('Wrong repository')
 names=files(root,component)
 if not names: raise ValueError('Empty artifact')
 data=dict(platformContract='legacy-int-v1',target=target,component=component,revision=revision,repository=repository,sha256={n:digest(root/n) for n in names})
 (root/'legacy-release.json').write_text(json.dumps(data,indent=2)+'\n')
 verify(root,target,component)
 return data

def verify(root,target,component='api'):
 data=json.loads((root/'legacy-release.json').read_text())
 for k,v in dict(platformContract='legacy-int-v1',target=target,component=component,repository='quickbit-pro/'+TARGETS[target]['repo']).items():
  if data.get(k)!=v: raise ValueError('Release '+k+' mismatch')
 if not re.fullmatch('[0-9a-f]{40}',data.get('revision','')): raise ValueError('Invalid revision')
 required={'api':['NeoBanking.Api.dll','NeoBanking.Application.dll','NeoBanking.Infrastructure.dll','NeoBanking.Domain.dll'],'web':['index.html','main.dart.js'],'admin':['index.html']}[component]
 hashes=data.get('sha256',{})
 if any(n not in hashes for n in required) or set(hashes)!=set(files(root,component)): raise ValueError('Incomplete artifact digests')
 for name,expected in hashes.items():
  p=root/name
  if Path(name).is_absolute() or '..' in Path(name).parts or p.is_symlink() or digest(p)!=expected: raise ValueError('Artifact checksum mismatch: '+name)
 return data
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('target',choices=TARGETS);p.add_argument('directory',type=Path);p.add_argument('--component',default='api',choices=['api','web','admin']);a=p.parse_args()
 verify(a.directory,a.target,a.component)
 print('Verified legacy release: '+a.target)
