# Slice 0 handoff for m7

Branch `gengc-astra`, base `d474219607df`, contract `gengc-final-plan.md` (2026-11-25),
`platform.lock` SHA-256 `5e96b2b0ca759e93ae6c6107a5c30d77bae7cabbbc406e1dbfad2e14e95a143b`.
The changes are in the working tree. The go/no-go decision belongs to m7 after the posidon runs.

## Files and interpretation

- `packages/arena/source/flint/arena/sys/gc/collector.d` times suspend, stopped mark, cache invalidation plus resume, sweep and the collection's entire interval under the GC lock. Lock time includes preparation, finalizers, post-sweep work and threshold updates. The normal allocator and full marker still use the existing code. `flint-predict` repeats the serial root scan, scans live scannable slots in address order with adjacent small slots coalesced, takes a batched pagemap census, then clears for the next interval. Its epochs run from just before resume to the next stopped mark. A short pagemap read discards that interval. The first clear seeds the census. The child of an application fork reopens its own descriptors and seeds a fresh interval.
- `packages/arena/source/flint/arena/sys/gc/profile.d` defines cumulative scalar fields, re-exported by `packages/arena/source/flint/arena/gc.d` alongside `pauseProfile()`. Times are monotonic nanoseconds. Each large block counts once at its full size in `dirtyBytes` when any page is dirty. `dirtyScanBytes` counts only its dirty pages. Small objects contribute only their block size. The scannable denominators span precisely the same successful intervals. A zero interval count means no usable census. The synchronous mark count is the denominator for the non-fork arms here.
- `packages/arena/tests/gc_selected.d` tests phase accounting, isolation of diagnostics by factory, and two dirty pages in a large rooted block across a pagemap batch boundary alongside a larger pointer-free allocation.
- `packages/arena/tests/softdirty_probe.d` is both an arena unittest and a standalone Linux executable. It verifies anonymous VMA merging on an unfaulted page, kernel writes to a resident page through a pipe, and agreement of pread with a multi-call ioctl walk where supported. The full run measures 2 MiB, 1,500 pages, 10 MiB and 20 MiB, first with the ordinary VMA layout and then with 2,200 extra alternating-protection pages. Every eighth page is dirty. JSON reports actual page size and VMA count, raw pread, pread plus bit enumeration, ioctl enumeration and one clear. Unsupported ioctl has an explicit status. Probe code uses the Linux UAPI directly. The collector reuses Flint's existing batched reader.
- `docs/spring/phase1/gc.md` gives the selection and probe commands.

**Implementation choices.** The existing cache flag has no druntime option. A startup-only `flint-no-cache` factory provides the parity arm in the same executable, and the predictor uses that allocation path to match the planned minors. The predictor always performs a synchronous full mark in the measuring process. Slice 0 introduces no minor collector, verifier mode or new stack scanner. The repeated scans use the existing ASan-exempt marker. The handoff note is the additional doc path explicitly requested in the deliverable.

## Local verification

Every command uses the pinned compilers and the venus lock. This sandbox's PID namespace hides the host lock owner's PID, so its local queue script would mistake the external lock for a stale one. The byte-identical queue script in the lock-owning checkout treats that lock as held whenever the file exists. All commands run from the assigned worktree.

```bash
export FLINT_MEASURE_LOCK=/home/olfa/flint-work/flint/.claude/worktrees/jolly-mendeleev-ea37ba/.flint/measure/MEASURING
export PATH=$PWD/.tools/ldc2-1.43.0-linux-x86_64/bin:$PWD/.tools/dmd2/linux/bin64:$PATH
export FLINT_DMD_SERVER=0
hold() { python3 "${FLINT_MEASURE_LOCK%/.flint/measure/MEASURING}/tools/measure_queue.py" hold -- "$@"; }
hold dub test :arena --compiler=ldc2
hold dub test :arena --compiler=dmd
hold dub test :arena --compiler=ldc2 -- '--DRT-gcopt=gc:flint-predict profile:1'
hold dub test :arena --compiler=dmd -- '--DRT-gcopt=gc:flint-predict profile:1'
hold python3 tools/gates.py --package arena --gate structural
hold ldc2 -O3 -preview=dip1000 -d-version=FlintSoftDirtyProbe packages/arena/tests/softdirty_probe.d -of=/tmp/flint-softdirty-probe
hold /tmp/flint-softdirty-probe --self-test
```

