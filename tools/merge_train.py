#!/usr/bin/env python3
"""The apps-landing merge train: several lanes' ready commits verified once and landed together.

    merge_train.py submit --role ROLE --agent NAME --ref BRANCH [--dod REPORT]   offer a ready branch
    merge_train.py withdraw --role ROLE                                          take it back
    merge_train.py show                                                          the submissions, in train order
    merge_train.py setup [--worktree PATH]                                       create the train's worktree
    merge_train.py run --agent NAME [--max 4] [--dry-run]                        hold apps-landing first

Coordinator request, 2026-11-26: the apps-landing queue was 9 deep at 7-10 minutes a hold. A lane whose change is green
on its own module's definition of done submits its branch; the agent holding the apps-landing slot runs the train:

 1. it takes the first N submissions (N up to 4) in apps-landing queue order, then by submission time;
 2. it rebases each, in that order, onto fp/main in the train's worktree (`git rebase --onto`, so commits already on
    main drop out); a submission that conflicts fails alone, with its log;
 3. it runs ONE apps verification of the whole train ON POSIDON (owner direction, 2026-11-26: venus stays free for lane
    development). The candidate is pushed to posidon's bare repository as refs/heads/train-<stamp>; in the dedicated
    worktree ~/flint-work/wt-train, under posidon's host-wide hold, it emits the native blocks, builds flint, and runs
    the definition of done's apps step for gs-rest-service and petclinic-rest: both compilers, as built and with the
    static trim, exact acceptance, and `flint budget` once the CLI has it. Every run then deletes its private
    FLINT_CACHE and build outputs (posidon has about 18 GB free) and stops only its own DMD servers;
 4. green: it pushes them all. Red: it bisects by submission, pushes the green prefix, and puts the first failing role
    back at the head of the apps-landing queue with its log; later submissions stay for the next train;
 5. if main moved meanwhile, it rebases again; commits touching nothing in the apps' closure (the cheap-rebase rule)
    push without a second verification, otherwise the train verifies again.

Landed and failed lanes are told by agentctl mail, and every step is in coordination/events.jsonl. The train's state is
coordination/train.json, under agentctl's lock. Logs go to coordination/train/.
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import agentctl  # noqa: E402

SLOT = 'apps-landing'
APPS = ('gs-rest-service', 'petclinic-rest')
DEFAULT_WORKTREE = Path.home() / 'flint-work' / 'worktrees' / 'merge-train'
MAX_TRAIN = 4
# Paths outside every package's directory whose change can alter what the apps verification sees.
SHARED_PATHS = ('benchmarks/spring/', 'policy/', 'apps/flint/', 'dub.sdl', 'dub.selections.json', 'platform.lock',
                'toolchain/', 'native/', 'tools/definition_of_done.py', 'tools/spring_bench.py')


def git(args, cwd, check=True):
    done = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)
    if check and done.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {done.stderr.strip() or done.stdout.strip()}")
    return done


POSIDON = 'olfa@10.10.10.12'
POSIDON_KEY = Path.home() / '.ssh' / 'full-access-ssh-key'
POSIDON_SSH = ['ssh', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-i', str(POSIDON_KEY)]

# Runs on posidon with bash -s; @COMMIT@, @REF@, @STAMP@ and @APPS@ are filled in. Its exit status is the verification's.
POSIDON_SCRIPT = r'''
set -uo pipefail
source "$HOME/flint-work/posidon.env"
SHARED="$HOME/flint-work/flint"
WT="$HOME/flint-work/wt-train"
export FLINT_HOME="$WT" FLINT_CACHE="$HOME/flint-work/train-cache-@STAMP@"
cleanup() {
  # Only this run's servers: DMD fork servers whose environment names this run's FLINT_CACHE.
  for pid in $(pgrep -u "$USER" -f 'dmd' || true); do
    if tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -qx "FLINT_CACHE=$FLINT_CACHE"; then kill "$pid" 2>/dev/null; fi
  done
  rm -rf "$FLINT_CACHE" "$WT/.flint/definition-of-done" "$WT/.flint/build" "$WT/artifacts"
  rm -rf "$WT"/benchmarks/spring/flint/*/.flint/build "$WT"/benchmarks/spring/flint/*/.dub
  find "$WT" -xdev -name .dub -type d -prune -exec rm -rf {} + 2>/dev/null
  git --git-dir="$HOME/flint-work/flint.git" update-ref -d "refs/heads/@REF@"
}
trap cleanup EXIT
git -C "$SHARED" fetch -q origin "refs/heads/@REF@" || exit 3
[ -d "$WT" ] || git -C "$SHARED" worktree add -q --detach "$WT" "@COMMIT@" || exit 3
cd "$WT"
git checkout -q -f --detach "@COMMIT@" || exit 3
[ -e .tools ] || ln -s "$SHARED/.tools" .tools
mkdir -p .flint && { [ -e .flint/peers ] || ln -s "$SHARED/.flint/peers" .flint/peers; }
[ -d .native/install ] || { mkdir -p .native && cp -a "$SHARED/.native/install" .native/; }
export PATH="$WT/.flint/bin:$WT/.tools/dmd2/linux/bin64:$PATH"
H="python3 tools/measure_queue.py hold --"
echo "== native blocks"; $H python3 tools/native_build.py --profile ci --target linux-x86_64-glibc --phase build --emit-dub || exit 4
echo "== flint"; $H python3 tools/install_toolchains.py --compiler flint || exit 4
echo "== apps"; python3 tools/gates.py --module framework/web --definition-of-done --step apps --apps @APPS@
'''


class PosidonVerifier:
    """The train's apps verification on posidon. Called with a commit (and the venus repository that has it);
    returns (ok, log)."""

    def __init__(self, host=POSIDON, ssh=None, bare='flint-work/flint.git', url=None):
        self.host = host
        self.ssh = list(ssh or POSIDON_SSH)
        self.url = url or f'{host}:{bare}'

    def __call__(self, commit, repo):
        stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + commit[:8]
        ref = f'train-{stamp}'
        env = dict(os.environ, GIT_SSH_COMMAND=shlex.join(self.ssh))
        pushed = subprocess.run(['git', 'push', '-q', self.url, f'{commit}:refs/heads/{ref}'],
                                cwd=repo, env=env, capture_output=True, text=True)
        if pushed.returncode != 0:
            return False, f'pushing the candidate to posidon failed:\n{pushed.stderr}'
        script = POSIDON_SCRIPT
        for token, value in (('@COMMIT@', commit), ('@REF@', ref), ('@STAMP@', stamp), ('@APPS@', ','.join(APPS))):
            script = script.replace(token, value)
        done = subprocess.run([*self.ssh, self.host, 'bash', '-s'], input=script, capture_output=True, text=True)
        log = f'posidon {self.host}, ~/flint-work/wt-train at {commit} ({ref}):\n{done.stdout}{done.stderr}'
        return done.returncode == 0, log


def closure_paths(root):
    """The directories of every package in the apps' dependency closure, plus SHARED_PATHS."""
    import workspace
    edges = workspace.dependencies(root)
    directories = {name: meta[1] for name, meta in workspace.package_repos(root).items()}
    names, todo = set(), []
    for app in APPS:
        document = tomllib.loads((root / 'benchmarks' / 'spring' / 'flint' / app / 'flint.toml').read_text())
        todo += [d[6:] for section in ('dependencies', 'test-dependencies') for d in document.get(section, {})
                 if d.startswith('flint:')]
    while todo:
        name = todo.pop()
        if name not in names:
            names.add(name)
            todo += [d.removeprefix('flint:') for d in edges.get(name, [])]
    return tuple(sorted(directories[n].rstrip('/') + '/' for n in names if n in directories)) + SHARED_PATHS


