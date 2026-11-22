# Minimal REST worker GC probe

Run with the pinned Linux native providers linked.

```sh
dub run --quiet --root=benchmarks/hot-gc --compiler=ldc2 --build=release
```

The probe links the same HTTP/1.1 server configuration, router, and typed REST controller as `bench-rest`. It binds numeric loopback and establishes one persistent connection to each of the two configured reactor workers. This application creates no logging or controller-offload workers. Client connections and numeric sampling slots are prepared before warmup.

The coordinator verifies 10,000 warmup responses and 100,000 measured responses against the complete canonical status line, response headers, and JSON body. Each client connection has at most one request outstanding. The first control exchange on each worker records its Linux thread ID and monotonic D GC allocation counter before the coordinator releases measured work. After the final measured response on a connection, the client's next control exchange follows that response's write completion and arena retirement. This lets each worker sample its own counter after its measured requests drain. The coordinator reads the process collection counter between the completed opening barrier and the first measured request, and again after both closing samples. Automatic collection stays enabled.

A changed worker identity, failed response, missing slot, deadline, or shutdown error exits nonzero. Successful observation writes one JSON object with the raw samples and deltas. Nonzero allocation and collection deltas remain visible to the release gate.

Pass `-- --smoke` to `dub run` for 20 warmup and 100 observed requests. The smoke run exercises both barriers and reports `phase: "smoke"`. The release collector rejects that phase.
