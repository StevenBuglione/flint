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
GENERATED_FILES = ('docs/spring/java-differences.md', 'docs/spring/api-mapping.md',
                   # tools/api_differences.py --write regenerates the JDK table too (api-coverage, 8cad51c23).
                   'docs/spring/jdk-coverage.md')
# Shrink-only ID lists and ratchets that every lane edits (a JDK lane removes the ids it confirms from
# api/jdk-unconfirmed.json). Adjacent removals conflict line by line, so the train merges them three-way as sets
# (merge_sets; coordinator, 2026-11-26).
SET_FILES = ('api/jdk-unconfirmed.json', 'api/kind-baseline.json', 'api/dependency-baseline.json',
             'api/jdk-leaf-types.json',
             # The upstream-tests ratchet: sorted per-module lists of deferred classes, shrink-only (sol-jackson,
             # 2026-11-26: two lanes removing adjacent rows conflicted).
             'policy/upstream-tests-baseline.json')
# Files the regeneration may also rewrite; staged with the pages so `rebase --continue` does not stop on them (sol-web).
# Both ratchets shrink on --write.
REGENERATED_ALSO = ('api/dependency-baseline.json', 'api/kind-baseline.json')
# Tables keyed by entry ID ('| S-32 | ...'). A union merge keeps both sides' versions of a row both sides edited
# (S-32 five times, coordinator 2026-11-26 15:00Z); the train merges such a row three-way by its ID instead.
ROW_FILES = ('docs/spring/performance-playbook.md',)
ROW_ID = re.compile(r'^\| ([RBSD]-[0-9A-Z-]+) \|', re.M)


class SetConflict(ValueError):
    """Both sides of a JSON set file changed one entry incompatibly."""


_ABSENT = object()


def merge_sets(base, ours, theirs, where='$'):
    """Three-way merge of a JSON value whose lists are sets and whose objects are keyed entries: an id or key survives
    unless either side removed it, and anything either side added is kept. A scalar changed on one side takes that
    side; changed differently on both sides, or changed on one side and removed on the other, raises SetConflict.
    Lists come back sorted and nested objects with sorted keys, so the result doesn't depend on which side was first."""
    if all(isinstance(v, dict) or v is _ABSENT for v in (base, ours, theirs)):
        b, o, t = (v if isinstance(v, dict) else {} for v in (base, ours, theirs))
        keys = [k for k in o if k in t or k not in b] + [k for k in t if k not in o and k not in b]
        merged = {}
        for k in keys:
            merged[k] = merge_sets(b.get(k, _ABSENT), o.get(k, _ABSENT), t.get(k, _ABSENT), f'{where}.{k}')
        for k in b:
            if (k in o) != (k in t):
                kept, side = (o, 'ours') if k in o else (t, 'theirs')
                if kept[k] != b[k]:
                    raise SetConflict(f'{where}.{k}: removed on one side, changed on the other ({side})')
        return merged if where == '$' else dict(sorted(merged.items()))
    if all(isinstance(v, list) or v is _ABSENT for v in (base, ours, theirs)):
        b, o, t = (set(map(_frozen, v)) if isinstance(v, list) else set() for v in (base, ours, theirs))
        return sorted(map(_thawed, (o & t) | (o - b) | (t - b)), key=lambda v: json.dumps(v, sort_keys=True))
    if ours == theirs:
        return ours
    if ours == base:
        return theirs
    if theirs == base:
        return ours
    raise SetConflict(f'{where}: changed differently on both sides')


def json_indent(text, default=1):
    """The indentation a JSON file is written with (its first indented line), so a merge does not reformat the file:
    policy/upstream-tests-baseline.json uses 2, the api/ sets 1."""
    for line in text.splitlines()[1:]:
        stripped = line.lstrip(' ')
        if stripped and len(stripped) < len(line):
            return len(line) - len(stripped)
    return default


def _frozen(value):
    return json.dumps(value, sort_keys=True) if isinstance(value, (dict, list)) else value


def _thawed(value):
    return json.loads(value) if isinstance(value, str) and value[:1] in '{[' else value


def id_rows(text):
    """{entry ID: [row lines]} of a table keyed by ID."""
    rows = {}
    for line in (text or '').splitlines():
        found = ROW_ID.match(line)
        if found:
            rows.setdefault(found.group(1), []).append(line)
    return rows