def touches(paths, prefixes):
    return [p for p in paths if any(p == q.rstrip('/') or p.startswith(q) for q in prefixes)]


class Train:
    def __init__(self, store, repo=ROOT, worktree=DEFAULT_WORKTREE, remote='fp', branch='main', verify=None,
                 closure=None, log_dir=None, mail=True, verifier=None):
        self.store = store
        self.repo = Path(repo)
        self.worktree = Path(worktree)
        self.remote = remote
        self.branch = branch
        self.verify_commands = verify  # local commands (tests); otherwise the verifier, posidon by default
        self.verifier = verifier or (None if verify else PosidonVerifier())
        self.closure = closure
        self.log_dir = Path(log_dir) if log_dir else store.root / 'train'
        self.mail = mail
        self.verifications = 0

    # State.
    def submissions(self):
        return self.store._read_json('train.json', {}).get('submissions', [])

    def _write(self, submissions):
        self.store._write_json('train.json', {'submissions': submissions})

    def submit(self, role, agent, ref, dod=None):
        commit = git(['rev-parse', '--verify', ref + '^{commit}'], self.repo).stdout.strip()
        with self.store.locked():
            submissions = [s for s in self.submissions() if s['role'] != role]
            submissions.append({'role': role, 'agent': agent, 'ref': ref, 'commit': commit,
                                'submitted': agentctl.utc_now(), **({'dod': dod} if dod else {})})
            self._write(submissions)
            self.store.event('train-submit', role=role, agent=agent, ref=ref, commit=commit)
        return commit

    def withdraw(self, role):
        with self.store.locked():
            submissions = self.submissions()
            if not any(s['role'] == role for s in submissions):
                raise SystemExit(f'merge_train: {role} has no submission')
            self._write([s for s in submissions if s['role'] != role])
            self.store.event('train-withdraw', role=role)

    def ordered(self):
        """Submissions in apps-landing queue order (by agent), then by submission time."""
        queue, _, _ = self.store.queue_view(SLOT)
        position = {m['agent']: i for i, m in enumerate(queue.get('members', []))}
        return sorted(self.submissions(), key=lambda s: (position.get(s['agent'], len(position)), s['submitted']))

    # Git.
    def _fetch(self):
        git(['fetch', '-q', self.remote, self.branch], self.worktree)
        return git(['rev-parse', f'{self.remote}/{self.branch}'], self.worktree).stdout.strip()

    def build(self, batch, base):
        """Rebase each submission in order onto the train; returns ([(submission, tip)], [(submission, log)])."""
        git(['checkout', '-q', '--detach', base], self.worktree)
        applied, failed, tip = [], [], base
        for submission in batch:
            fork = git(['merge-base', base, submission['commit']], self.worktree).stdout.strip()
            git(['checkout', '-q', '--detach', submission['commit']], self.worktree)
            done = git(['rebase', '-q', '--onto', tip, fork], self.worktree, check=False)
            if done.returncode != 0:
                git(['rebase', '--abort'], self.worktree, check=False)
                git(['checkout', '-q', '--detach', tip], self.worktree)
                failed.append((submission, f'rebase onto the train failed (conflict):\n{done.stdout}{done.stderr}'))
                continue
            tip = git(['rev-parse', 'HEAD'], self.worktree).stdout.strip()
            applied.append((submission, tip))
        git(['checkout', '-q', '--detach', tip], self.worktree)
        return applied, failed

    def verify(self, commit):
        git(['checkout', '-q', '--detach', commit], self.worktree)
        self.verifications += 1
        if self.verifier:
            return self.verifier(commit, self.worktree)
        log = []
        for command in self.verify_commands:
            done = subprocess.run(command, cwd=self.worktree, capture_output=True, text=True,
                                  shell=isinstance(command, str))
            log.append(f'$ {command if isinstance(command, str) else shlex.join(command)}\n{done.stdout}{done.stderr}')
            if done.returncode != 0:
                return False, '\n'.join(log)
        return True, '\n'.join(log)

    def changed(self, old, new):
        return git(['diff', '--name-only', old, new], self.worktree).stdout.split()

    # The run.
    def run(self, agent, max_train=MAX_TRAIN, dry_run=False, attempts=3):
        lease = self.store.leases().get(SLOT)
        if not lease or lease['agent'] != agent or not self.store.lease_live(lease):
            raise SystemExit(f'merge_train: run the train while holding {SLOT}: python3 tools/agentctl.py claim {SLOT} '
                             f'--agent {agent} --harness <h> --ttl-min 40 (join its queue first if it is busy)')
        batch = self.ordered()[:max_train]
        if not batch:
            return {'landed': [], 'failed': [], 'pending': []}
        if dry_run:
            return {'batch': [s['role'] for s in batch]}
        if git(['status', '--porcelain', '--untracked-files=no'], self.worktree).stdout.strip():
            raise SystemExit(f'merge_train: {self.worktree} has uncommitted tracked changes; the train needs it clean')
        base = self._fetch()
        applied, failed = self.build(batch, base)
        landed, verified_tip = [], None
        if applied:
            ok, log = self.verify(applied[-1][1])
            if ok:
                landed, verified_tip = applied, applied[-1][1]
            else:
                good, bad, bad_log = 0, len(applied), log  # prefix lengths: main itself is green
                while bad - good > 1:
                    middle = (good + bad) // 2
                    ok, middle_log = self.verify(applied[middle - 1][1])
                    if ok:
                        good = middle
                    else:
                        bad, bad_log = middle, middle_log
                failed.append((applied[bad - 1][0], 'the apps verification failed with this submission on the train:\n'
                               + bad_log))
                landed = applied[:good]
                verified_tip = applied[good - 1][1] if good else None
        pushed = None
        if landed:
            pushed = self.push([s for s, _ in landed], base, verified_tip, attempts)
            if pushed is None:
                failed += [(s, 'main moved under the train and the train could not land; resubmitted') for s, _ in landed]
                landed = []
        return self.settle(batch, landed, failed, pushed)

    def push(self, submissions, base, tip, attempts):
        """Push the verified train; when main moved, rebase again and push, verifying again only if the new commits
        touch the apps' closure. Returns the pushed commit, or None."""
        closure = self.closure if self.closure is not None else closure_paths(self.worktree)
        for _ in range(attempts):
            done = git(['push', '-q', self.remote, f'{tip}:refs/heads/{self.branch}'], self.worktree, check=False)
            if done.returncode == 0:
                return tip
            new_base = self._fetch()
            moved = touches(self.changed(base, new_base), closure)
            applied, failed = self.build(submissions, new_base)
            if failed or len(applied) != len(submissions):
                return None
            tip, base = applied[-1][1], new_base
            if moved:
                ok, _ = self.verify(tip)
                if not ok:
                    return None
        return None

    def settle(self, batch, landed, failed, pushed):
        landed_roles = {s['role'] for s, _ in landed} if landed and pushed else set()
        failed_roles = {s['role']: log for s, log in failed}
        self.log_dir.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
        logs = {}
        for role, log in failed_roles.items():
            path = self.log_dir / f'{role}-{stamp}.log'
            path.write_text(log)
            logs[role] = str(path)
        with self.store.locked():
            submissions = [s for s in self.submissions() if s['role'] not in landed_roles | set(failed_roles)]
            self._write(submissions)
        for submission in batch:
            if submission['role'] in landed_roles:
                self._leave_queue(submission['agent'])
                self.store.event('train-land', role=submission['role'], commit=pushed)
            elif submission['role'] in failed_roles:
                self._front_of_queue(submission['agent'])
                self.store.event('train-fail', role=submission['role'], log=logs[submission['role']])
        if self.mail:
            for role in landed_roles:
                self._send(role, f'merge train: your submission landed on {self.branch} (train tip {pushed[:12]}).')
            for role, path in logs.items():
                self._send(role, f'merge train: your submission did not land; you are back at the head of the {SLOT} '
                                 f'queue. Log: {path}')
        return {'landed': sorted(landed_roles), 'failed': sorted(failed_roles), 'pushed': pushed, 'logs': logs,
                'pending': [s['role'] for s in self.ordered()], 'verifications': self.verifications}

    def _leave_queue(self, agent):
        try:
            self.store.queue(SLOT, 'leave', agent)
        except SystemExit:
            pass

    def _front_of_queue(self, agent):
        self.store.queue(SLOT, 'front', agent)

    def _send(self, role, text):
        if self.store.known(role) and role != SLOT:
            self.store.send(SLOT, [role], text)


