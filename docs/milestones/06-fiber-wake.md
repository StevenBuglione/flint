# Fiber wake-up for stream and HTTP-client waiters

Base `31bd297`, measured on venus (Ubuntu 24.04, AMD Ryzen AI MAX+ 395 with 16 cores and 32 threads, Linux 7.0) with the pinned DMD 2.114.0 fork, LDC 1.43.0 and Go 1.27.4. Both trees linked the same privately built REST provider closure (OpenSSL, nghttp2, libcurl `http-only`, llhttp, liburing). Test binaries and builds ran pinned to CPUs 8–17 and 24–31, away from the benchmark's CPUs 2–7 and their SMT siblings 18–23. ADR-017 ("Public API additions", fiber wake-up) records the API.

## Change

Before this change, owner fibers waiting on HTTP/1 streamed or upgraded responses, HTTP/2 streams or the libcurl client had no completion wake-up. They resumed on every loop pass for 200 µs, then polled every 1 ms. `Reactor.wake(TaskWaker)` now marks a suspended fiber due from the completion, protocol event or libcurl callback it waits on. The loop resumes it on its next pass. The spin windows are gone. A 1 s fallback deadline remains only as a safety net.

## Delayed peers

Each test below is in the package suite. The base numbers come from running the same test source against `31bd297`, where the test fails. Medians are from LDC builds, and the runs repeated within 1%.

| Case | Base `31bd297` | This change |
| --- | ---: | ---: |
| HTTP/1 upgraded echo, peer sends 300 µs after each reply: median reply | 1,016 µs | 12 µs |
| Same, process CPU for 200 echoes | 43.5 ms | 2.9 ms |
| Same, wall time for 200 echoes (60 ms of it is the peer's own sleeps) | 273 ms | 73 ms |
| HTTP client, origin answers after 300 µs: median exchange | 1,328 µs | 322 µs |
| Same, worker CPU for 100 exchanges | 21.2 ms | 1.8 ms |

The echo handler now answers 12 µs after the message arrives, instead of at the next 1 ms poll. The client completes 22 µs after the origin's 300 µs. CPU falls by 15× and 12×, because waiting fibers no longer spin.

The loopback-only wall-clock tests and the 64-fiber HTTP/2 multiplex test, whose round trips stay inside the old spin window, kept their times (for example 9–10 ms against 10–11 ms for the multiplex test). The gRPC transport suite, which drives HTTP/2 duplex server streams through `HttpStream`, took 1.16 s on both trees. With both fallback deadlines raised to 5 s, every web, HTTP, RPC, MCP and actuator suite kept its time, so no path depends on the fallback.

## REST load benchmark

`tools/load_bench.py` ran nine trials per side. Each trial ran Flint `bench-rest` and the Go reference, with a 10 s warm-up, 60 s at a fixed 20,000 requests per second, then a 60 s capacity run. The server ran on CPUs 2–3 and oha 1.16.0 on CPUs 4–7. The base binary (`15b0468b…`) ran first, from 18:30 to 19:11 UTC. This change's binary (`23626972…`) ran next, until 19:51. Both sides used the same Go binary (`0b438b9a…`). Another session's builds ran during the window on CPUs 8 and above, with a load average of 2.5–4.8.

Medians of the nine trials. Latency and CPU per request come from the fixed-rate phase. Throughput comes from the capacity phase.

| Flint metric | Base `31bd297` | This change | Change / base |
| --- | ---: | ---: | ---: |
| Requests per second at capacity | 426,870 | 426,615 | 0.999 |
| CPU per request, fixed rate | 5.25 µs | 5.19 µs | 0.989 |
| CPU per request, capacity | 4.68 µs | 4.68 µs | 1.001 |
| p50 | 0.050 ms | 0.050 ms | 0.992 |
| p99 | 0.119 ms | 0.114 ms | 0.961 |
| p99.9 | 0.905 ms | 0.665 ms | 0.735 |
| Peak RSS | 12.18 MiB | 12.17 MiB | 0.999 |

There is no regression. The REST endpoint answers each request on the connection's fiber and never waits on a stream or the client, so a neutral result is expected. The tail differences are host noise rather than an effect of this change. In the base window, one Flint trial reached 0.82 ms p99 and 3.2 ms p99.9, and Go's own p99.9 median fell from 2.47 ms to 0.94 ms between the windows (Go's p99 from 0.280 ms to 0.227 ms). The Flint/Go ratios moved only because Go's window was quieter: capacity throughput 1.71 → 1.68 times Go, CPU per request 0.61 → 0.65 of Go's.

Two harness deviations, both outside the measured workload:

- **Ports.** Ports 8080/8081 were taken on venus, so a copy of `policy/http-benchmark.json` moved the servers to 18080/18081 and noted that in its description. Nothing else changed.
- **Port wait.** The unmodified harness failed both sides at trial 2 with "benchmark endpoint is already listening". Trials alternate which server starts first, so every even trial starts a Flint server right after the previous trial stopped one. That just-stopped Flint listener still accepted connections. A local, uncommitted copy of the harness instead polls the port every 50 ms for up to 10 s and logs the wait. Apart from a 1 ms check before the first trial, each wait was one poll (0.05 s), on the base and on this change alike, and always at a Flint-after-Flint start. A killed `bench-rest` run outside the harness frees its port within 5 ms, so the cause is not yet known. It is reported as a follow-up and not changed here.