| Held check | Result on venus |
| --- | --- |
| LDC 1.43.0, default Flint and predictor | Exit 0 each, 17 modules passed each. Predictor report contained 962 predictions and 961 valid census intervals. |
| DMD 2.114.0, default Flint and predictor | Exit 0 each, 17 modules passed each. Predictor report contained 96 predictions and 95 valid census intervals. |
| Arena structural gate | Exit 1 in the three required DMD compile-server consistency fixtures. The fork reported `client-local no-server`. A held local AF_UNIX bind in a fresh directory under `/tmp` failed with `EPERM`. The arena structural checks passed independently (exit 0, 1 package, 37 graph nodes, 27 framework modules). |
| Standalone LDC probe build and self-test | Exit 0 each, kernel `7.0.0-31-generic`, 4 KiB pages. Both enumeration methods agreed on 188 dirty pages in both VMA layouts. |

The first DMD command stalled before linking with its default server discovery. It was interrupted (130) and rerun with in-process compilation. The structural fixtures explicitly remove this environment override. The full structural result needs a runner that permits binding a local Unix socket.

The probe printed the following. These are functional self-test samples only. The posidon runs supply the measurement record.

```text
C5 adjacent mapping: dirty; pipe read into clean page: dirty
1500 pages +0 VMAs: pread 10800 ns, enumeration 11200 ns, PAGEMAP_SCAN 10100 ns, clear_refs 19600 ns
1500 pages +2200 VMAs: pread 11100 ns, enumeration 11300 ns, PAGEMAP_SCAN 4900 ns, clear_refs 156700 ns
{"c5":true,"page_bytes":4096,"pipe_read":true,"samples":[{"clear_ns":19600,"dirty_pages":188,"enumerate_ns":11200,"extra_vmas":0,"pages":1500,"pread_ns":10800,"scan_ns":10100,"scan_supported":true,"total_vmas":36},{"clear_ns":156700,"dirty_pages":188,"enumerate_ns":11300,"extra_vmas":2200,"pages":1500,"pread_ns":11100,"scan_ns":4900,"scan_supported":true,"total_vmas":2237}]}
```

For sanitizer verification, using the same `hold` function:

```bash
export PATH="$PWD/.tools/LLVM-22.1.8-Linux-X64/bin:$PATH"
export LIBRARY_PATH="$PWD/.tools/ldc-1.43.0-sanitizer-runtime/lib"
export DFLAGS='-g -O1 -unittest -preview=dip1000 -boundscheck=on -fsanitize=address -defaultlib=phobos2-ldc-sanitizers,druntime-ldc-sanitizers -gcc=clang -Xcc=-fsanitize=address,undefined'
export UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1'
export ASAN_OPTIONS='detect_leaks=1:abort_on_error=1:detect_stack_use_after_return=1'
hold dub test :arena --compiler=ldc2 --build=plain --force -- '--DRT-gcopt=gc:flint-predict profile:1'
```

With leak detection enabled, DUB exited 2. All 17 unittest modules passed, then LeakSanitizer's exit scan failed. Verbose LeakSanitizer output identified the failing operation as `Could not attach to thread 4 (errno 1)`. This sandbox cannot verify leaks. The full leak-inclusive profile remains open.

The separate ASan + UBSan checks keep stack-use-after-return and halt-on-error enabled:

