# REST comparison workload

Both Flint and Go encode the same typed message on every GET /json request; output is exactly `{"message":"hello","n":42}` (no newline). HTTP1 keepalive, four cores, no TLS/database/request logging. The reference uses encoding/json.Marshal, not a pre-serialized shortcut. Correctness is checked before load. This application does not use a faster test-only codepath.

From the implementation root: `dub build --root=benchmarks/bench-rest --compiler=ldc2 --build=release`; output `build/bench-rest`. It accepts `--listen 127.0.0.1:8080`. Set GOMAXPROCS=4 for the reference. Alternative TLS/H2/database workloads require separate matched reference cases.
