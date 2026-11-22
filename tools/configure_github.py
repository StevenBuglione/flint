#!/usr/bin/env python3
"""Prepare, or explicitly apply, the repository owner's required CI ruleset."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
NAME='Flint required CI'
CONTEXT='Flint / all six gates'

def require(condition,message):
    if not condition:raise ValueError(message)

def payload(branch,integration_id=None):
    check={'context':CONTEXT}
    if integration_id is not None:check['integration_id']=integration_id
    return {'name':NAME,'target':'branch','enforcement':'active','bypass_actors':[],
        'conditions':{'ref_name':{'include':['refs/heads/'+branch],'exclude':[]}},
        'rules':[
            {'type':'required_status_checks','parameters':{
                'strict_required_status_checks_policy':True,'do_not_enforce_on_create':False,
                'required_status_checks':[check]}},
            {'type':'pull_request','parameters':{
                'required_approving_review_count':1,'dismiss_stale_reviews_on_push':True,
                'require_code_owner_review':True,'require_last_push_approval':True,
                'required_review_thread_resolution':True}},
            {'type':'non_fast_forward'}]}

def api(arguments):
    command=['gh','api','-H','Accept: application/vnd.github+json',
             '-H','X-GitHub-Api-Version: 2026-03-10',*arguments]
    return json.loads(subprocess.check_output(command,text=True))

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',required=True,help='OWNER/REPO, never inferred from credentials')
    parser.add_argument('--branch',default='main')
    parser.add_argument('--integration-id',type=int,help='Optional verified GitHub App ID for the required status')
    parser.add_argument('--output',type=Path,default=ROOT/'artifacts/github-ruleset.json')
    parser.add_argument('--apply',action='store_true',help='Owner-authorized remote ruleset create/update; otherwise only write JSON locally')
    args=parser.parse_args(argv)
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',args.repo),'repo must be OWNER/REPO')
    require(re.fullmatch(r'[A-Za-z0-9_./-]+',args.branch) and '..' not in args.branch and not args.branch.endswith('/'),
            'invalid protected branch name')
    require(args.integration_id is None or args.integration_id>0,'integration ID must be a verified positive integer')
    body=payload(args.branch,args.integration_id)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(body,indent=2)+'\n')
    print('Prepared exact ruleset JSON at',args.output)
    if not args.apply:
        print('No GitHub settings changed. Review the JSON and real baseline evidence before an owner uses --apply.')
        return 0
    owners=ROOT/'.github/CODEOWNERS'
    require(owners.is_file(),'commit a real .github/CODEOWNERS file before enabling the owner-review rule')
    lines=[line.strip() for line in owners.read_text().splitlines() if line.strip() and not line.lstrip().startswith('#')]
    for pattern in ('/.github/','/tools/','/policy/','/benchmarks/'):
        require(any(line.split()[0] in (pattern,'*','/*') and any(word.startswith('@') for word in line.split()[1:]) for line in lines),
                'CODEOWNERS does not designate owners for '+pattern)
    repository=api(['repos/'+args.repo])
    require(repository.get('permissions',{}).get('admin') is True,'repository administration permission is required')
    pages=api(['repos/'+args.repo+'/rulesets','--paginate','--slurp'])
    existing=[rule for page in pages for rule in page if rule.get('name')==NAME and rule.get('source_type')=='Repository']
    require(len(existing)<=1,'multiple Flint rulesets exist; reconcile them explicitly')
    endpoint='repos/'+args.repo+'/rulesets'
    method='POST'
    if existing:endpoint+='/'+str(existing[0]['id']);method='PUT'
    result=api(['--method',method,endpoint,'--input',str(args.output.resolve())])
    require(result.get('enforcement')=='active','GitHub did not return an active ruleset')
    print(json.dumps({'ruleset_id':result['id'],'enforcement':result['enforcement'],
                      'required_status':CONTEXT,'repository':args.repo},indent=2))
    return 0

if __name__=='__main__':
    try:raise SystemExit(main())
    except (ValueError,KeyError,OSError,subprocess.SubprocessError) as error:
        print('GITHUB CONFIGURATION BLOCKED:',error,file=sys.stderr);raise SystemExit(1)
