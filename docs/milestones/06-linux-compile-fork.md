# Linux compile time with the Flint toolchain fork

With the forked DMD and DUB in `toolchain/`, the unchanged typed CLI and two-route REST applications build faster than the pinned Go comparator, both from a cold source tree and after an edit. All four 99% intervals lie on the favourable side of the 0.99 Go-relative limit. Application source, Flint APIs, the checked build profile and the `dub build` command are unchanged. [Raw samples](06-linux-compile-fork-samples.csv)

## Results

Medians of nine paired trials in milliseconds, x86-64 glibc, AMD Ryzen 9 5900X, Linux 6.18.59.

| Workflow | Flint fork | Go 1.27.4 | Flint / Go | 99% interval |
| --- | ---: | ---: | ---: | --- |
| CLI cold | 93.4 | 107.8 | 0.867 | 0.835–0.895 |
| CLI after edit | 78.9 | 109.6 | 0.720 | 0.687–0.752 |
| REST cold | 119.9 | 193.0 | 0.621 | 0.587–0.635 |
| REST after edit | 97.1 | 194.2 | 0.500 | 0.481–0.618 |

The same applications with the upstream DMD and DUB and the mold linker, measured in five trials on the same machine during the same session:

| Upstream workflow | CLI cold | CLI edit | REST cold | REST edit |
| --- | ---: | ---: | ---: | ---: |
| `dub build` | 617.5 | 179.0 | 676.5 | 229.0 |
| `dub build --combined` | 295.6 | 291.2 | 345.0 | 344.3 |

The first build after the compile server has exited starts the server and compiles without it. That build took 283 ms for the CLI and 226 ms for REST. The next cold build used the server.

## What changed

The DMD fork keeps the 137 druntime and Phobos modules that these applications import analysed in a resident server and forks a pre-started worker for each compile. A worker refuses any request that could observe that state, and the caller then compiles in-process. The DMD fork also runs the linker that `cc` would choose directly, with the same startup files, libraries and search order. The DUB fork compiles balanced chunks of every out-of-date package at once, archives libraries in-process, and caches the compiler platform probe. [Toolchain fork](../../toolchain/README.md)

The phases of one cold CLI build show where the time now goes:

| Phase | Elapsed ms |
| --- | ---: |
| DUB start, recipe loading and planning | 8 |
| Parallel compilation of 58 modules in 22 jobs | 47 |
| In-process archives | 4 |
| Direct mold link | 33 |
| Copy to `build/` and exit | 2 |

The application module dominates the compile phase. Instantiating `load!Settings` and `parse!Options` accounts for about 12 ms of its 42 ms in a time trace, and emitting the resulting instances for another 10 ms. The link floor is mold reading the 12,586 members of the pinned static `libphobos2.a`, about 17 ms of mold time even for a hello-world program.

## Measurement

`tools/compare_go_builds.py` ran all series. Each cold Flint trial copies the repository source into a fresh directory with an empty `DUB_HOME`, then runs `dub build --compiler=dmd --build=plain --skip-registry=all` with `DFLAGS='-preview=dip1000 -debug -g -boundscheck=on'`. The edit appends the repository's private enum to the application module and rebuilds. Each Go trial copies the frozen comparator and a standard-library-only primed `GOCACHE`, then runs `go build -trimpath -buildvcs=false -ldflags='-s -w'`; its edit appends a private constant. Every binary ran after every build: the CLI printed its greeting and the REST server returned the exact health and JSON bodies on one persistent connection. Trial order alternated between toolchains and applications. Timers covered the build command only.

The REST recipe links the verified native install that `tools/native_build.py --emit-dub` emitted for the previous performance study, shared by every trial. The compile server was running before the measured series, as ADR-016 proposes for a retained toolchain runtime. It held only druntime and Phobos. The CPUs were not pinned on this ordinary workstation, so these figures are not the designated-runner Gate 3 result. Intervals use the repository's deterministic 10,000-resample ratio of medians.

The installer built the measured toolchain from the checksum-locked archives in a directory whose path contains a space:

```bash
python3 tools/install_toolchains.py --compiler dmd --dmd-linker mold --flint-fork
```

## Verification

Every package's `dub test :<package> --compiler=dmd` suite gave the same result with the fork as with the upstream toolchain: 35 packages passed with both. `desktop` failed in both on the SDL runtime assertion in this environment, and `rpc` failed in both on the missing native RPC fixture archive recorded in Milestone 06. Compile errors printed identical text, positions and source excerpts with and without the server. An edit to Flint Arena rebuilt Arena, every dependent package and the application. The golden CLI ran, and the golden REST service passed its verifier for invalid requests, persistence across a restart and migration drift. Both patches apply to the pristine pinned sources.

## Remaining work

- Run the nine-trial comparison on the designated `flint-perf-x86_64-v1` runner and record compiler RSS for the build tree and, separately, for the server.
- Review ADR-016.
- Reduce the application module's template work in Config, CLI and Serde, and the link time spent on the static Phobos archive, to widen the CLI cold margin.
