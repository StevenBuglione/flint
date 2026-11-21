# Flint operation microbenchmarks

Build and run with the pinned Linux native reactor and toolchain after the source and workload freeze.

```sh
dub run --quiet --root=benchmarks/micro --compiler=ldc2 --build=release
```

The program writes one JSON object. Each of the five release series contains 21 independent trials in nanoseconds per completed operation. A batch warms each trial before measurement. Timed batches run for at least 100 ms, and the result retains their operation counts, checksums, and monotonic elapsed times. Loopback connection setup and explicit cancellation happen outside the timed interval.

- **Arena** uses a fixed 64 KiB region and a 64-byte pattern. Setup verifies the written bytes and stale-handle rejection. Every timed operation allocates, writes, reads, and resets an arena generation.
- **Serde** round trips the shared 26-byte REST DTO. Every operation checks the wire bytes and both decoded fields.
- **Validate** repeats eight DTOs with two accepted inputs and six rejected inputs. The corpus includes ASCII blanks, Unicode blanks, multibyte text, both range limits, and text-length failures. Every operation verifies its exact violation count.
- **Router** dispatches prepared literal, parameter, wildcard, and missing routes through the production dispatcher. The selected handler and captured spans are checked. The result carries the exact route and request tables and their hashes.
- **Reactor echo** uses four persistent loopback connections and verifies all 64 returned bytes per operation. Every trial checks four final cancelled reads, EOF on each peer, and zero outstanding operations after joining the reactor. The result identifies the actual backend and payload digest.

TOML round-trip observations are reported as the separate `diagnostics.serde_toml` series. They do not enter the JSON series. Pass `-- --smoke` to exercise a single short observation per workload. Its sample count fails the production collector.
