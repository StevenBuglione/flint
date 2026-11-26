#!/usr/bin/env python3
"""The apps-landing merge train: several lanes' ready commits verified once and landed together.

    merge_train.py submit --role ROLE --agent NAME --ref BRANCH [--dod REPORT]   offer a ready branch
    merge_train.py withdraw --role ROLE                                          take it back
    merge_train.py show                                                          the submissions, in train order
    merge_train.py setup [--worktree PATH]                                       create the train's worktree
    merge_train.py run --agent NAME [--max 4] [--dry-run]                        hold apps-landing first
    merge_train.py serve [--agent merge-train] [--poll 15]                       the continuous scheduler (venus)

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
import re
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
SHARED_PATHS = ('benchmarks/spring/', 'apps/flint/', 'dub.sdl', 'dub.selections.json', 'platform.lock', 'toolchain/',
                'native/', 'tools/definition_of_done.py', 'tools/spring_bench.py', 'policy/request-allocations.json',
                'policy/profiles.toml', 'policy/native-lock.json', 'policy/native-c.toml', 'policy/peer-lock.json',
                'policy/toolchains.json', 'policy/platform.toml', 'policy/budgets.json')
# Package registries: a change counts only when it changes an entry of a package in the apps' closure (coordinator,
# 02:14Z: shared policy files alone don't need the slot).
REGISTRIES = {'policy/framework.json': 'modules', 'policy/packages.json': 'packages', 'policy/boot.json': 'libraries'}
# Never build inputs: docs, the gates' baselines and inventories, and the flint CLI's tests and API-coverage code.
NOT_BUILD = ('.md',)
NOT_BUILD_NAMES = ('upstream-tests.json', 'closure-baseline.json', 'leaf-budgets.json', 'coverage-baseline.json')
NOT_BUILD_PREFIXES = ('apps/flint/test/', 'apps/flint/src/flint_tool/api/', 'docs/')


# Append-only logs every lane adds to: two lanes' entries at the end conflict textually but never in meaning, so the
# train's own rebases keep both (git's built-in union driver). Lanes' own rebases are unaffected.
UNION_FILES = ('docs/spring/performance-playbook.md', 'docs/spring/phase1/decisions.md')
# Generated pages: a conflict confined to them is resolved by regenerating them (coordinator, 2026-11-26); the API gate
# on the candidate then proves the result.
GENERATED_FILES = ('docs/spring/java-differences.md', 'docs/spring/api-mapping.md')
REGENERATE = [sys.executable, 'tools/api_differences.py', '--write']


def git(args, cwd, check=True):
    done = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)
    if check and done.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {done.stderr.strip() or done.stdout.strip()}")
    return done


SSH_KEY = Path.home() / '.ssh' / 'full-access-ssh-key'
SSH = ['ssh', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-i', str(SSH_KEY)]
POSIDON = 'olfa@10.10.10.12'
POSIDON_SSH = SSH
VERIFIERS_FILE = 'train/verifiers.json'  # in the coordination directory
# Built in, so a fresh checkout trains on posidon; coordination/train/verifiers.json adds or replaces verifiers.
DEFAULT_VERIFIERS = [{
    'name': 'posidon', 'host': POSIDON, 'budget': True,
    'prelude': 'source "$HOME/flint-work/posidon.env"',
    'push_to': 'flint-work/flint.git', 'bare': '$HOME/flint-work/flint.git', 'repo': '$HOME/flint-work/flint',
    'worktree': '$HOME/flint-work/wt-train', 'tools': '$HOME/flint-work/flint/.tools',
    'peers': '$HOME/flint-work/flint/.flint/peers', 'native_install': '$HOME/flint-work/flint/.native/install',
    'cache_root': '$HOME/flint-work', 'receipts': {}}]

# Runs on a verifier with bash -s; the @NAME@ tokens are filled in from its entry. Exit status: 0 green, 1/2/4 red
# (the candidate's apps, its native shims or its flint fail), 3 git setup and 5 a receipt mismatch: the verifier, not
# the candidate, so nobody is blamed.
VERIFY_SCRIPT = r"""
set -uo pipefail
BARE="@BARE@"; REPO="@REPO@"; WT="@WORKTREE@"
export FLINT_HOME="$WT" FLINT_CACHE="@CACHE_ROOT@/train-cache-@STAMP@"
@PRELUDE@
cleanup() {
  # Only this run's servers: DMD fork servers whose environment names this run's FLINT_CACHE.
  for pid in $(pgrep -u "$USER" -f 'dmd' || true); do
    if tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -qx "FLINT_CACHE=$FLINT_CACHE"; then kill "$pid" 2>/dev/null; fi
  done
  rm -rf "$FLINT_CACHE" "$FLINT_CACHE.dod.json" "$FLINT_CACHE.api.json" "$WT/.flint/definition-of-done" "$WT/.flint/build" "$WT/artifacts"
  # Each app's whole .flint (its dub cache grew to 5 GB on posidon) and the CLI's build tree; the natives stay.
  rm -rf "$WT"/benchmarks/spring/flint/*/.flint "$WT"/benchmarks/spring/flint/*/.dub "$WT/apps/flint/.flint/build"
  find "$WT" -xdev -name .dub -type d -prune -exec rm -rf {} + 2>/dev/null
  git --git-dir="$BARE" update-ref -d "refs/heads/@REF@"
}
trap cleanup EXIT
echo "== receipts"
RECEIPTS="@RECEIPTS@"
if [ -n "$RECEIPTS" ]; then
  ( cd "$HOME" && printf '%s' "$RECEIPTS" | sha256sum --quiet -c - ) || { echo "receipt mismatch: this verifier's toolchain changed; re-pin it"; exit 5; }
