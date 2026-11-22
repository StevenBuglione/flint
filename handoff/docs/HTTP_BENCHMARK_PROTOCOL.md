# HTTP measurement protocol

`scaffold/tools/load_bench.py` produces measured HTTP evidence for the six-gate collector. It is a working Linux harness, not a Flint server implementation. Its checked-in smoke receipt uses the Go reference server in **both** target slots to exercise the harness. That receipt has `mode: "smoke"` and is never acceptable as Flint-versus-Go performance evidence.

## Reproduce the production measurement

Run from the implemented monorepo root after `tools/measure_builds.py` publishes its verified **O3** binaries at `build/bench-rest` and `build/reference-go-rest`:

```sh
python3 tools/load_bench.py --manifest policy/http-benchmark.json --output artifacts/http-load.json --oha .tools/oha-1.16.0/oha
```

The supplied policy requires nine paired trials, 10 seconds of warm-up, 60 seconds of fixed-rate latency measurement, and a separate 60-second throughput-capacity phase for each server. A fresh process starts for every server/trial. Target order alternates Flint/Go then Go/Flint. The production invocation takes at least 39 minutes, plus build, startup, drain, and cleanup time. Do not shorten it to make a pull request pass.

The pinned load generator is the upstream Linux x86-64 `oha 1.16.0` release binary. The script checks both its bytes and `--version` before starting:

```text
https://github.com/hatoo/oha/releases/download/v1.16.0/oha-linux-amd64
SHA256 620bb9e16fb53eabc9a3fc45f88bdb41fefa3fee5c05e75892011ce320391716
```

This hash records the downloaded release artifact. It is not a claim of independent signature verification. The runner must provide `taskset`, `/proc`, readable CPU topology, and the CPU IDs in the workload manifest. The canonical runner has server CPUs 2–3 and client CPUs 4–7; provision that topology or change the reviewed manifest for both base and candidate. The manifest hash is part of the comparison fingerprint.

## Equivalent workload and two measurement phases

Both native server executables implement `GET /json` with HTTP/1.1 keep-alive and this exact 26-byte UTF-8 body, without a newline:

```json
{"message":"hello","n":42}
```

Both serialize the typed message for each request. The D implementation uses the arena-backed JSON encoder; the Go reference uses `encoding/json`. Matching a precomputed constant in one server against per-request serialization in the other invalidates the comparison.

The latency phase offers 20,000 requests/second with 64 connections and `--latency-correction`. It records p50, p99, p99.9, process CPU nanoseconds per completed request, and process peak resident memory. Oha's corrected latency includes waiting for the scheduled request slot/available connection. The script rejects a run completing fewer than 99.5% of the nominal offered request count, transport errors, non-200 responses, missing tail percentiles, non-finite measurements, and reversed percentile order. Time-based `-w` drains outstanding requests; the phase has an additional bounded wall-clock deadline.

The separate capacity phase uses the same endpoint, connection count, time interval, and server CPU quota without `-q`. Its successful requests/second supply the throughput metric. Comparing throughput while both servers are capped at the same fixed offered rate cannot establish a 1% capacity advantage, which is why the two measurements are separate. Capacity-phase tail latency and CPU are retained in raw evidence but do not replace the matched-load latency/CPU arrays.

The server and generator have disjoint CPU sets, and production rejects sets sharing an SMT physical core. `FLINT_CORES=2` and `GOMAXPROCS=2` are explicit target environments. The script pins its own body/RSS monitor to client CPUs. Production also rejects a phase if the generator consumes at least 85% of its assigned CPU capacity; a client-limited result cannot demonstrate server throughput. This heuristic is a guard against obvious saturation, not proof that every network or scheduler bottleneck has been excluded.

## What is measured