def merge_rows(current, base, ours, theirs):
    """(text, conflicts): `current` (a union merge) with one row per entry ID that the merge duplicated. An ID that
    was already duplicated on either side is left alone (an old collision, not this merge's doing). The row is merged
    three-way against `base` (the fork point): the side that changed it wins; both changing it differently is a
    conflict, returned by ID and left as it is."""
    now, b, o, t = id_rows(current), id_rows(base), id_rows(ours), id_rows(theirs)
    picks, conflicts = {}, []
    for entry, lines in now.items():
        if len(lines) < 2 or len(o.get(entry, [])) > 1 or len(t.get(entry, [])) > 1:
            continue
        old, mine, other = (b.get(entry) or [None])[0], (o.get(entry) or [None])[0], (t.get(entry) or [None])[0]
        if mine == other or other == old:
            picks[entry] = mine
        elif mine == old:
            picks[entry] = other
        else:
            conflicts.append(entry)
    if not picks:
        return current, conflicts
    out, seen = [], set()
    for line in current.splitlines(keepends=True):
        found = ROW_ID.match(line)
        entry = found.group(1) if found else None
        if entry in picks:
            if entry not in seen and picks[entry] is not None:
                out.append(picks[entry] + ('\n' if line.endswith('\n') else ''))
            seen.add(entry)
            continue
        out.append(line)
    return ''.join(out), conflicts
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
  [ -z "${LOAD_PID:-}" ] || kill "$LOAD_PID" 2>/dev/null
  # Only this run's servers: DMD fork servers whose environment names this run's FLINT_CACHE.
  for pid in $(pgrep -u "$USER" -f 'dmd' || true); do
    if tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -qx "FLINT_CACHE=$FLINT_CACHE"; then kill "$pid" 2>/dev/null; fi
  done
  rm -rf "$FLINT_CACHE" "$FLINT_CACHE.dod.json" "$FLINT_CACHE.api.json" "$FLINT_CACHE.budget.json" "$FLINT_CACHE.tight.json" "$FLINT_CACHE.median.json" "$FLINT_CACHE.load" "$FLINT_CACHE.noisy" "$FLINT_CACHE.notight.json" "$FLINT_CACHE.modules.log" "$WT/.flint/definition-of-done" "$WT/.flint/build" "$WT/artifacts"
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
# Load guard (coordinator, 2026-11-26 14:06Z): foreign CPU load inflates instruction counts (11:0xZ test on posidon:
# 13 busy CPUs added 650-1,800 instructions per request). Around each flint budget command, log loadavg and the run
# queue, and sample every 2 s the runnable threads of other sessions (this verifier's own builds share its session;
# kernel threads have none). Quiet: mean <= LOAD_MEAN and max <= LOAD_MAX. A run that was not quiet never takes the
# tight-spread skip (b): its borderline misses get the median re-measure.
LOAD_MEAN=0.5; LOAD_MAX=4; SID=$(ps -o sid= -p $$ | tr -d ' ')
load_now() { printf 'loadavg %s, procs_running %s' "$(cut -d' ' -f1-3 /proc/loadavg)" "$(awk '/^procs_running/ {print $2}' /proc/stat)"; }
load_start() {
  echo "== load before: $(load_now)"
  ( while :; do ps -eLo stat=,sid= | awk -v me="$SID" '$1 ~ /^R/ && $2 != me && $2 != 0 {n++} END {print n + 0}'; sleep 2; done ) > "$FLINT_CACHE.load" 2>/dev/null &
  LOAD_PID=$!
}
load_stop() {
  kill "$LOAD_PID" 2>/dev/null; wait "$LOAD_PID" 2>/dev/null
  local verdict
  verdict=$(awk -v mean="$LOAD_MEAN" -v max="$LOAD_MAX" '{s += $1; if ($1 > m) m = $1; n++} END {
    q = (n == 0 || (s / n <= mean && m <= max)) ? "quiet" : "NOT quiet";
    printf "foreign runnable threads mean %.2f, max %d over %d samples: %s", (n ? s / n : 0), m, n, q}' "$FLINT_CACHE.load")
  echo "== load after: $(load_now); $verdict (quiet: mean <= $LOAD_MEAN, max <= $LOAD_MAX)"
  case "$verdict" in *"NOT quiet") : > "$FLINT_CACHE.noisy" ;; esac
}
# A full native build only when what defines the libraries changed since the last one here; otherwise just the Flint
# C shims over the installed libraries, plus the dub blocks (a full build recompiles OpenSSL every time).
INPUTS=$(git ls-tree -r HEAD -- policy/native-lock.json policy/native-c.toml tools/native_build.py native/conan-index | sha256sum | cut -c1-64)
SHIMS=""; [ -f .native/train-native-inputs ] && [ "$(cat .native/train-native-inputs)" = "$INPUTS" ] && SHIMS="--shims-only"
[ "@FULL_NATIVE@" = yes ] || SHIMS="--shims-only"
echo "== native blocks ${SHIMS:-full build}"
$H python3 tools/native_build.py --profile ci --target linux-x86_64-glibc --phase build $SHIMS --emit-dub || exit 4
echo "$INPUTS" > .native/train-native-inputs
echo "== flint"; $H python3 tools/install_toolchains.py --compiler flint || exit 4
if [ "@MODE@" = budget ]; then
  # A budget-only step (bisecting a failure that was flint budget's alone): acceptance is already proven.
  echo "== budget only: @BUDGET_APPS@"
  set -- ; for app in @BUDGET_APPS@; do set -- "$@" --app "$app"; done
  load_start; $H flint budget "$@" --report "$FLINT_CACHE.budget.json" > "$FLINT_CACHE.dod.json" 2>&1; rc=$?; load_stop
  cat "$FLINT_CACHE.budget.json" >> "$FLINT_CACHE.dod.json" 2>/dev/null
  cat "$FLINT_CACHE.dod.json"
  [ $rc -eq 2 ] && { echo "flint budget could not measure (exit 2): the verifier, not the candidate"; exit 3; }
