# ADR-016: Count a resident toolchain compile server as a retained toolchain runtime

Status: proposed, awaiting review; date: 2026-11-21.

## Context

Gate 3 and the Go-relative compile goal define a cold build as a fresh copy of the project source and a fresh `DUB_HOME` build cache, with immutable native install archives shared, precompiled toolchain runtimes retained and the OS page cache warm. The Go comparator starts each cold build from a fresh copy of a standard-library-only primed `GOCACHE`, so Go never recompiles `encoding/json`, `net/http` or `log/slog` during a measured build.

Stock DMD re-parses and re-analyses every imported druntime and Phobos module in every compiler invocation. In the typed CLI that work was about 84 ms of a 214 ms combined compile, and it repeats in each parallel compile.

The Flint DMD fork (`toolchain/`) keeps those toolchain modules analysed in a background server and forks a worker per compile. The server's state derives only from the compiler executable, its configuration, its flags and the toolchain's own druntime and Phobos sources. It never holds project or application modules.

## Decision

Treat the server's preloaded druntime and Phobos analysis as a precompiled toolchain runtime. Cold measurements may start with a server already running for the measured flags, exactly as Go starts with its standard library compiled. Each cold trial still copies the project source afresh and starts with an empty `DUB_HOME`, so every Flint package and the application compile from source in the measured window.

Reports must also state the first build after the server has exited, in which the build starts the server and compiles without it.

## Alternatives and consequences

- Count the server start inside every cold build. This would measure a toolchain cache that no developer pays twice and that Go's comparator does not pay at all.
- Precompile the Flint framework like Go's standard library. Rejected: the current cold definition requires the framework to compile from source.
- Ship serialized semantic state for Phobos. Not available in DMD; a server provides the same reuse without changing the language or the compiler's semantics.

The server is a separate process tree. A build's process-tree compiler RSS omits the shared server, about 80 MB resident per flag set, and Gate 3 compiler RSS reports must list it separately. The server key includes every semantic flag, so the `-allinst` compiles that the parallel DUB pipeline uses get their own server.

## Acceptance evidence

- The same nine-trial paired comparison reports cold and edited builds with the server running, plus the first build without a server.
- Every package's DMD unit suite gives the same result with the fork as with the upstream toolchain.
- Compiler diagnostics are identical with and without the server.
- A worker refuses requests that could observe preloaded state, as described in `toolchain/README.md`.