| Output field | Source and meaning |
|---|---|
| `p50_ms`, `p99_ms`, `p999_ms` | Oha's fixed-rate `latencyPercentiles.p50`, `.p99`, and `.p99.9`, converted from seconds to milliseconds; one value per trial. |
| `requests_per_second` | Oha's successful capacity-phase requests/second, one value per trial. |
| `cpu_ns_per_request` | Difference in server `/proc/PID/stat` user+system ticks across the fixed-rate phase, converted using `SC_CLK_TCK`, divided by successful load requests plus completed body sentinel probes. Threads are included in the process counters. Child processes invalidate the single-process accounting. |
| `peak_rss_bytes` | Maximum of process `VmHWM` and sampled `VmRSS`, in bytes. Because `VmHWM` is a process lifetime high-water mark, startup and warm-up peaks remain included. This is process RSS, not whole-machine RAM or allocator-requested bytes. |
| `servers.flint/go` | Resolved executable path, exact SHA256, effective `taskset`+server argv, and explicitly configured environment. `/proc/PID/exe` must hash to that executable after readiness, and the file must not change during a trial. The collector matches these hashes to the measured O3 build artifacts. |
| `trials` | Every warm-up, latency, and capacity raw-result hash, command, exit code, wall time, CPU/probe counters, and server log path. |

The script reads exact response bytes before load, after each phase, and through a once-per-second sentinel while the phase is active. Oha independently checks success/status and aggregates body bytes; the script requires every recorded response length to equal 26 bytes. **The sentinel is sampled correctness, not a byte-for-byte validator for every load-generator response.** Full response-format correctness belongs to the protocol unit/integration suite as well. All probes are recorded and their successful requests are included in the CPU denominator.

The first readiness request is outside measured CPU time. The fixed-rate phase starts after warm-up. CPU ticks have the host kernel's accounting resolution; the 60-second production interval reduces quantization effects. RSS sampling runs approximately every 20 milliseconds, supplemented by the kernel's high-water counter. Neither samples nor warm-up output may be silently discarded based on the performance result.

## Evidence and failures

The output has schema 1, `mode: "production"`, `status: "passed"`, the manifest SHA256, effective workload, pinned tool identity, `rest` metric arrays, `go.rest` arrays, server identities, and detailed trial receipts. Each array contains exactly nine values. The measured gate compares complete independent base/candidate collections with identical runner, toolchain, dependency, and workload fingerprints; the baseline must identify a different commit. Bootstrap never manufactures baseline values.

Unexpected server exit, wrong bytes/content type, an already listening endpoint, child processes, binary mutation, timeout, missing raw JSON fields, oha failure, failed offered-load delivery, or absent process counters cause a nonzero exit. A failure after measurement initialization writes partial evidence with `status: "failed"`. Those partial arrays cannot pass the collector. Servers and timed-out generator process groups are terminated during cleanup.

For harness development, `--smoke` reduces trials to one and intervals to 1/2/2 seconds, caps offered load at 1,000 requests/second and connections at eight, and skips the production CPU-saturation/SMT guard. It still verifies the pinned executable, response contract, statuses, counters, raw files, and server binary identity. Do not copy smoke arrays into a production file. The supplied `verification/oha-smoke-manifest.json` deliberately uses a scratch-built Go binary for both slots; adjust its paths when independently reproducing the harness check.

## Authoritative references

- [Oha 1.16.0 README](https://github.com/hatoo/oha/blob/v1.16.0/README.md): time-bounded runs, fixed rate, latency correction, and JSON output.
- [Oha 1.16.0 output schema](https://github.com/hatoo/oha/blob/v1.16.0/schema.json): exact metric names and latency units.
- [Oha 1.16.0 command implementation](https://github.com/hatoo/oha/blob/v1.16.0/src/main.rs): supported flags and rate/correction behavior.
- [Linux proc filesystem documentation](https://docs.kernel.org/filesystems/proc.html): process CPU fields, RSS/high-water counters, and task/process scope.

The trial count, thresholds, CPU allocation, JSON message, alternating order, and gate policy are Flint project decisions, not claims made by these upstream sources.
