#!/usr/bin/env python3
"""Fail closed before building or deploying any legacy application."""
import argparse, json, re, subprocess
from pathlib import Path

CHECKS = {
 "backend/src/NeoBanking.Application/DTOs/Cards/CardDtos.cs": [r"public int\? CardId", r"public int\? CardTypeId", r"int.TryParse\(userId"],
 "backend/src/NeoBanking.Application/DTOs/Tiers/TierDtos.cs": [r"public int\? TierId", r"public int TierId"],
 "backend/src/NeoBanking.Infrastructure/Hoppa/HoppaOptions.cs": [r"public int CompanyId"],
 "backend/src/NeoBanking.Api/Company/CompanyOptions.cs": [r"public int\? DashboardCompanyId"],
 "backend/src/NeoBanking.Api/Controllers/ApiControllerBase.cs": [r"int.TryParse\(userId"],
 "backend/src/NeoBanking.Api/Controllers/MobileTiersController.cs": [r"TryGetInt32\(payload, out var selectedTierId"],
 "backend/src/NeoBanking.Infrastructure/Hoppa/HoppaClient.cs": [r"int.TryParse\(userId"],
 "mobile_flutter/lib/core/models/banking_models.dart": [r"final int\? cardTypeId;"],
}

def validate(root, target=None, check_origin=True):
    manifest=json.loads((root/'platform-contract.json').read_text())
    if manifest.get('family') != 'legacy-int-v1':
        raise ValueError('Only the legacy integer-ID contract may deploy to old apps.')
    repo=manifest['repository']
    allowed={'quickbit-pro/hoppa_demo_app':['cardeo-prod','cardeo-dev'], 'quickbit-pro/sample_mobile_app':['hoppa'], 'quickbit-pro/songs-wallet':['songs'], 'quickbit-pro/fibi-electronic':['fibi'], 'quickbit-pro/example_app':['demo']}
    if repo not in allowed or manifest.get('targets') != allowed[repo]:
        raise ValueError('Repository/target allowlist mismatch.')
    if target and target not in allowed[repo]:
        raise ValueError('This source repository cannot deploy to '+target)
    if check_origin:
        for push in [False,True]:
            cmd=['git','-C',str(root),'remote','get-url']+(['--push'] if push else [])+['--all','origin']
            urls=subprocess.check_output(cmd,text=True).strip().splitlines()
            valid={'https://github.com/'+repo, 'https://github.com/'+repo+'.git', 'git@github.com:'+repo, 'git@github.com:'+repo+'.git', 'ssh://git@github.com/'+repo+'.git'}
            if not urls or any(url not in valid for url in urls):
                raise ValueError('Wrong source origin. NewPlatform/UserApp must never deploy to legacy apps.')
    for file, patterns in CHECKS.items():
        source=(root/file).read_text()
        for pattern in patterns:
            if not re.search(pattern, source):
                raise ValueError('Legacy contract mismatch in '+file+': '+pattern)
    # These public DTO identifiers must never become UUIDs, even if another
    # numeric field happens to satisfy one of the checks above.
    for file in ['Cards/CardDtos.cs','Tiers/TierDtos.cs']:
        source=(root/'backend/src/NeoBanking.Application/DTOs'/file).read_text()
        if re.search(r'public Guid\?? (CardId|CardTypeId|TierId)\b',source):
            raise ValueError('UUID platform ID leaked into '+file)
    return manifest

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--target');p.add_argument('--archive',action='store_true')
    args=p.parse_args()
    try: result=validate(args.root.resolve(),args.target,not args.archive)
    except (ValueError,OSError,KeyError,subprocess.CalledProcessError) as error: p.exit(1,'Legacy deployment blocked: '+str(error)+'\n')
    print('Legacy contract verified: '+result['repository'])