fi
[ "$REPO" = "$BARE" ] || git -C "$REPO" fetch -q origin "refs/heads/@REF@" || exit 3
[ -d "$WT" ] || git -C "$REPO" worktree add -q --detach "$WT" "@COMMIT@" || exit 3
cd "$WT"
git checkout -q -f --detach "@COMMIT@" || exit 3
[ -e .tools ] || ln -s "@TOOLS@" .tools
mkdir -p .flint && { [ -e .flint/peers ] || ln -s "@PEERS@" .flint/peers; }
relocate() {
  # A native prefix built elsewhere (its receipt and .pc files name that machine's path): copy the build-tree link
  # metadata the receipt digests, rewrite the old prefix to this one, and re-digest what the rewrite changed.
  local old="$1" from; from="$(dirname "@NATIVE_INSTALL@")/build"
  mkdir -p .native/build
  ( cd "$from" && find . \( -name native-static-link.json -o -name system-link.json \) -exec cp --parents {} "$WT/.native/build/" \; )
  grep -rlI "$old" .native/install .native/build | xargs -r sed -i "s#$old#$WT/.native#g"
  python3 - <<'PY'
import hashlib, json, pathlib
def walk(node):
    if isinstance(node, dict):
        if isinstance(node.get('path'), str) and isinstance(node.get('sha256'), str) and pathlib.Path(node['path']).is_file():
            node['sha256'] = hashlib.sha256(pathlib.Path(node['path']).read_bytes()).hexdigest()
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)
for receipt in pathlib.Path('.native/install').glob('*/flint-native-install.json'):
    data = json.loads(receipt.read_text()); walk(data); receipt.write_text(json.dumps(data, indent=2) + '\n')
PY
}
if [ ! -d .native/install ]; then
  { mkdir -p .native && cp -a "@NATIVE_INSTALL@" .native/ && @NATIVE_FIX@; } || exit 3
  [ -z "@RELOCATE_FROM@" ] || relocate "@RELOCATE_FROM@" || exit 3