```bash
export ASAN_OPTIONS='detect_leaks=0:abort_on_error=1:detect_stack_use_after_return=1'
hold dub test :arena --compiler=ldc2 --build=plain --force -- '--DRT-gcopt=gc:flint-predict profile:1'
hold dub test :arena --compiler=ldc2 --build=plain -- --DRT-gcopt=gc:flint
```

Both exited 0 with 17 modules passed. A separate minimal allocation/collection program built with both compilers also exited 0 under `gc:conservative` (zeroed Flint profile) and `gc:flint-no-cache` (positive collection count, zero predictions).

## Posidon commands

Run in a disposable, provisioned posidon checkout containing m7's reviewed slice. The following setup changes only its diagnostic build recipes and local harness. The stock matrix fixes the manifest path and uses the application name as the workload key. The adapter below selects the existing error manifest and key and retains its raw digest, request, response checks, rate, phase lengths, database and CPU sets. The result directory holds the raw server logs and the per-trial records. The setup edits and shell/Python syntax were checked on temporary copies here. m7 runs the workloads on posidon.

```bash
set -euo pipefail
source ~/flint-work/posidon.env
: "${FLINT_MEASURE_LOCK:?source the shared posidon runner environment}"
export FLINT_HOME=$PWD
export PATH="$PWD/.tools/ldc2-1.43.0-linux-x86_64/bin:$PWD/.tools/dmd2/linux/bin64:$PATH"
out=$(mktemp -d "$PWD/slice0-posidon.XXXXXXXX")
timed() { python3 tools/measure_queue.py timed --label "$1" -- "${@:2}"; }
matrix() { timed "slice0-$1-$2" python3 tools/spring_bench.py gc-matrix "$2" --output "$out/$1-$2.json" "${@:3}"; }

python3 - <<'PY'
import json
from pathlib import Path
for app in ('gs-rest-service', 'petclinic-rest'):
    p = Path('benchmarks/spring/flint') / app / 'flint-spring.json'
    recipe = json.loads(p.read_text())
    assert recipe['build'] == ['flint', 'build', '--profile', 'release']
    recipe['build'] += ['--', '-d-version=FlintCollector']
    p.write_text(json.dumps(recipe, indent=2) + '\n')

p = Path('tools/spring_gc_matrix.py')
s = p.read_text()
def edit(old, new, count=1):
    global s
    assert s.count(old) == count, old
    s = s.replace(old, new)
edit("manifest_path = ROOT / 'policy' / 'spring-http-benchmark.json'",
     """key = os.environ.get('SLICE0_ERROR_KEY')
    manifest_path = ROOT / 'policy' / ('spring-error-paths-benchmark.json' if key else 'spring-http-benchmark.json')""")
edit("if app not in manifest['apps']:", "if manifest['apps'].get(key or app, {}).get('app', key or app) != app or (key or app) not in manifest['apps']:")
edit("spec = manifest['apps'][app]", "spec = manifest['apps'][key or app]")
edit("observer=observer)", "observer=observer, capacity_context=bool(key))", 2)
p.write_text(s)
PY
git diff -- benchmarks/spring/flint tools/spring_gc_matrix.py > "$out/diagnostic-harness.diff"
```

### 1. O3 parity

```bash
unset SLICE0_ERROR_KEY
for app in gs-rest-service petclinic-rest; do
  matrix parity "$app" --setting conservative --gcopt cached=gc:flint --gcopt uncached=gc:flint-no-cache --no-go
done
```

Check the release receipts for `-O3`, `-plugin-opt=O3` and `FlintCollector`, and the per-trial Flint binary hashes for equality across arms. Divide the exit report's total mark time and total pause by its collection count before comparing paired runs. Read the `Pauses` field of the druntime `GC summary` line for stop-the-world time. The matrix's `total_pause_ms` parser currently matches grand total GC time, which includes sweep. Parity requires both ratios in [0.95, 1.05].

### 2. Prediction on both error paths

