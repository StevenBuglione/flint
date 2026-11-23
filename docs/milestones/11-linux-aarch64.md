# Milestone 11 · Native Linux aarch64

Native Linux aarch64 was built on `main`, with each verified stage pushed straight to `main`. It is the third platform of [ADR-021](../adr/ADR-021-flint-platform.md) row 11, after [macOS arm64](11-macos.md) and beside the Windows x86-64 port ([ADR-026](../adr/ADR-026-windows-x86-64.md)).

Until now, both Linux AArch64 lanes had run only in a full-system QEMU guest under TCG emulation, with wall-clock bounds reported instead of asserted ([Milestone 6](06.md#linux-aarch64)). This run is native: the CPU runs the code directly, and `FLINT_EMULATED` is not set, so every wall-clock bound is asserted.

## The runner

The runner is a virtual machine on `pluto`:

- **Host:** Apple M1 (8 cores), 16 GB, macOS 26.4.
- **Hypervisor:** Apple's Virtualization framework (`vmType: vz`) through Lima 2.1.0, installed with Homebrew. No QEMU is involved.
- **Guest:** Ubuntu 24.04.4 LTS arm64 (kernel 6.8.0-101, glibc 2.39, GCC 13.3, CMake 3.28) with 4 vCPUs, 8 GiB of memory and a sparse 60 GiB disk. The rest of `pluto` stays with the macOS work.
- **Toolchain:** LDC 1.43.0 linux-aarch64, the Flint DUB 1.43.0 built with it, Go 1.27.4 linux-arm64 and Rust 1.97.0, all from their pins.

The VM definition is a short Lima file. It has no host mounts, so the guest keeps its own checkout:

```yaml
base: template:ubuntu-24.04
vmType: vz
arch: aarch64
cpus: 4
memory: 8GiB
disk: 60GiB
mounts: []
containerd: {system: false, user: false}
ssh: {forwardAgent: true}
```

The apt prerequisites are the CI list (`.github/workflows/ci.yml`). `libxtst-dev` was added to that list, because the pinned SDL3 refuses to configure without XTest and a plain Ubuntu arm64 image does not have it. `gdb` is needed only for the debugger tests.

## What was built

- **Toolchain.** The forked DMD's AArch64 code generator is not finished on Linux yet (ADR-025 section 3), so Linux arm64 takes the macOS arrangement (ADR-024):
  - LDC's `ldmd2` fills the DMD role of the dev and test profiles.
  - The Flint DUB is built from source with LDC; its pipeline is off.
  - `install_toolchains.py --compiler dub` and the `flint` bootstrap accept a Linux arm64 glibc host, and `--compiler go` installs the new `go1.27.4.linux-arm64.tar.gz` pin.
  - The `flint` CLI's `host.d` has a Linux AArch64 branch, and its native identity reads the `linux-aarch64-glibc` provider install. `flint toolchain install`, `verify` and `doctor` all pass, and `flint` bootstraps itself.
- **All 37 packages** pass `dub test` natively on `ldc2`, without `FLINT_EMULATED`. They passed at `dbc55ca`, and again inside the lane at `931ff7e` after the ADR-030 engine rename. This needed no package change.
- **Native providers.** `tools/native_build.py --profile ci --target linux-aarch64-glibc --library wasmtime` builds all of the `ci` closure's providers and wasmtime from source on the guest.
- **Native C checks.** The `flint-ffi` ctest suite passes: the ABI probe, real io_uring on the 6.8 kernel, setup-denied seccomp, the llhttp/zlib library test and the MQ socket check.
- **Peers.** The platform lane now runs the peered packages through `flint test` on both compilers, as the macOS lane does. It runs them against PostgreSQL 18.7, Valkey 9.1.2, MinIO and the Go protocol peers, all built on the guest. At `af56e50` all 18 runs passed their functional checks, and only the wall-clock bounds below failed under load.
- **Live `mq` scenarios.** All 7 pass natively at `af56e50`: Kafka receipts, rebalance, rejection, drain and outage on a real KRaft broker, and NATS JetStream over loopback and verified TLS. Kafka runs on the Temurin aarch64 Linux JRE, a new `linux-aarch64-glibc` override in `policy/peer-lock.json`.
- **Tests.** The CLI, diagnostics and gdb tests find `ldmd2` on Linux arm64. The gdb probe uses `pragma(inline, false)` in place of x86 inline assembly.

## Evidence

The platform lane, in the guest:

```bash
export PATH="$PWD/.tools/dub-1.43.0/bin:$PWD/.tools/ldc2-1.43.0-linux-aarch64/bin:$PWD/.tools/bin:$PATH"
python3 tools/ci.py platform --target linux-aarch64-glibc
```

The lane runs these steps:

1. the native providers and wasmtime, built or verified from their receipts;
2. 37 `dub test` runs on `ldc2`;
3. 18 peered `flint test` runs, the nine peered packages on `ldmd2` and on `ldc2`;
4. the 7 live `mq` scenarios;
5. the five compile-negative fixtures and the BetterC fixtures on `ldc2`.

**No passing receipt exists yet, so Gate 6's `linux-aarch64-glibc` entry is still false.** Every recording so far ran on a busy shared host, and each one stopped at a step after the 37 suites:

| Commit | Exit | Time | Where it stopped | `pluto` load (1 min) |
| --- | ---: | ---: | --- | --- |
| `af56e50` | 1 | 823 s | peered `flint:http` on `ldmd2`: 20.9 ms of worker CPU against 15 ms | 9–11 |
| `af56e50` | 1 | 409 s | `flint:web` suite: delayed-echo median 263 µs against 250 µs | 3 at start, 12 at end |
| `af56e50` | 1 | 1021 s | peered `flint:http` on `ldc2`: median exchange 803.6 µs against 800 µs | 8 at start, 17 at end |
| `931ff7e` | 1 | 589 s | peered step: `flint test --verify` stops on FLINT-E0529, undeclared Boot-layer imports in `boot/core` | 3 at start, 8 at end |

Every functional assertion passed in every attempt. The first three each missed a different wall-clock bound, by 1–40%, under host contention (see below). The fourth passed the native providers and all 37 suites at the rebased head with every bound asserted, then stopped on a workspace check unrelated to arm64. That check comes from `89e274b` ("policy/boot.json: register Boot's 17 Phase 1 packages"): its Boot packages import modules that `policy/boot.json` does not declare. It fails the same way for any `flint test --verify` in the workspace, on any platform, so the macOS lane's peered step is blocked too until it is fixed.

Each failed receipt is kept with its log in the guest under `~/evidence/<commit>-attempt<n>/`. As with the other platforms (ADR-017 decision 4), receipts and logs stay on the runner rather than being committed. A receipt is bound to its commit, so the lane must be re-run after every rebase. Once a run passes, `tools/collect_evidence.py`'s receipt check (`verified_receipt` against the commit) makes Gate 6's entry true.

To record it once the Boot check passes:

```bash
~/flint-work/lima/quiet-lane.sh lane   # on pluto
```

The script waits until `pluto`'s 1-minute load is below 4 and its 5-minute load below 5. It then gives the VM process `nice -10` for the run only, and restores 0 afterwards. In the third attempt an incremental `renice -n` left the VM at -20 by mistake; the script now sets absolute values.

## Wall-clock bounds in a shared VM

The guest's bounds are real, but its vCPUs share `pluto` with the macOS work. Apple's Virtualization framework gives the guest no steal-time accounting (`/proc/stat` steal stays 0). When the host preempts a vCPU, the guest counts that time as CPU time of whatever thread was running.

`flint:http`'s reactor-fiber test asserts two bounds over 100 exchanges with an origin that answers after 300 µs: a median under 800 µs, and under 15 ms of worker CPU. Eight runs at `af56e50`, instrumented locally and not committed, measured the following:

| Host state | Median exchange | Worker CPU, 100 exchanges |
| --- | ---: | ---: |
| quiet (7 runs) | 381–482 µs | 5.7–11.4 ms |
| saturated (1 run) | 672 µs, tail to 3.9 ms | 22.7 ms |

At rest, Flint on arm64 meets both bounds with room to spare. A saturated host breaks them by shifting the whole distribution, not by adding a slow mode. A plain C loopback ping-pong in the same guest shows the cost of a wake-up: 51 µs median per blocking round trip, against 2.9 µs busy-polled.

`pluto` also runs the macOS and DMD arm64 work, and two unrelated `node serve-sim` processes that each hold a core at 100%. Its load average sat between 5 and 22 through this work. No bound was raised and no case was removed. A dedicated arm64 runner, or a quiet window on `pluto`, is what the lane needs.

## Not done

- **linux-aarch64-musl.** Not run natively. The container lane needs Docker in the guest and a second provider build for musl, and `pluto` had under 10 GB of free disk. Its Gate 6 entry rests on the Milestone 6 QEMU receipt until it is re-recorded.
- **DMD arm64.** The packages run on `ldmd2` until the dmd-arm64 work lands the forked DMD's AArch64 code generator on Linux (ADR-025 section 3). This VM is the native machine for its stage 2 on Linux and for stage 5's measurement.
- **The DUB pipeline with `ldmd2`.** It stays off on Linux arm64 (`host.d`, the `flint` bootstrap). macOS now runs it with a Darwin archiver (`442591f`), and Linux's ELF archives need no new archiver, so turning it on here is a small follow-up to measure.
- **Build measurement.** `tools/measure_builds.py` was not run on this guest. A run on a shared host would not be a fair baseline.

## Linux reruns

The shared changes are confined to Linux arm64: the new branches in `install_toolchains.py`, `host.d` and `receipt.d`, and the JRE override. On Linux x86-64 they select the same paths as before. The `linux-x86_64-glibc` platform lane is unchanged; only the arm64 lanes gained the peered step.

On a Linux arm64 checkout, `tests/test_flint_starters.py` failed three cases that start example servers (at `dbc55ca`, before the native providers were built). They were not re-run because starter work is paused.
