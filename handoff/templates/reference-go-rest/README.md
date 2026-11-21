# Equivalent Go reference

Pinned compiler: Go 1.27.4. No external Go modules. Run `go test ./...`, `go build -buildvcs=false -trimpath -ldflags="-s -w" -o reference-go-rest .`, and `./reference-go-rest -listen 127.0.0.1:8081`. Set `GOTOOLCHAIN=local` in hermetic CI so a compiler mismatch fails rather than downloading another toolchain implicitly.

The exact comparison response is `{"message":"hello","n":42}` with content type `application/json`, HTTP 200 and no trailing newline. Both implementations use HTTP/1.1 keepalive, no TLS/database/request logging, the same physical core budget and equal timeout limits. This is the transport baseline; separate secure/database scenarios must compare equivalent implementations.

The shutdown channel is joined before exit. SIGINT/SIGTERM initiates a bounded graceful shutdown. Benchmark traffic must not call a test-only or optimized alternate endpoint.