else
  echo "== api gate"; $H python3 tools/gates.py --gate api > "$FLINT_CACHE.api.json" 2>&1 || { tail -40 "$FLINT_CACHE.api.json"; rm -f "$FLINT_CACHE.api.json"; exit 1; }
  rm -f "$FLINT_CACHE.api.json"
  echo "== apps"; load_start; python3 tools/gates.py --module framework/web --definition-of-done --step apps --apps @APPS@ @DOD_FLAGS@ --json > "$FLINT_CACHE.dod.json"; rc=$?; load_stop
  cat "$FLINT_CACHE.dod.json"
  # Module caps (coordinator, 2026-11-26 15:14Z): the size and template probes of every framework module whose closure
  # the candidate touches; a breach the candidate causes (new, or worse than main's) is red, naming the module.
  if [ $rc -eq 0 ] && [ -n "@BASE@" ] && [ -f tools/module_probes.py ]; then
    echo "== module probes against main @BASE@"
    LDC_BIN=$(ls -d "$WT"/.tools/ldc2-*-linux-x86_64/bin 2>/dev/null | head -1)
    PATH="${LDC_BIN:+$LDC_BIN:}$PATH" $H python3 tools/module_probes.py --base "@BASE@" > "$FLINT_CACHE.modules.log" 2>&1; mrc=$?
    cat "$FLINT_CACHE.modules.log"
    # A probe that cannot run judges nothing and blocks nothing (17:15Z and 17:43Z: probe tooling, not candidates,
    # held two whole trains); the log says so, and the lanes' own definition of done still runs the probes.
    [ $mrc -eq 2 ] && echo "module probes: could not run; not judged (the verifier's tooling, not the candidate)"
    [ $mrc -eq 1 ] && exit 1
  fi
fi
if [ $rc -ne 0 ]; then
  # Decision 6478897a: a borderline flint budget miss (every failure an instruction miss under twice its tolerance)
  # is re-measured and the median of 5 runs judged; a miss on an endpoint whose measured spread is under 0.2% is real
  # at once (coordinator, 2026-11-26); anything else stays red.
  TIGHTFILE="$FLINT_CACHE.tight.json"
  if [ -e "$FLINT_CACHE.noisy" ]; then  # the load guard: a run that was not quiet takes no tight-spread skip
    TIGHTFILE="$FLINT_CACHE.notight.json"; echo '{}' > "$TIGHTFILE"
    echo "== the run was not quiet: no tight-spread skip; borderline misses are re-measured"
  fi
  cat > "$FLINT_CACHE.tight.json" <<'TIGHT'
@TIGHT@
TIGHT
  apps=$(python3 - "$FLINT_CACHE.dod.json" "$TIGHTFILE" <<'PY'
import json, os, re, sys
text, tight = open(sys.argv[1]).read(), json.load(open(sys.argv[2]))
final = len(sys.argv) > 3 and sys.argv[3] == 'final'
# Main's own open misses (benchmarks/spring/train-budget-relative.json, a temporary coordinator decision): such an
# endpoint fails only if the candidate regresses past main's measured value by more than the tolerance.
RELATIVE = 'benchmarks/spring/train-budget-relative.json'
relative = json.load(open(RELATIVE)).get('endpoints', {}) if os.path.exists(RELATIVE) else {}
objects, at = [], 0
while text.find('{', at) >= 0:
    at = text.find('{', at)
    try:
        found, end = json.JSONDecoder().raw_decode(text[at:])
        objects.append(found)
        at += max(end, 1)
    except ValueError:
        at += 1
MISS = re.compile(r"([\w.-]+): '([^']+)': instructions [0-9,]+ -> [0-9,]+ \(\+([0-9.]+)%, tolerance \+([0-9.]+)%\)")
dod = next((o for o in objects if isinstance(o, dict) and 'steps' in o), None)
report = next((o for o in objects if isinstance(o, dict) and str(o.get('schema', '')).startswith('flint.budget/')), None)
if dod is not None:
    step = next((s for s in dod['steps'] if s['step'] == 'apps'), None)
    if step is None:
        sys.exit(1)
    bad = [k for k, v in step['details'].items() if k != 'apps' and not str(v).startswith(('pass', 'skip'))]
    if not bad or any(not k.endswith(' flint budget') for k in bad):
        sys.exit(1)
    problems = [m.strip()[len('budget:'):].strip() for m in step['messages'] if m.strip().startswith('budget:')]
elif report is not None:
    problems = list(report.get('problems', []))
else:
    sys.exit(1)
FULL = re.compile(r"([\w.-]+): '([^']+)': instructions ([0-9,]+) -> ([0-9,]+) \(\+([0-9.]+)%, tolerance \+([0-9.]+)%\)")
kept = []
for problem in problems:
    found = FULL.search(problem)
    if found and found.group(2) in relative.get(found.group(1), {}):
        entry = relative[found.group(1)][found.group(2)]
        if int(found.group(4).replace(',', '')) <= entry['main'] * (1 + entry['tolerance']):
            continue
    kept.append(problem)
if problems and not kept:
    print('RELATIVE-GREEN')
    sys.exit(0)
problems = kept
if not problems or final:
    sys.exit(1)
apps = set()
for problem in problems:
    found = MISS.search(problem)
    if not found or float(found.group(3)) >= 2 * float(found.group(4)):
        sys.exit(1)
    if found.group(2) in tight.get(found.group(1), []):
        sys.exit(1)
    apps.add(found.group(1))
print(' '.join(sorted(apps)))
PY
) || exit $rc
  if [ "$apps" = RELATIVE-GREEN ]; then echo "only main's open budget misses, within tolerance of main"; exit 0; fi
  echo "== borderline flint budget miss: re-measuring $apps (median of 5, decision 6478897a)"
  set -- ; for app in $apps; do set -- "$@" --app "$app"; done
  load_start; $H flint budget "$@" --repeat 5 --report "$FLINT_CACHE.median.json"; rc=$?; load_stop
  [ $rc -eq 0 ] && { echo "the median of 5 is within budget"; exit 0; }
  cat "$FLINT_CACHE.median.json" 2>/dev/null
  verdict=$(python3 - "$FLINT_CACHE.median.json" "$TIGHTFILE" final <<'PY'
@CLASSIFIER@
PY
) && [ "$verdict" = RELATIVE-GREEN ] && { echo "the median of 5 misses only main's open endpoints, within tolerance of main"; exit 0; }
  exit 1