```bash
for SLICE0_ERROR_KEY in gs-rest-service:not-found petclinic-rest:validation-error; do
  export SLICE0_ERROR_KEY
  matrix prediction "${SLICE0_ERROR_KEY%:*}" --setting conservative --gcopt predict=gc:flint-predict --no-go
done
rg 'GC summary:|Flint (pause ns|prediction ns|census):' "$out"/prediction-*-raw > "$out/prediction-profiles.txt"
```

Use the stock mean pause as the denominator for each paired trial. From the predictor log, price slice 1 as (suspend + roots + oldScan + resume) / predictions. Price slice 2 using the same suspend/root/resume floor, plus old-scan time scaled by dirtyScanBytes/scannableBytes, plus dirty-page enumeration. Use measurement 4 to price enumeration for the relevant heap size and VMA count. Report the full diagnostic census time separately. This scaling estimates bandwidth cost and cannot measure first-touch work for future young survivors. Require valid census intervals and positive scannable bytes. Report both estimates on each workload. The targets are ≤0.8× and ≤0.6× respectively. Predictor p99 includes additional stopped work.

### 3. Ceiling with interleaved Go

Use a large heap factor and verify that the fixed phase really had zero collections. For this diagnostic checkout, the following adds one flushed marker per full collection to a ceiling-only Flint build. The harness counts it at fixed-phase boundaries, outside the timed request loop. A collection during load invalidates the trial. Go runs in the same matrix session.

```bash
python3 - <<'PY'
from pathlib import Path
p = Path('packages/arena/source/flint/arena/sys/gc/collector.d')
s = p.read_text()
line = '        const collectionBegin = begin;'
assert s.count(line) == 1
p.write_text(s.replace(line, '''        import core.stdc.stdio : fputs, stderr;
        fputs("SLICE0_FULL\\n", stderr);
''' + line))
p = Path('tools/load_bench.py')
s = p.read_text()
line = '                    phases[phase]=run_oha(oha,url,workload,seconds,rate,outdir/'
assert s.count(line) == 1
s = s.replace(line, '''                    check_ceiling = target == "flint" and label == "flint-ceiling" and phase == "latency"
                    if check_ceiling:
                        before = log_path.read_bytes().count(b"SLICE0_FULL\\n")
''' + line)
line = '                observe("after-"+phase)'
assert s.count(line) == 1
p.write_text(s.replace(line, '''                if check_ceiling:
                    after = log_path.read_bytes().count(b"SLICE0_FULL\\n")
                    phases[phase]["fixed_gc_count"] = after - before
                    require(after == before, "collection during ceiling fixed phase")
''' + line))
PY
for SLICE0_ERROR_KEY in gs-rest-service:not-found petclinic-rest:validation-error; do
  export SLICE0_ERROR_KEY
  matrix ceiling "${SLICE0_ERROR_KEY%:*}" --gcopt 'ceiling=gc:flint heapSizeFactor:1000000'
done
```

Require a Flint phase report in the raw logs to establish that the custom collector was linked and selected. Inspect the recorded zero `fixed_gc_count` in every Flint trial. Compare the fixed-phase p99 ratio with 0.9 on each error path. RSS from this diagnostic arm is outside the ceiling comparison. If prediction or the ceiling fails on either path, stop and report to the owner.

### 4. Kernel probe

```bash
python3 tools/measure_queue.py hold -- ldc2 -O3 -preview=dip1000 -d-version=FlintSoftDirtyProbe \
  packages/arena/tests/softdirty_probe.d -of="$out/softdirty-probe"
for trial in $(seq 1 9); do
  timed "slice0-probe-$trial" "$out/softdirty-probe" > "$out/probe-$trial.txt"
done
```

Use the JSON line in each file for the 1,500-page rows. Compare `enumerate_ns` (pread plus bit count) and supported `scan_ns` with 15,000 ns. Compare `clear_ns` at the server's VMA count with 500,000 ns. Retain the raw samples, kernel version, toolchain receipts and all matrix outputs with the decision.