fi
export PATH="$WT/.flint/bin:$WT/.tools/dmd2/linux/bin64:$PATH"
H="python3 tools/measure_queue.py hold --"
# A full native build only when what defines the libraries changed since the last one here; otherwise just the Flint
# C shims over the installed libraries, plus the dub blocks (a full build recompiles OpenSSL every time).
INPUTS=$(git ls-tree -r HEAD -- policy/native-lock.json policy/native-c.toml tools/native_build.py native/conan-index | sha256sum | cut -c1-64)
SHIMS=""; [ -f .native/train-native-inputs ] && [ "$(cat .native/train-native-inputs)" = "$INPUTS" ] && SHIMS="--shims-only"
[ "@FULL_NATIVE@" = yes ] || SHIMS="--shims-only"
echo "== native blocks ${SHIMS:-full build}"
$H python3 tools/native_build.py --profile ci --target linux-x86_64-glibc --phase build $SHIMS --emit-dub || exit 4
echo "$INPUTS" > .native/train-native-inputs
echo "== flint"; $H python3 tools/install_toolchains.py --compiler flint || exit 4
echo "== api gate"; $H python3 tools/gates.py --gate api > "$FLINT_CACHE.api.json" 2>&1 || { tail -40 "$FLINT_CACHE.api.json"; rm -f "$FLINT_CACHE.api.json"; exit 1; }
rm -f "$FLINT_CACHE.api.json"
echo "== apps"; python3 tools/gates.py --module framework/web --definition-of-done --step apps --apps @APPS@ @DOD_FLAGS@ --json > "$FLINT_CACHE.dod.json"; rc=$?
cat "$FLINT_CACHE.dod.json"
if [ $rc -ne 0 ]; then
  # Decision 6478897a: a borderline flint budget miss (every failure an instruction miss under twice its tolerance)
  # is re-measured, and the median of 5 runs is judged; anything else stays red.
  apps=$(python3 - "$FLINT_CACHE.dod.json" <<'PY'
import json, re, sys
text, report, at = open(sys.argv[1]).read(), None, 0
while report is None and text.find('{', at) >= 0:
    at = text.find('{', at)
    try:
        found, end = json.JSONDecoder().raw_decode(text[at:])
        report = found if isinstance(found, dict) and 'steps' in found else None
        at += max(end, 1)
    except ValueError:
        at += 1
step = next((s for s in (report or {}).get('steps', []) if s['step'] == 'apps'), None)
if step is None:
    sys.exit(1)
bad = [k for k, v in step['details'].items() if k != 'apps' and not str(v).startswith(('pass', 'skip'))]
lines = [m for m in step['messages'] if m.strip().startswith('budget:')]
if not bad or not lines or any(not k.endswith(' flint budget') for k in bad):
    sys.exit(1)
for line in lines:
    found = re.search(r': instructions [0-9,]+ -> [0-9,]+ \(\+([0-9.]+)%, tolerance \+([0-9.]+)%\)', line)
    if not found or float(found.group(1)) >= 2 * float(found.group(2)):
        sys.exit(1)
print(' '.join(sorted(k[:-len(' flint budget')] for k in bad)))
PY
) || exit $rc
  echo "== borderline flint budget miss: re-measuring $apps (median of 5, decision 6478897a)"
  set -- ; for app in $apps; do set -- "$@" --app "$app"; done
  $H flint budget "$@" --repeat 5 && { echo "the median of 5 is within budget"; exit 0; }
  exit 1