fi
"""
POSIDON_SCRIPT = VERIFY_SCRIPT  # the name earlier tests and notes use
UNAVAILABLE = (3, 5, 255)  # git setup, a receipt mismatch, ssh itself


MISS_LINE = re.compile(r"([\w.-]+): '([^']+)': instructions ([0-9,]+) -> ([0-9,]+) \(\+([0-9.]+)%, tolerance \+([0-9.]+)%\)")


def budget_misses(log):
    """[(app, endpoint, before, after, percent, tolerance)] for every flint budget instruction miss in a log."""
    seen, found = set(), []
    for match in MISS_LINE.finditer(log or ''):
        key = (match.group(1), match.group(2))
        if key not in seen:
            seen.add(key)
            found.append((match.group(1), match.group(2), match.group(3), match.group(4), float(match.group(5)),
                          float(match.group(6))))
    return found


def budget_only_apps(log):
    """The apps whose flint budget alone failed a verification, or None when anything else failed too (or the log
    shows no flint budget failure): then a bisect step needs the full verification."""
    if not log:
        return None
    decoder, at, objects = json.JSONDecoder(), 0, []
    while log.find('{', at) >= 0:
        at = log.find('{', at)
        try:
            found, end = decoder.raw_decode(log[at:])
            objects.append(found)
            at += max(end, 1)
        except ValueError:
            at += 1
    for found in objects:
        if isinstance(found, dict) and 'steps' in found:
            step = next((s for s in found['steps'] if s.get('step') == 'apps'), None)
            if step is None:
                return None
            bad = [k for k, v in step['details'].items() if k != 'apps' and not str(v).startswith(('pass', 'skip'))]
            if not bad or any(not k.endswith(' flint budget') for k in bad):
                return None
            return sorted(k[:-len(' flint budget')] for k in bad)
        if isinstance(found, dict) and str(found.get('schema', '')).startswith('flint.budget/'):
            apps = sorted({m[0] for m in budget_misses('\n'.join(found.get('problems', [])))})
            if not apps or len(apps) != len({p.split(':', 1)[0] for p in found.get('problems', [])}):
                return None
            return apps
    return None


def tight_endpoints(store):
    """{app: [endpoints]} whose measured spread is under 0.2% (coordination/train/budget-spread.json, {app:
    {endpoint: spread fraction}}): a borderline miss there is real without a median re-measure."""
    path = store.root / 'train' / 'budget-spread.json'
    spreads = json.loads(path.read_text()).get('spread', {}) if path.is_file() else {}
    return {app: sorted(e for e, value in endpoints.items() if value < 0.002) for app, endpoints in spreads.items()}


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

    supports_modes = True

    def script(self, commit, ref, stamp, mode='full', apps=None, tight=None, base=None):
        e = self.entry
        receipts = ''.join(f'{digest}  {path}\n' for path, digest in sorted(e.get('receipts', {}).items()))
        values = {'@PRELUDE@': e.get('prelude', ''), '@BARE@': e['bare'], '@REPO@': e.get('repo', e['bare']),
                  '@WORKTREE@': e['worktree'], '@TOOLS@': e['tools'], '@PEERS@': e['peers'],
                  '@NATIVE_INSTALL@': e['native_install'], '@NATIVE_FIX@': e.get('native_fix', 'true'),
                  '@RELOCATE_FROM@': e.get('native_relocate_from', ''),
                  '@FULL_NATIVE@': 'yes' if e.get('full_native', True) else 'no',
                  '@CACHE_ROOT@': e.get('cache_root', '$HOME'), '@RECEIPTS@': receipts,
                  '@DOD_FLAGS@': '' if self.budget else '--no-flint-budget', '@APPS@': ','.join(APPS),
                  '@MODE@': mode, '@BUDGET_APPS@': ' '.join(apps or APPS), '@TIGHT@': json.dumps(tight or {}),
                  '@COMMIT@': commit, '@REF@': ref, '@STAMP@': stamp, '@BASE@': base or ''}
        text = VERIFY_SCRIPT
        start = text.index("<<'PY'\n", text.index('TIGHT\n  apps=')) + len("<<'PY'\n")
        text = text.replace('@CLASSIFIER@', text[start:text.index('\nPY\n', start)])
        for token, value in values.items():
            text = text.replace(token, value)
        return text

    takes_base = True  # the module probes judge a candidate against the train's base

    def __call__(self, commit, repo, mode='full', apps=None, tight=None, base=None):
        stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + commit[:8]
        ref = f'train-{stamp}'
        env = dict(os.environ, GIT_SSH_COMMAND=shlex.join(self.ssh))
        pushed = subprocess.run(['git', 'push', '-q', self.url, f'{commit}:refs/heads/{ref}'],
                                cwd=repo, env=env, capture_output=True, text=True)
        if pushed.returncode != 0:
            return None, f'{self.name}: pushing the candidate failed:\n{pushed.stderr}'
        done = subprocess.run([*self.ssh, self.host, 'bash', '-s'], input=self.script(commit, ref, stamp, mode, apps, tight, base),
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
        self.base = None  # main at the train's start: the module probes judge candidates against it
        self.restacked = False  # one restack per train after a named culprit (coordinator, 19:27Z)
        import threading
        self.git_lock = threading.RLock()  # the worktree's checkouts: an early prefix push may run beside a bisect
        self.early = None  # (submissions, pushed) when a green prefix landed before the bisect finished
        self.early_future = None
        self.max_train = MAX_TRAIN

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
        with self.git_lock:
            return self._build(batch, base)

    def _build(self, batch, base):
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
                paths = git(['diff', '--name-only', '--diff-filter=U'], self.worktree, check=False).stdout.split()
                git(['rebase', '--abort'], self.worktree, check=False)
                git(['checkout', '-q', '--detach', tip], self.worktree)
                generated = [path for path in paths if path in GENERATED_FILES]
                failed.append((submission, 'rebase onto the train failed (conflict) in: ' + (', '.join(paths) or '?')
                               + (f'\n(generated, regenerated by the train: {", ".join(generated)}; the others are '
                                  'real conflicts to rebase)' if generated else '')
                               + f'\n{done.stdout}{done.stderr}'))
                continue
            conflicts = self.merge_id_rows(tip, fork, submission)
            if conflicts:
                git(['checkout', '-q', '--detach', tip], self.worktree)
                failed.append((submission, 'rebase onto the train failed (conflict): both sides changed these '
                               'entries differently: ' + ', '.join(conflicts)))
                continue
            tip = git(['rev-parse', 'HEAD'], self.worktree).stdout.strip()
            applied.append((submission, tip))
        git(['checkout', '-q', '--detach', tip], self.worktree)
        return applied, failed

    def merge_id_rows(self, tip, fork, submission):
        """After `submission` rebased onto `tip`: give each ID-keyed table one row per entry the union merge
        duplicated (merge_rows), committed on top as the train. Returns the IDs both sides changed differently."""
        changed, conflicts = [], []
        for path in ROW_FILES:
            target = self.worktree / path
            if not target.is_file():
                continue
            current = target.read_text()
            merged, clashes = merge_rows(current, self.show(fork, path), self.show(tip, path),
                                         self.show(submission['commit'], path))
            conflicts += [f'{path} {entry}' for entry in clashes]
            # Every entry ID once: a duplicate the train did not already have is the submission's (a reused ID).
            before = {entry for entry, lines in id_rows(self.show(tip, path)).items() if len(lines) > 1}
            conflicts += [f'{path} {entry} (duplicate entry ID; take a fresh one: agentctl.py id next)'
                          for entry, lines in id_rows(merged).items()
                          if len(lines) > 1 and entry not in before and entry not in clashes]
            if merged != current:
                target.write_text(merged)
                changed.append(path)
        if conflicts:
            git(['checkout', '-q', '--', *ROW_FILES], self.worktree, check=False)
            return conflicts
        if changed:
            git(['add', '--', *changed], self.worktree)
            git(['commit', '-q', '-m',
                 f"merge train: one row per entry ID after rebasing {submission['role']}\n\n"
                 'A union merge kept both versions of an entry both sides edited; the train kept the side that changed '
                 'it (merge_train.merge_rows).'], self.worktree)
            self.store.event('train-rows-merged', role=submission['role'], files=changed)
        return []

    def verify(self, commit, verifier=None, mode='full', apps=None):
        """(ok, log): True green, False red, None the verifier could not run. `mode` 'budget' runs flint budget alone
        for `apps` (bisecting a budget-only failure; acceptance is already proven)."""
        self.verifications += 1
        if self.verifiers:
            chosen = verifier or self.verifiers[-1]
            if getattr(chosen, 'supports_modes', False):
                extra = {'base': self.base} if getattr(chosen, 'takes_base', False) else {}
                return chosen(commit, self.worktree, mode=mode, apps=apps, tight=tight_endpoints(self.store), **extra)
            return chosen(commit, self.worktree)
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
            if not conflicted or any(path not in GENERATED_FILES + SET_FILES for path in conflicted):
                return done
            for path in (p for p in conflicted if p in SET_FILES):
                if not self.merge_set_file(path):
                    return done  # both sides changed one entry incompatibly: a real conflict
            regenerated = subprocess.run(REGENERATE, cwd=self.worktree, capture_output=True, text=True)
            if regenerated.returncode != 0:
                return regenerated
            if any('<<<<<<<' in (self.worktree / path).read_text() for path in GENERATED_FILES
                   if (self.worktree / path).is_file()):
                return done  # a conflict in a hand-written part of the page: a real one
            # Only paths that exist: one missing pathspec makes `git add` stage nothing.
            staged = [path for path in GENERATED_FILES + REGENERATED_ALSO + SET_FILES if (self.worktree / path).is_file()]
            git(['add', '--', *staged], self.worktree, check=False)
            self.store.event('train-regenerated', files=conflicted)
            done = git(['-c', 'core.editor=true', '-c', f'core.attributesFile={self.attributes()}', 'rebase',
                        '--continue'], self.worktree, check=False)
            if done.returncode == 0:
                return done
        return done

    def merge_set_file(self, path):
        """Resolve a conflicted SET_FILES path from its index stages (1 base, 2 the train, 3 the submission) with
        merge_sets, write it back and stage it. False on a real conflict."""
        stages, texts = [], []
        for stage in (1, 2, 3):
            shown = git(['show', f':{stage}:{path}'], self.worktree, check=False)
            texts.append(shown.stdout if shown.returncode == 0 else '')
            stages.append(json.loads(shown.stdout) if shown.returncode == 0 and shown.stdout.strip() else _ABSENT)
        try:
            merged = merge_sets(*stages)
        except SetConflict as conflict:
            self.store.event('train-set-conflict', file=path, reason=str(conflict))
            return False
        (self.worktree / path).write_text(json.dumps(merged, indent=json_indent(texts[1] or texts[2])) + '\n')
        git(['add', '--', path], self.worktree, check=False)
        self.store.event('train-set-merged', file=path)
        return True

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
        base = self.base = self._fetch()
        self.restacked, self.max_train = False, max_train
        self.early, self.early_future = None, None
        budget_verifier = next((v for v in reversed(self.verifiers) if getattr(v, 'budget', False)), None)
        others = [v for v in self.verifiers if not getattr(v, 'budget', False)]
        if budget_verifier is not None and others and getattr(budget_verifier, 'supports_modes', False):
            outcome = self._screened(batch, base, max_train, budget_verifier, others)
        else:
            outcome = self._stacked(batch, base, max_train)
        if 'main_red' in outcome:  # settle only the rebase conflicts; everything else waits for main
            settled = self.settle(batch, [], outcome.get('failed', []), None)
            settled.update({k: outcome[k] for k in ('main_red', 'main_red_log') if k in outcome})
            return settled
        batch, applied, failed, landed, verified_tip = (outcome[k] for k in ('batch', 'applied', 'failed', 'landed', 'tip'))
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
        result = self.settle(batch, landed, failed, pushed)
        if outcome.get('landed_early'):
            result['landed_early'], result['pushed_early'] = outcome['landed_early'], self.early[1]
        return result

    def _stacked(self, batch, base, max_train):
        """Speculative stacking: candidate k is main plus groups 1..k (up to max_train submissions each), one per
        verifier, all verified at once; they land in strict order."""
        applied, failed = self.build(batch, base)
        if not applied:
            return {'batch': batch, 'applied': applied, 'failed': failed, 'landed': [], 'tip': None}
        lanes = max(1, len(self.verifiers))
        ends = [min(len(applied), (k + 1) * max_train) for k in range(lanes) if k * max_train < len(applied)]
        results = self.verify_all([applied[end - 1][1] for end in ends])
        first = next((k for k, (ok, _) in enumerate(results) if ok is not True), None)
        if first is not None and first > 0 and results[first][0] is False and self.budget_lanes(len(ends))[first] \
                and not all(self.budget_lanes(len(ends))[:first]):
            # Red on the budget verifier, but the green candidates before it were checked without flint budget:
            # that green is no budget baseline. Budget-check the green prefix once; if it holds, only the red group
            # is bisected, otherwise the culprit is in the prefix, which is bisected instead.
            prefix_ok, prefix_log = self.verify(applied[ends[first - 1] - 1][1], mode='budget', apps=list(APPS))
            self.store.event('train-budget-prefix', candidates=first, prefix_green=prefix_ok)
            if not prefix_ok:
                ends, results, first = [ends[first - 1]], [(prefix_ok, prefix_log)], 0
        if first is None:
            return {'batch': batch, 'applied': applied, 'failed': failed, 'landed': applied, 'tip': applied[-1][1]}
        good, bad = (ends[first - 1] if first else 0), ends[first]
        return self._resolve(batch, applied, failed, good, bad, results[first], base)

    def _resolve(self, batch, applied, failed, good, bad, verdict, base, verifier=None):
        """Bisect applied[good:bad] (applied[:good] is green, the candidate ending at bad red) and settle what lands.
        `verifier` bisects (default: the budget verifier, last); an acceptance failure is bisected on its own verifier."""
        ok, bad_log = verdict
        if ok is None:  # the verifier failed: land what is green before it, blame nobody
            self.store.event('train-verifier-failed', log=bad_log[-2000:])
        else:
            only = budget_only_apps(bad_log)  # a budget-only failure is bisected with flint budget alone
            step = dict(mode='budget', apps=only) if only else {}
            middle_log = ''
            while bad - good > 1:
                middle = (good + bad) // 2
                ok, middle_log = self.verify(applied[middle - 1][1], verifier, **step)
                if ok is None:
                    bad = None
                    break
                if ok:
                    good = middle
                else:
                    bad, bad_log = middle, middle_log
            if bad is None:
                self.store.event('train-verifier-failed', log=middle_log[-2000:])
            elif bad == 1 and (main := self.verify(base, verifier, **step))[0] is not True:
                # Main itself is red: blame nobody; every submission waits for main to be fixed.
                return self._main_red(base, main[1], failed)
            else:
                failed.append((applied[bad - 1][0], 'the apps verification failed with this submission on the '
                               'train:\n' + bad_log))
                behind = applied[bad:]
                if behind and not self.restacked:
                    # Coordinator, 19:27Z: once a culprit is named, the submissions behind it are restacked on the
                    # green prefix and verified once more in this train (a bisect if that fails, with no second
                    # restack), so no lane loses its turn to one repeat failure.
                    self.restacked = True
                    if self.early_future is not None:
                        self.early_future.result()  # never build while an early push may still be rebuilding
                    if self.early:
                        landed_early = {(s['role'], s['commit']) for s in self.early[0]}
                        keep = [s for s, _ in applied[:good] + behind if (s['role'], s['commit']) not in landed_early]
                        base = self.early[1]
                    else:
                        keep = [s for s, _ in applied[:good] + behind]
                    self.store.event('train-restack', culprit=applied[bad - 1][0]['role'], roles=[s['role'] for s in keep])
                    outcome = self._stacked(keep, base, self.max_train)
                    outcome['failed'] = failed + outcome.get('failed', [])
                    outcome['batch'] = batch
                    outcome['restacked'] = True  # verified by _stacked's lanes, its deepest candidate with flint budget
                    return outcome
        return {'batch': batch, 'applied': applied, 'failed': failed, 'landed': applied[:good],
                'tip': applied[good - 1][1] if good else None}

    def singles(self, batch, base):
        """[(submission, tip)] for each submission whose own diff touches the apps' closure, rebased alone onto base
        (a new opt-in package cannot change the apps' instruction counts, so it is not screened)."""
        closure = self.closure if self.closure is not None else closure_paths(self.worktree)
        names = self.closure_names()
        found = []
        for submission in batch:
            fork = git(['merge-base', base, submission['commit']], self.worktree).stdout.strip()
            files = self.changed(fork, submission['commit'])
            show = (lambda path, old=fork, new=submission['commit']: (self.show(old, path), self.show(new, path)))
            if not build_relevant(files, closure, names, show):
                continue
            applied, _ = self.build([submission], base)
            if applied:
                found.append(applied[0])
        return found

    def _screened(self, batch, base, max_train, budget_verifier, others):
        """Stack first (coordinator, 2026-11-26 12:3xZ, replacing screen-first): while the acceptance verifiers check
        the stacked candidates, posidon, the only budget runner, budget-checks the whole stack once. When both are
        green everything lands on one posidon run. Only a red stack budget screens each closure-touching submission
        alone on main (_budget_red), so the lane that regresses alone is returned at once with its misses."""
        from concurrent.futures import ThreadPoolExecutor
        batch = batch[:max_train * len(others)]
        applied, failed = self.build(batch, base)
        if not applied:
            return {'batch': batch, 'applied': applied, 'failed': failed, 'landed': [], 'tip': None}
        ends = [min(len(applied), (k + 1) * max_train) for k in range(len(others)) if k * max_train < len(applied)]
        with ThreadPoolExecutor(1 + len(ends)) as pool:
            stack = pool.submit(self.verify, applied[-1][1], budget_verifier, mode='budget', apps=list(APPS))
            accepted = [pool.submit(self.verify, applied[end - 1][1], verifier) for end, verifier in zip(ends, others)]
            verdict, accepted = stack.result(), [f.result() for f in accepted]
        self.store.event('train-stack-budget', candidates=len(applied), ok=verdict[0])
        first = next((k for k, (ok, _) in enumerate(accepted) if ok is not True), None)
        if first is not None:  # an acceptance failure: bisect inside its group on the verifier that failed it
            good, bad = (ends[first - 1] if first else 0), ends[first]
            early_pool = None
            if good:  # coordinator, 2026-11-27 02:26Z: land the green prefix now, beside the bisect
                early_pool = ThreadPoolExecutor(1)
                self.early_future = early_pool.submit(self._land_early, applied[:good], base, budget_verifier)
            try:
                outcome = self._resolve(batch, applied, failed, good, bad, accepted[first], base, others[first])
            finally:
                if early_pool is not None:
                    self.early_future.result()
                    early_pool.shutdown()
            if self.early:  # those lanes are on main and settled already; the rest lands on top of them
                landed_early = {(s['role'], s['commit']) for s in self.early[0]}
                outcome['landed'] = [x for x in outcome['landed'] if (x[0]['role'], x[0]['commit']) not in landed_early]
                outcome['landed_early'] = sorted(s['role'] for s in self.early[0])
                if not outcome['landed']:
                    return outcome
            landed = outcome['landed']
            if verdict[0] is True or not landed or 'main_red' in outcome or outcome.get('restacked'):
                return outcome
            # The whole stack's budget was not green, so the acceptance-green prefix needs its own budget verdict.
            verdict = self.verify(landed[-1][1], budget_verifier, mode='budget', apps=list(APPS))
            self.store.event('train-budget-prefix', candidates=len(landed), prefix_green=verdict[0])
            if verdict[0] is True:
                return outcome
            return self._budget_red(batch, landed, outcome['failed'], base, max_train, budget_verifier, verdict)
        if verdict[0] is True:
            return {'batch': batch, 'applied': applied, 'failed': failed, 'landed': applied, 'tip': applied[-1][1]}
        return self._budget_red(batch, applied, failed, base, max_train, budget_verifier, verdict)

    def _land_early(self, prefix, base, budget_verifier):
        """Push an acceptance-green prefix before the bisect behind it finishes (coordinator, 2026-11-27 02:26Z). The
        prefix's exact tree (main plus those lanes) was acceptance-verified; the whole stack's green budget cannot speak
        for it (a later lane may have lowered the counts), so posidon budget-checks this exact tree first. push()
        re-verifies after a rebase if main moved under build-relevant paths. Settled at once, mail included."""
        ok, _ = self.verify(prefix[-1][1], budget_verifier, mode='budget', apps=list(APPS))
        self.store.event('train-early-prefix', candidates=len(prefix), budget=ok)
        if ok is not True:
            return None
        pushed = self.push([s for s, _ in prefix], base, prefix[-1][1], 3)
        if pushed is None:
            return None
        self.settle([s for s, _ in prefix], prefix, [], pushed)
        self.early = ([s for s, _ in prefix], pushed)
        self.store.event('train-early-landed', roles=[s['role'] for s, _ in prefix], pushed=pushed)
        return pushed

    def _main_red(self, base, log, failed):
        """Main itself fails verification: blame nobody for it. The log is kept (coordination/train/main-red-*.log), and
        only the rebase conflicts found on the way, which are real whatever main's state, go back to their lanes."""
        self.log_dir.mkdir(parents=True, exist_ok=True)
        path = self.log_dir / f"main-red-{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}-{base[:8]}.log"
        path.write_text(log)
        self.store.event('train-main-red', base=base, log=str(path), misses=[f'{a}: {e}' for a, e, *_ in budget_misses(log)])
        conflicts = [(s, why) for s, why in failed if why.startswith('rebase onto the train failed')]
        if self.mail:
            misses = '; '.join(f"{a} '{e}' {b} -> {x} (+{pct:.2f}%)" for a, e, b, x, pct, _ in budget_misses(log)[:8])
            self._send('coordinator', f'merge train: main {base[:12]} itself fails verification, so nothing lands until '
                                      f'it is fixed (a fix at the queue head still can).'
                                      + (f' flint budget misses: {misses}.' if misses else '') + f' Log: {path}')
        return {'landed': [], 'failed': conflicts, 'pushed': None, 'logs': {}, 'main_red': base, 'main_red_log': str(path),
                'pending': [s['role'] for s in self.ordered()], 'verifications': self.verifications}

    def _budget_red(self, batch, applied, failed, base, max_train, budget_verifier, verdict):
        """The stack `applied` (acceptance-green) failed flint budget: bisect it with budget-only steps for the apps that
        missed, on the budget verifier (log2 of the stack: 3 steps for 8). The first submission whose prefix misses is
        returned with its misses, the green prefix before it lands, and the rest wait for the next train. If the
        bisect starts only after main itself passes flint budget on the budget verifier.
        Coordinator, 2026-11-26 21:3xZ: screening every closure-touching submission alone, one after another on
        posidon at about 30 minutes each, held a red train for up to four hours. A verifier that could not run blames
        nobody and lands nothing."""
        if verdict[0] is None:
            return self._resolve(batch, applied, failed, 0, len(applied), verdict, base)
        # Main first (coordinator, 21:27Z): a budget bisect against an unverified base misled us before (gs-rest read
        # +0.43% with no code change). One posidon run; a red main blames nobody.
        main_ok, main_log = self.verify(base, budget_verifier, mode='budget', apps=list(APPS))
        if main_ok is None:
            return self._resolve(batch, applied, failed, 0, len(applied), (None, main_log), base)
        if main_ok is False:
            return self._main_red(base, main_log, failed)
        return self._resolve(batch, applied, failed, 0, len(applied), verdict, base)

    def push(self, submissions, base, tip, attempts):
        with self.git_lock:
            return self._push(submissions, base, tip, attempts)

    def _push(self, submissions, base, tip, attempts):
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
            self.base = new_base
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
                misses = budget_misses(Path(path).read_text())
                if misses:
                    later += ' flint budget misses: ' + '; '.join(
                        f"{app} '{endpoint}' {before} -> {after} (+{pct:.2f}%, tolerance {tol:.2f}%)"
                        for app, endpoint, before, after, pct, tol in misses[:12]) + '.'
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
    if queue.get('paused'):  # a deliberate hold: no train starts until the queue is resumed
        return False
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
        guard.close()
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
            guard.close()
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
