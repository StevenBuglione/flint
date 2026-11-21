# Linux performance against Go

Measured source `0a9e322f175a895922f9e05d030284f0bbc9bc01` uses the pinned D runtime and the canonical CLI and REST applications. This prototype branch includes typed configuration binding changes, active-I/O iteration, sparse HTTP/1 connection storage and a size-optimized build of the locked OpenSSL release. All observations below came from a local x86-64 Ryzen 9 5900X workstation. DMD was 2.114.0, LDC 1.43.0, DUB 1.43.0 and Go 1.27.4.

## Developer builds

The table gives median wall time in milliseconds across nine builds per cell. Each trial started with a fresh copy of the application and framework sources and an empty Flint build cache. Go received a fresh copy of its standard-library-only cache built with the matching trimpath profile. The prepared C archives and compilers were shared. The edit changed an application source declaration and retained the build cache from that trial's cold build. Timing includes DUB or Go process startup through the final executable link. The machine's filesystem cache was warm.

| Application and state | Standard DUB | DUB with LLD | DUB combined with LLD | Go |
| --- | ---: | ---: | ---: | ---: |
| CLI cold | 946 | 724 | 319 | 116 |
| CLI after edit | 461 | 243 | 320 | 116 |
| REST cold | 1,196 | 760 | 394 | 233 |
| REST after edit | 698 | 276 | 384 | 247 |

The checked DMD profile includes DIP1000, debug information and bounds checks. Combined mode reduced repeated package compilation on a cold build. Package mode reused framework objects after an application edit. Each column is a complete build configuration. Switching modes between the cold and edited rows has its own cache cost. All modes miss the Go cold-build threshold. The cold comparison used DUB's documented combined build option. [DUB build options](https://dub.pm/cli-reference/dub-build/) The combined cold Flint/Go ratios are 2.74 for CLI and 1.69 for REST. Their 99% upper bounds are 3.11 and 2.05.

For scale, an empty DUB application built with combined mode and LLD took 71 ms. Direct DMD took 62 ms, and the empty Go executable took 61 ms. Those nine-run diagnostics include the link. The full CLI measurement gives Flint a budget of about 115 ms to reach 99% of Go. That leaves roughly 44 ms above the measured empty-DUB cost to compile the entire framework and application and link the larger program. The corresponding REST budget is about 230 ms. Both budgets move with the host and workload.

Two compiler traces identified source-level costs. Removing two generic formatting calls from configuration errors reduced semantic-analysis time in that helper from 45.4 to 0.7 ms and kept error strings and offsets byte-identical. Narrowing the typed configuration prefix and filename handling brought one direct checked CLI compile from 284 to 255 ms before linking. The separate file-loading import still took about 21 ms inclusive. An isolated link of the same debug REST object took 325 ms with GNU ld and 93 ms with LLD. These component trials used their own controls. Adding their times together would conflate distinct workloads.

An additional experimental driver obtained the graph from DUB, grouped framework sources into three independent checked DMD invocations, and compiled the application as a fourth group. It verified the application after cold and edited builds. On the earlier prototype, its cold medians were 338 ms against 117 ms for Go CLI, and 364 ms against 228 ms for Go REST. Its edited medians were 263/118 ms and 277/225 ms respectively. A separate per-module experiment found that compiling the full REST graph in one group and recompiling only the app later can leave Phobos template symbols undefined. An incremental build backend needs consistent compilation groups from its first build.

## Native release output

Both release profiles used pinned providers, ThinLTO, the normal Linux linker and ordinary relocations. The Oz binary is the repository's Go size comparison. The application, its TLS features, the provider revision and the Go comparator were fixed.

| Stripped executable | Flint | Go | Reduction |
| --- | ---: | ---: | ---: |
| CLI Oz | 1,217,800 bytes | 2,732,192 bytes | 55.4% |
| REST Oz | 6,462,000 bytes | 6,598,816 bytes | 2.1% |

REST O3 was 6,511,152 bytes. The earlier REST link map attributed about 70.4% of the entire file to input sections from the two OpenSSL archives. Building that provider with size optimization and separately discardable C functions and data reduced the shipped ELF. The regular native build recompiled the pinned OpenSSL and liburing sources and the Flint shims into a private copy of the other prepared providers. All four native CTests passed, and the repository's source and archive identity check verified the committed source and 19-provider receipt.

A separate TLS check isolated the OpenSSL change using two protocol executables built from identical earlier D objects and the same linker flags. Nine alternating pairs of 80 new trusted TLS connections plus a typed request took 128.0 ms with the smaller provider versus 122.6 ms with the original provider. The median ratio was 1.044, with a 99% interval of 0.984–1.156. A persistent-connection test fetching 192 bodies of 128 KiB took 7.60 s versus 7.65 s. These measurements leave a possible handshake regression to resolve through profiling or selective optimization of hot C code before release. They compare the two Flint providers.

The final CLI ran its version command. Both final REST binaries served the exact health and typed JSON responses on one persistent connection on glibc 2.42 and 2.44. The final protocol fixture passed HTTP/1 bindings and backpressure, multiplexed HTTP/2 with flow control and GOAWAY, trusted TLS and ALPN, and shutdown with 1,024 admitted fibers. Config, Reactor and Web passed their DMD and LDC unit suites and structural checks. Formatter and scanner checked 37 source files. The final 100,000-response probe measured zero GC allocation on both workers and zero collections.