fi
"""
POSIDON_SCRIPT = VERIFY_SCRIPT  # the name earlier tests and notes use
UNAVAILABLE = (3, 5, 255)  # git setup, a receipt mismatch, ssh itself


def load_verifiers(store):
    """The configured verifiers: coordination/train/verifiers.json if present ({"verifiers": [...]}), else posidon."""
    path = store.root / VERIFIERS_FILE
    entries = json.loads(path.read_text())['verifiers'] if path.is_file() else DEFAULT_VERIFIERS
    return [RemoteVerifier(entry) for entry in entries if entry.get('enabled', True)]


class RemoteVerifier:
    """One verifier: a host plus a worktree (coordinator, 2026-11-26). Called with a commit and the venus repository
    that has it; returns (ok, log), ok None when the verifier itself failed (nobody is blamed)."""

    def __init__(self, entry, ssh=None, url=None):
        self.entry = dict(entry)
        self.name = entry['name']
        self.host = entry['host']
        self.budget = bool(entry.get('budget'))
        self.ssh = list(ssh or entry.get('ssh') or SSH)
        self.url = url or entry.get('url') or f"{self.host}:{entry['push_to']}"

    def script(self, commit, ref, stamp):
        e = self.entry
        receipts = ''.join(f'{digest}  {path}\n' for path, digest in sorted(e.get('receipts', {}).items()))
        values = {'@PRELUDE@': e.get('prelude', ''), '@BARE@': e['bare'], '@REPO@': e.get('repo', e['bare']),
                  '@WORKTREE@': e['worktree'], '@TOOLS@': e['tools'], '@PEERS@': e['peers'],
                  '@NATIVE_INSTALL@': e['native_install'], '@NATIVE_FIX@': e.get('native_fix', 'true'),
                  '@RELOCATE_FROM@': e.get('native_relocate_from', ''),
                  '@FULL_NATIVE@': 'yes' if e.get('full_native', True) else 'no',
                  '@CACHE_ROOT@': e.get('cache_root', '$HOME'), '@RECEIPTS@': receipts,
                  '@DOD_FLAGS@': '' if self.budget else '--no-flint-budget', '@APPS@': ','.join(APPS),
                  '@COMMIT@': commit, '@REF@': ref, '@STAMP@': stamp}
        text = VERIFY_SCRIPT
        for token, value in values.items():
            text = text.replace(token, value)
        return text

    def __call__(self, commit, repo):
        stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + commit[:8]
        ref = f'train-{stamp}'
        env = dict(os.environ, GIT_SSH_COMMAND=shlex.join(self.ssh))
        pushed = subprocess.run(['git', 'push', '-q', self.url, f'{commit}:refs/heads/{ref}'],
                                cwd=repo, env=env, capture_output=True, text=True)
        if pushed.returncode != 0:
            return None, f'{self.name}: pushing the candidate failed:\n{pushed.stderr}'
        done = subprocess.run([*self.ssh, self.host, 'bash', '-s'], input=self.script(commit, ref, stamp),
                              capture_output=True, text=True)
        log = f'{self.name} ({self.host}), {self.entry["worktree"]} at {commit} ({ref}):\n{done.stdout}{done.stderr}'
        if done.returncode in UNAVAILABLE:
            return None, log
        return done.returncode == 0, log

    def pin(self, paths):
        """Record the sha256 of `paths` (relative to the verifier's home) as its receipts."""
        done = subprocess.run([*self.ssh, self.host, 'cd "$HOME" && sha256sum ' + ' '.join(shlex.quote(p) for p in paths)],
                              capture_output=True, text=True, check=True)
        return {line.split(None, 1)[1].strip(): line.split()[0] for line in done.stdout.splitlines() if line.strip()}


def PosidonVerifier(host=POSIDON, ssh=None, bare='flint-work/flint.git', url=None):
    """posidon's built-in entry (kept for callers and tests of the first version)."""
    entry = dict(DEFAULT_VERIFIERS[0], host=host, push_to=bare)
    return RemoteVerifier(entry, ssh=ssh, url=url)


def closure_paths(root):
    """The directories of every package in the apps' dependency closure, plus SHARED_PATHS."""
    import workspace
    directories = {name: meta[1] for name, meta in workspace.package_repos(root).items()}
    names = closure_names(root)
    return tuple(sorted(directories[n].rstrip('/') + '/' for n in names if n in directories)) + SHARED_PATHS


def closure_names(root):
    """Every package in the apps' dependency closure."""
    import workspace
    edges = workspace.dependencies(root)
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
    return names


def build_relevant(paths, closure, names=None, show=None):
    """The changed paths that can alter the apps verification: under the closure, not docs or gate metadata, and for
    a package registry only when an entry of a closure package changed (`show(path)` -> (old text, new text))."""
    relevant = []
    for path in paths:
        if path.endswith(NOT_BUILD) or path.rsplit('/', 1)[-1] in NOT_BUILD_NAMES or path.startswith(NOT_BUILD_PREFIXES):
            continue
        if path == 'dub.sdl' and show is not None:
            # Registering a new package (a subPackage line) outside the apps' closure cannot change their build.
            old, new = show(path)
            changed = set(old.splitlines()) ^ set(new.splitlines())
            outside = all(re.fullmatch(r'\s*subPackage\s+"([^"]+)"\s*', line) and not
                          touches([re.fullmatch(r'\s*subPackage\s+"([^"]+)"\s*', line).group(1).rstrip('/') + '/'],
                                  closure) for line in changed if line.strip())
            if not outside:
                relevant.append(path)
            continue
        if path in REGISTRIES:
            if names is None or show is None:
                continue
            old, new = show(path)
            section = REGISTRIES[path]
            entries = lambda text: (json.loads(text).get(section, {}) if text else {})
            before, after = entries(old), entries(new)
            if any(before.get(n) != after.get(n) for n in names):
                relevant.append(path)
            continue
        if touches([path], closure):
            relevant.append(path)
    return relevant


def touches(paths, prefixes):
    return [p for p in paths if any(p == q.rstrip('/') or p.startswith(q) for q in prefixes)]


class Train:
    def __init__(self, store, repo=ROOT, worktree=DEFAULT_WORKTREE, remote='fp', branch='main', verify=None,
                 closure=None, log_dir=None, mail=True, verifier=None, verifiers=None):
        self.store = store
        self.repo = Path(repo)
        self.worktree = Path(worktree)
        self.remote = remote
        self.branch = branch
        self.verify_commands = verify  # local commands (tests); otherwise the remote verifiers
        if verifiers is None:
            verifiers = [verifier] if verifier else ([] if verify else load_verifiers(store))
        # The budget verifier last: it gets the deepest candidate, so flint budget covers everything that lands.
        self.verifiers = sorted(verifiers, key=lambda v: bool(getattr(v, 'budget', False)))
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
        # A submission is served in queue order: one whose agent is not queued (it left when an earlier commit landed)
        # would wait at the back unseen, so submitting also joins the queue.
        queue, _, _ = self.store.queue_view(SLOT)
        if agent not in [m['agent'] for m in queue.get('members', [])]:
            try:
                self.store.queue(SLOT, 'join', agent)
            except SystemExit:
                pass
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
            done = git(['-c', f'core.attributesFile={self.attributes()}', 'rebase', '-q', '--onto', tip, fork],
                       self.worktree, check=False)
            if done.returncode != 0:
                done = self.regenerate_through(done)
            if done.returncode != 0:
                git(['rebase', '--abort'], self.worktree, check=False)
                git(['checkout', '-q', '--detach', tip], self.worktree)
                failed.append((submission, f'rebase onto the train failed (conflict):\n{done.stdout}{done.stderr}'))
                continue
            tip = git(['rev-parse', 'HEAD'], self.worktree).stdout.strip()
            applied.append((submission, tip))
        git(['checkout', '-q', '--detach', tip], self.worktree)
        return applied, failed

    def verify(self, commit, verifier=None):
        """(ok, log): True green, False red, None the verifier could not run."""
        self.verifications += 1
        if self.verifiers:
            return (verifier or self.verifiers[-1])(commit, self.worktree)
        git(['checkout', '-q', '--detach', commit], self.worktree)
        log = []
        for command in self.verify_commands:
            done = subprocess.run(command, cwd=self.worktree, capture_output=True, text=True,
                                  shell=isinstance(command, str))
            log.append(f'$ {command if isinstance(command, str) else shlex.join(command)}\n{done.stdout}{done.stderr}')
            if done.returncode != 0:
                return False, '\n'.join(log)
        return True, '\n'.join(log)

    def regenerate_through(self, done):
        """Continue a stopped rebase while each stop conflicts only in generated pages: regenerate them, stage them,
        continue. Returns the last git result (returncode 0 when the rebase completed)."""
        for _ in range(50):
            conflicted = git(['diff', '--name-only', '--diff-filter=U'], self.worktree, check=False).stdout.split()
            if not conflicted or any(path not in GENERATED_FILES for path in conflicted):
                return done
            regenerated = subprocess.run(REGENERATE, cwd=self.worktree, capture_output=True, text=True)
            if regenerated.returncode != 0:
                return regenerated
            if any('<<<<<<<' in (self.worktree / path).read_text() for path in GENERATED_FILES
                   if (self.worktree / path).is_file()):
                return done  # a conflict in a hand-written part of the page: a real one
            git(['add', '--', *GENERATED_FILES], self.worktree, check=False)
            self.store.event('train-regenerated', files=conflicted)
            done = git(['-c', 'core.editor=true', '-c', f'core.attributesFile={self.attributes()}', 'rebase',
                        '--continue'], self.worktree, check=False)
            if done.returncode == 0:
                return done
        return done

    def attributes(self):
        path = self.log_dir / 'merge.attributes'
        text = ''.join(f'{name} merge=union\n' for name in UNION_FILES)
        if not path.is_file() or path.read_text() != text:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        return path

    def budget_lanes(self, count):
        """Whether candidate k of `count` is verified with flint budget (the verifier verify_all gives it)."""
        lanes = self.verifiers[-count:] if self.verifiers else []
        return [bool(getattr(v, 'budget', False)) for v in lanes] or [False] * count

    def verify_all(self, commits):
        """Verify candidate k on verifier k, concurrently; results in candidate order."""
        if len(commits) == 1:
            return [self.verify(commits[0])]
        from concurrent.futures import ThreadPoolExecutor
        # The deepest candidate goes to the last verifier (the budget one).
        pairs = list(zip(commits, self.verifiers[-len(commits):]))
        with ThreadPoolExecutor(len(pairs)) as pool:
            return list(pool.map(lambda pair: self.verify(*pair), pairs))

    def show(self, commit, path):
        done = git(['show', f'{commit}:{path}'], self.worktree, check=False)
        return done.stdout if done.returncode == 0 else ''

    def closure_names(self):
        if self.closure is not None:
            return None  # tests give paths directly
        try:
            return closure_names(self.worktree)
        except Exception:
            return None

    def changed(self, old, new):
        return git(['diff', '--name-only', old, new], self.worktree).stdout.split()

    # The run.
    def run(self, agent, max_train=MAX_TRAIN, dry_run=False, attempts=6):
        lease = self.store.leases().get(SLOT)
        if not lease or lease['agent'] != agent or not self.store.lease_live(lease):
            raise SystemExit(f'merge_train: run the train while holding {SLOT}: python3 tools/agentctl.py claim {SLOT} '
                             f'--agent {agent} --harness <h> --ttl-min 40 (join its queue first if it is busy)')
        batch = self.ordered()[:max_train * max(1, len(self.verifiers))]
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
            # Speculative stacking: candidate k is main plus groups 1..k (up to max_train submissions each), one per
            # verifier, all verified at once; they land in strict order.
            lanes = max(1, len(self.verifiers))
            ends = [min(len(applied), (k + 1) * max_train) for k in range(lanes) if k * max_train < len(applied)]
            results = self.verify_all([applied[end - 1][1] for end in ends])
            first = next((k for k, (ok, _) in enumerate(results) if ok is not True), None)
            if first is not None and first > 0 and results[first][0] is False and self.budget_lanes(len(ends))[first] \
                    and not all(self.budget_lanes(len(ends))[:first]):
                # Red on the budget verifier, but the green candidates before it were checked without flint budget:
                # that green is no budget baseline. Budget-check the green prefix once; if it holds, only the red
                # group is bisected, otherwise the culprit is in the prefix, which is bisected instead.
                prefix_ok, prefix_log = self.verify(applied[ends[first - 1] - 1][1])
                self.store.event('train-budget-prefix', candidates=first, prefix_green=prefix_ok)
                if not prefix_ok:
                    # Red (bisect the prefix, from nothing landed) or unavailable (land nothing): either way the
                    # candidate to resolve is the prefix itself.
                    ends, results, first = [ends[first - 1]], [(prefix_ok, prefix_log)], 0
            if first is None:
                landed, verified_tip = applied, applied[-1][1]
            else:
                good, bad = (ends[first - 1] if first else 0), ends[first]
                ok, bad_log = results[first]
                if ok is None:  # the verifier failed: land what is green before it, blame nobody
                    landed = applied[:good]
                    verified_tip = applied[good - 1][1] if good else None
                    self.store.event('train-verifier-failed', log=bad_log[-2000:])
                else:
                    while bad - good > 1:  # bisect the red group on top of the green candidates before it
                        middle = (good + bad) // 2
                        ok, middle_log = self.verify(applied[middle - 1][1])
                        if ok is None:
                            bad = None
                            break
                        if ok:
                            good = middle
                        else:
                            bad, bad_log = middle, middle_log
                    if bad is None:
                        self.store.event('train-verifier-failed', log=middle_log[-2000:])
                    elif bad == 1 and self.verify(base)[0] is not True:
                        # Main itself is red: blame nobody; every submission waits for main to be fixed.
                        self.store.event('train-main-red', base=base)
                        return {'landed': [], 'failed': [], 'pushed': None, 'logs': {}, 'main_red': base,
                                'pending': [s['role'] for s in self.ordered()], 'verifications': self.verifications}
                    else:
                        failed.append((applied[bad - 1][0], 'the apps verification failed with this submission on '
                                       'the train:\n' + bad_log))
                    landed = applied[:good]
                    verified_tip = applied[good - 1][1] if good else None
        pushed = None
        if landed:
            pushed = self.push([s for s, _ in landed], base, verified_tip, attempts)
            if pushed is None:  # main kept moving or a re-verification failed: they stay submitted for the next train
                self.store.event('train-push-failed', roles=[s['role'] for s, _ in landed])
                for submission, _ in reversed(landed):  # back to the head, in train order, and told
                    self._front_of_queue(submission['agent'])
                    if self.mail:
                        self._send(submission['role'], f"merge train: your submission {submission['commit'][:12]} was "
                                   f'verified but could not land (main kept moving under the push). It stays submitted '
                                   f'and you are back at the head of the {SLOT} queue for the next train; nothing to do.')
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
            moved = build_relevant(self.changed(base, new_base), closure, self.closure_names(),
                                   lambda path, old=base, new=new_base: (self.show(old, path), self.show(new, path)))
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
        """Remove exactly the submissions that rode this train (by role AND commit): a role that resubmitted while the
        train ran keeps its newer submission and its place in the queue (framework-core, 2026-11-26)."""
        landed_keys = {(s['role'], s['commit']) for s, _ in landed} if landed and pushed else set()
        failed_logs = {(s['role'], s['commit']): log for s, log in failed}
        landed_roles = {role for role, _ in landed_keys}
        self.log_dir.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
        logs = {}
        for (role, _), log in failed_logs.items():
            path = self.log_dir / f'{role}-{stamp}.log'
            path.write_text(log)
            logs[role] = str(path)
        with self.store.locked():
            submissions = [s for s in self.submissions()
                           if (s['role'], s['commit']) not in landed_keys | set(failed_logs)]
            self._write(submissions)
        newer = {s['role'] for s in submissions}
        for submission in batch:
            key = (submission['role'], submission['commit'])
            if key in landed_keys:
                if submission['role'] not in newer:
                    self._leave_queue(submission['agent'])
                self.store.event('train-land', role=submission['role'], commit=pushed, submitted=submission['commit'])
            elif key in failed_logs:
                self._front_of_queue(submission['agent'])
                self.store.event('train-fail', role=submission['role'], log=logs[submission['role']],
                                 submitted=submission['commit'])
        if self.mail:
            for role in landed_roles:
                rode = next(c for r, c in landed_keys if r == role)[:12]
                later = (' Your newer submission stays queued for the next train.' if role in newer else '')
                self._send(role, f'merge train: your submission {rode} landed on {self.branch} (train tip '
                                 f'{pushed[:12]}).{later}')
            for role, path in logs.items():
                later = (' Your newer submission is queued and goes next.' if role in newer else ' Fix it and resubmit.')
                self._send(role, f'merge train: your submission did not land; you are back at the head of the {SLOT} '
                                 f'queue.{later} Log: {path}')
        return {'landed': sorted(landed_roles), 'failed': sorted(r for r, _ in failed_logs), 'pushed': pushed,
                'logs': logs, 'pending': [s['role'] for s in self.ordered()], 'verifications': self.verifications}

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


def next_train(store, submissions):
    """Whether the scheduler should run a train now: the slot is free, something is submitted, and the head of the
    apps-landing queue (if any) is a submitter, so a lane landing by hand keeps its turn."""
    if not submissions:
        return False
    lease = store.leases().get(SLOT)
    if lease and store.lease_live(lease):
        return False
    queue, _, _ = store.queue_view(SLOT)
    submitters = {s['agent'] for s in submissions}
    members = [m for m in queue.get('members', [])]
    # Lanes the train returned ('retry') keep their place for when they resubmit, but don't block it meanwhile.
    while members and members[0].get('retry') and members[0]['agent'] not in submitters:
        members.pop(0)
    return not members or members[0]['agent'] in submitters


def serve(store, train, agent='merge-train', poll=15, once=False, log=print):
    """The continuous scheduler: whenever next_train() holds, take the head's place in the queue, claim the slot, run a
    train, release. Runs on venus outside any lane's turn (coordinator, 2026-11-26). One instance at a time: every
    scheduler shares the agent name, so the slot's lease cannot keep two apart; an exclusive lock does."""
    import fcntl
    (store.root / 'train').mkdir(parents=True, exist_ok=True)
    guard = open(store.root / 'train' / 'scheduler.lock', 'a+')
    try:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log(f'{agent_utc()} another scheduler holds {guard.name}; exiting')
        return
    guard.seek(0); guard.truncate(); guard.write(f'{os.getpid()}\n'); guard.flush()
    while True:
        if next_train(store, train.submissions()):
            if train.verify_commands is None and train.verifiers and isinstance(train.verifiers[0], RemoteVerifier):
                # verifiers.json is re-read before every train: enabling or disabling a verifier needs no restart.
                train.verifiers = sorted(load_verifiers(store), key=lambda v: bool(getattr(v, 'budget', False)))
            store.queue(SLOT, 'front', agent)
            try:
                store.claim(SLOT, agent, 'other', None, 120)
            except SystemExit as exc:
                log(f'{agent_utc()} claim refused: {exc}')
                store.queue(SLOT, 'leave', agent)
            else:
                try:
                    result = train.run(agent)
                    log(f'{agent_utc()} train: {json.dumps(result)}')
                except Exception as exc:  # a broken run must not stop the scheduler or keep the slot
                    log(f'{agent_utc()} train error: {exc!r}')
                finally:
                    store.release(SLOT, agent, 'merge train')
                    train.verifications = 0
        if once:
            return
        time.sleep(poll)


def agent_utc():
    return agentctl.utc_now()


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
    s = sub.add_parser('serve'); s.add_argument('--agent', default='merge-train')
    s.add_argument('--poll', type=int, default=15); s.add_argument('--worktree', type=Path, default=DEFAULT_WORKTREE)
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
    elif a.command == 'serve':
        serve(store, train, a.agent, a.poll, log=lambda line: print(line, flush=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