def setup(worktree, repo=ROOT):
    """The train's venus worktree, detached at fp/main. Venus only rebases and pushes there; the apps verification
    runs on posidon, whose ~/flint-work/wt-train the verification creates on first use."""
    worktree = Path(worktree)
    if not worktree.exists():
        git(['fetch', '-q', 'fp', 'main'], repo)
        git(['worktree', 'add', '--detach', str(worktree), 'fp/main'], repo)
    return worktree


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='command', required=True)
    s = sub.add_parser('submit'); s.add_argument('--role', required=True); s.add_argument('--agent', required=True)
    s.add_argument('--ref', required=True, help='a branch or commit, green on its own module definition of done')
    s.add_argument('--dod', help='the module definition-of-done report that passed')
    s = sub.add_parser('withdraw'); s.add_argument('--role', required=True)
    sub.add_parser('show')
    s = sub.add_parser('setup'); s.add_argument('--worktree', type=Path, default=DEFAULT_WORKTREE)
    s = sub.add_parser('run'); s.add_argument('--agent', required=True)
    s.add_argument('--max', type=int, default=MAX_TRAIN, choices=range(1, MAX_TRAIN + 1))
    s.add_argument('--worktree', type=Path, default=DEFAULT_WORKTREE); s.add_argument('--dry-run', action='store_true')
    a = p.parse_args(argv)
    store = agentctl.Store(agentctl.coord_dir())
    if a.command == 'setup':
        print(setup(a.worktree))
        return 0
    train = Train(store, worktree=getattr(a, 'worktree', DEFAULT_WORKTREE))
    if a.command == 'submit':
        print(f"{a.role}: {train.submit(agentctl.check_role(a.role), a.agent, a.ref, a.dod)[:12]} submitted")
    elif a.command == 'withdraw':
        train.withdraw(a.role)
    elif a.command == 'show':
        for i, s in enumerate(train.ordered(), 1):
            print(f"{i}. {s['role']} ({s['agent']}) {s['ref']} {s['commit'][:12]} since {s['submitted']}")
    elif a.command == 'run':
        print(json.dumps(train.run(a.agent, a.max, a.dry_run), indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