## REST runtime

Nine alternating local pairs used the final O3 executable and the frozen Go executable. Each server had two workers and two CPU cores. The load generator used 64 keepalive connections and verified the canonical 26-byte JSON response. This diagnostic used a one-second warmup, three seconds at 20,000 requests/s and a separate one-second capacity phase. The intervals use the repository's 10,000-replicate bootstrap.

| Metric | Flint | Go | Flint / Go, 99% interval |
| --- | ---: | ---: | ---: |
| Capacity requests/s | 195,817 | 103,031 | 1.228–2.071 |
| Fixed-rate CPU per request | 10.67 µs | 17.18 µs | 0.592–0.738 |
| Fixed-rate p99 | 1.241 ms | 2.304 ms | 0.337–1.256 |
| Peak resident memory | 21.36 MB | 13.94 MB | 1.523–1.579 |

The new reactor visits slots with active I/O. The final CPU and throughput intervals favored Flint. The p99 median favored Flint, and its interval crossed parity. All requests succeeded. The earlier full-duration Milestone 6 comparison measured 153,948 versus 75,551 requests/s and 2.373 versus 6.164 ms p99 on earlier Flint code. A full-duration rerun on an intermediate memory revision stopped when the benchmark port was occupied, so it supplied no complete comparison. The final code still needs the full-duration run on the designated host.

## Resident memory

The stock-runtime HTTP/1 change reserves a fixed-size, GC-visible table and initializes each slot on its first connection. It keeps the 4,096-connections-per-core limit, slot addresses, parser generations, cancellation and worker shutdown. A single-worker test exercised the full limit, refused excess admissions and reused retired slots. Both D compilers passed two forced collections while 1,024 fibers were suspended. The same diagnostic on the original and revised table showed the stock-runtime peak falling from 26.37 MB to 21.30 MB.

The next largest measured cost is 2,176 guarded fiber stacks. Preparing their initial frames dirties one 4 KiB page per fiber, about 8.91 MB before useful work. A separate experiment deferred frame initialization in a private LDC runtime object and reduced the io_uring submission queue while preserving completion capacity. Combined with the sparse HTTP/1 table, it reached **10.49 MB against Go's 13.76 MB** in one matched eight-second measurement after warmup at 20,000 requests/s. The stock sparse build in that comparison used 21.30 MB. All five tested variants served approximately 160,000 correct responses each. The runtime modification and smaller queue remain experimental. The supported stock runtime is the one used in the main table.

## Engineering priorities

1. **Put framework work outside the consumer's template instantiations.** Keep typed configuration, CLI options, routes, DTOs, DI and compiler diagnostics at the public API. Reduce each per-type expansion to static descriptors and small checked adapters. Give the parsing, binding, formatting and dispatch algorithms ordinary non-template implementations. Start with the traced config file and schema imports and the Web/Serde dependency graph. Verify positive and compiler-negative examples, exact diagnostic text and both applications at each step. A fresh build must still compile every enabled Flint implementation. Reprofile before considering a compiler change.
2. **Keep the developer command and optimize the build underneath it.** Combined DUB plus LLD is the current cold-build reference. For edits, keep stable, reusable object groups and invalidate consumers when types, imported templates, versions or provider flags change. Remeasure both states from the same sequence. Use the roughly 115 ms CLI and 230 ms REST targets on this host to decide whether a change earns further work.
3. **Remove the eager fiber-frame cost within the supported runtime contract.** The stock build needs another 7.57 MB against the matched Go RSS threshold. Deferred initial frames alone address an 8.91 MB cost. A supported druntime implementation must preserve guard pages, precise stack registration, stack switching, pool capacity and zero steady-state D allocations. Validate both compilers, cancellation and exhaustion. The shorter io_uring submission queue also needs burst fairness and drain measurements. The private runtime object is excluded from the prototype branch.
4. **Verify all comparisons on one binary pair.** Use the original workloads, fully prepared native closure, canonical sources and thresholds. Repeat the full 10-second warmup, 60-second fixed-rate and 60-second capacity phases for all nine pairs, along with checked cold and edited builds, compiler RSS, package caps, template counts and hot GC. The designated bare-metal runner and an approved historical baseline remain outstanding for release qualification.

## Evidence

The measured source and documentation are on the Linux performance prototype branch. Local receipts are under `artifacts/tasks/m6-perf-investigation`. The final build observations are in `final-build/build-loop.jsonl`, with each command's output in `final-build/build-loop-logs`. `final-stock-go/README.md` links the runtime results. `final-binaries.sha256`, `final-source-identity.json`, `final-protocol.log` and `final-hot-gc.json` identify the exact release artifacts and their verification. The CLI trace investigations are under `artifacts/tasks/m6-integration/cli-front-end`. The sparse-table and runtime-object comparisons are under `artifacts/tasks/m6-web-sparse-table` and `artifacts/tasks/m6-rss-residual`. The original full-duration results are in the [Milestone 6 checkpoint](06.md).

The local study manifest is `EVIDENCE.sha256` with SHA-256 `b06175cac2297a186eafa70d7238f17dfa1f75c37e735ab0452d4c08b416ecc0`.
