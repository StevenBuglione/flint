# Linux compile time after the first performance prototype

This study compares the previous performance branch at `1ea961c` with `85cb091`. The typed CLI and two-route REST application keep their existing D source and APIs. Values are medians of nine builds in milliseconds on an x86-64 glibc Ryzen 9 5900X. [Run-level samples](06-linux-compile-samples.csv)

## Time to a linked application

An edit is the first rebuild in the same mode, with the dependencies built by that mode's cold build. Package mode and combined mode are separate workflows. The checked DMD profile includes debug information, DIP1000 and full bounds checks. The previous revision used manual flags to select LLD.

| Build workflow | CLI cold | CLI edit | REST cold | REST edit |
| --- | ---: | ---: | ---: | ---: |
| Previous DMD, system linker | 930 | 454 | 1,195 | 692 |
| Current DMD, system linker | 845 | 399 | 1,142 | 693 |
| Previous DMD, LLD | 719 | 233 | 757 | 253 |
| Current DMD, LLD | 638 | 185 | 718 | 255 |
| Current DMD, mold | 609 | 162 | 690 | 219 |
| Previous DMD, LLD, combined | 314 | 306 | 376 | 367 |
| Current DMD, LLD, combined | 301 | 298 | 362 | 361 |
| Current DMD, mold, combined | 282 | 280 | 338 | 333 |
| Go | 109 | 106 | 208 | 212 |

With the same linker and package mode, the framework changes reduced CLI cold time by 11.3% and edit time by 20.3%. The corresponding current/previous ratios and 99% intervals were 0.887 (0.860–0.922) and 0.797 (0.771–0.851). For REST these ratios were 0.949 (0.923–0.979) cold and 1.005 (0.939–1.069) edited.

With mold in package mode, the checked CLI edit was 1.528 (1.461–1.809) times Go and the REST edit was 1.036 (0.945–1.182) times Go. With mold and combined mode, the cold ratios were 2.595 (2.479–2.727) for CLI and 1.624 (1.484–1.756) for REST.

## Edits that change the running application

A second nine-trial series changed the CLI's greeting punctuation and the REST controller's typed JSON message in temporary copies of both projects. Each edited binary produced the new output. The REST check also verified the health route on the same connection.

| Build workflow | CLI cold | CLI edit | REST cold | REST edit |
| --- | ---: | ---: | ---: | ---: |
| Previous DMD, LLD | 731 | 241 | 765 | 255 |
| Current DMD, LLD | 660 | 188 | 722 | 258 |
| Current DMD, mold | 632 | 169 | 712 | 228 |
| Go | 110 | 111 | 214 | 206 |

## Where compiler time went

- Config imports file, process, Unicode and owned JSON support inside the functions that use them. Seven paired DMD runs compiling the CLI application object alone fell from 138 to 94 ms. The framework preserves configuration precedence, errors, offsets and annotations.
- Serde defers implementation imports to the codec entry points, instantiates descriptor helpers as needed and orders owned TOML entries by source offset with an in-place heap sort. Validate instantiates the regex parser and lowering for annotated fields. A separate experiment sharing JSON member parsing slowed the 16 KiB escaped JSON round trip by 3.4%. Restoring its specialized implementation produced a release-mode Serde probe byte-for-byte identical to the previous revision. The final source retains that specialized implementation.
- Web reuses each controller's compile-time route table during registration. Application composition still checks for collisions between controllers. In an isolated 258-route fixture, nine checked DMD/LLD edit rebuilds fell from 623 to 590 ms, a 5.3% reduction (99% ratio interval 0.917–0.991). Both DMD and LDC served every route. The corresponding isolated two-route interval included equality.
- A separate identical-object comparison measured GNU BFD links at 226 ms for CLI and 466 ms for REST, and LLD links at 63 and 108 ms. In a 15-sample comparison on two cores, mold took 43 and 67 ms against LLD's 67 and 105 ms. The project-local installer can select either linker once. The resulting DMD compiler is the pinned upstream executable. Its ordinary DUB build products retain debug information.

## Release edits with the existing LDC toolchain

LDC 1.43.0 can retain native ThinLTO objects across edits. From an application directory on Linux with the native providers prepared:

```bash
mkdir -p .dub/flint-thinlto
DFLAGS='-preview=dip1000 -release -boundscheck=safeonly -O3 --flto=thin -link-defaultlib-shared=false -L-plugin-opt=cache-dir=.dub/flint-thinlto' \
  dub build --compiler=ldc2 --build=plain --skip-registry=all
```

The relative cache path stays one DFLAGS token when the checkout's absolute path has spaces. The command uses the GNU linker and the toolchain's LLVMgold plugin. Each of nine cache-enabled cold trials started with an empty private cache.

| Build workflow | CLI cold | CLI edit | REST cold | REST edit |
| --- | ---: | ---: | ---: | ---: |
| Ordinary ThinLTO | 1,830 | 563 | 2,405 | 910 |
| With local cache | 1,801 | 462 | 2,415 | 801 |

The cache reduced edited builds by 17.9% for CLI and 12.0% for REST. The respective time ratios were 0.821 (0.787–0.876) and 0.880 (0.838–0.936). A separate check changed the CLI version and the REST invalid-argument exit code and verified the new binaries and both REST responses. Tracing those links confirmed that they read 43 cached objects for CLI and 52 for REST.

## Measurement and verification

The canonical series ran on CPUs 2–5 with DMD 2.114.0, DUB 1.43.0, mold 3.0.0, LLD 21.1.8 and Go 1.27.4. The output-changing edit series used CPUs 10, 11, 22 and 23. The LDC cache series used CPUs 6, 7, 18 and 19. Comparisons used the same CPUs within each series on this ordinary workstation. Order rotated by trial and reversed on alternating trials. Each cold build started in a fresh source copy with an empty DUB home. Both revisions used the same 19-provider installation and verified archive list. Go started from a fresh copy of a standard-library-only cache and used the repository's frozen comparator and flags. OS page caches stayed warm. Timers covered the external build command through the link. Workspace setup, dependencies installed by the toolchain, and post-build verification were outside the timer.

DUB used `build --compiler=dmd --build=plain --skip-registry=all` with `DFLAGS='-preview=dip1000 -debug -g -boundscheck=on'`. Combined trials added `--combined`. Go used `build -trimpath -buildvcs=false -ldflags='-s -w'` and a fresh target path. In the CSV, `before` and `after` identify the source revisions above. A bare revision uses the system linker, a `combined` suffix on its own uses LLD, and `mold-combined` uses mold. The numbered trials pair each fresh build with its own edit.

The canonical edit appends the repository's private enum to D and the matching private constant to Go. Every measured Flint CLI binary ran its version command or checked the edited greeting. Go CLI builds checked the greeting and structured log. REST builds returned the expected health and JSON bodies on one persistent connection. Intervals use the repository's deterministic 10,000-resample ratio of medians. The release gate still requires its designated-host run.

Both DMD and LDC passed the Config, CLI, Serde, Validate and Web unit suites. All five structural checks passed. The formatter and scanner checked 61 D source and test files. The Python suite passed 38 tests. Separate coverage included the native and WASM BetterC fixtures, pinned libyaml, CLI diagnostics and structured logging, controller ambiguity diagnostics and HTTP/1, HTTP/2 and TLS protocol tests. Standard DUB builds of both apps with each selectable linker passed and their ELF debug sections and linker identities were verified.
