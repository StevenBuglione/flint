# Service, protocol and native-shell evidence

Research cut: 2026-11-21. Primary sources only. Numerical package budgets and proposed APIs are design decisions, not upstream benchmarks.

# Critical decisions

- MCP defaults to published revision 2026-07-28 with an isolated 2025-11-25 adapter; modern POST-only stateless behavior must not be mixed with old initialize/session examples.
- Native async is a connection-owner state machine, not proof of zero C allocation. libcurl/nghttp2/libpq callbacks must respect each library's ownership rules.
- D UDAs are compile-time metadata. Advice, transaction, cache and retry wrappers affect registered/generated invocation paths; arbitrary calls are ordinary D calls.
- PostgreSQL /current/ docs identify version 19 at this research cut; Flint's reviewed libpq pin remains an explicit compatible selection in native-lock.json.
- SDL is the default permissive desktop profile. WebKitGTK's LGPL components prevent calling a Linux WebView bundle wholly permissive.
- Embedded SQL hashes are generated and rechecked offline with Python hashlib; CTFE parses imports/metadata and never reimplements cryptography.
- No library contract typecheck is represented as a runtime implementation or an achieved performance target.

# Source ledger

| ID | Primary source | Supported narrow fact |
| --- | --- | --- |
| SVC-001 | [nghttp2 programmer guide](https://nghttp2.org/documentation/programmers-guide.html) | nghttp2 is I/O-agnostic and a session has one owner at a time. |
| SVC-002 | [D parameter attributes](https://dlang.org/spec/function.html) | Function parameters can carry UDAs; scope/return are compiler-checked attributes, not ownership magic. |
| SVC-003 | [curl threading](https://curl.se/libcurl/c/threadsafe.html) | A handle cannot be used concurrently on multiple threads. |
| SVC-004 | [multi-socket action](https://curl.se/libcurl/c/curl_multi_socket_action.html) | Socket and timeout notifications drive asynchronous transfer progress. |
| SVC-005 | [JWT best practices](https://www.rfc-editor.org/rfc/rfc8725.html) | Algorithm, issuer and audience validation must be explicit. |
| SVC-006 | [libsodium password hashing](https://doc.libsodium.org/password_hashing/default_phf) | Use the library password verifier format and high-level functions. |
| SVC-007 | [OTLP specification](https://opentelemetry.io/docs/specs/otlp/) | OTLP/HTTP supports Protobuf JSON and defines signal endpoints/partial success. |
| SVC-008 | [D compile-time attributes](https://dlang.org/spec/attribute.html) | UDA metadata is available to compile-time descriptors. |
| SVC-009 | [gRPC concepts](https://grpc.io/docs/what-is-grpc/core-concepts/) | gRPC supports four call shapes and independent local completion outcomes. |
| SVC-010 | [gRPC flow control](https://grpc.io/docs/guides/flow-control/) | Bounded streams must keep readers making progress to avoid mutual writer stalls. |
| SVC-011 | [protobuf-c](https://github.com/protobuf-c/protobuf-c) | Generated C codec supplies the Protobuf runtime boundary. |
| SVC-012 | [libpq asynchronous processing](https://www.postgresql.org/docs/current/libpq-async.html) | Nonblocking output and complete result draining are separate requirements. |
| SVC-013 | [SQLite WAL](https://www.sqlite.org/wal.html) | WAL concurrency and checkpoint/durability tradeoffs require explicit operational choices. |
| SVC-014 | [PostgreSQL parameters](https://www.postgresql.org/docs/current/libpq-exec.html) | Parameterized query APIs separate data from SQL command text. |
| SVC-015 | [D string import](https://dlang.org/spec/expression.html#import_expressions) | Templates can consume compile-time source resources. |
| SVC-016 | [PostgreSQL explicit locking](https://www.postgresql.org/docs/current/explicit-locking.html) | Database-scoped advisory locks coordinate independent migration processes. |
| SVC-017 | [hiredis](https://github.com/redis/hiredis) | hiredis provides async parsing and length-aware command APIs; its README is the upstream integration source. |
| SVC-018 | [librdkafka overview](https://docs.confluent.io/kafka-clients/librdkafka/current/overview.html) | Manual offset management and delivery callbacks are upstream-supported control points. |
| SVC-019 | [librdkafka configuration](https://docs.confluent.io/platform/current/clients/librdkafka/html/md_CONFIGURATION.html) | Producer idempotence and transaction settings are separate configuration decisions. |
| SVC-020 | [JetStream semantics](https://github.com/nats-io/nats.docs/blob/master/using-nats/jetstream/model_deep_dive.md) | Deduplication and acknowledged acks improve broker delivery guarantees without atomically covering external side effects. |
| SVC-021 | [AWS SigV4 authorization](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-auth-using-authorization-header.html) | Signing mode and payload checksum semantics are explicit protocol choices. |
| SVC-022 | [S3 multipart limits](https://docs.aws.amazon.com/AmazonS3/latest/userguide/qfacts.html) | Multipart part size and count constraints are upstream-defined. |
| SVC-023 | [SigV4 streaming](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-streaming.html) | Chunk signatures are chained; ordinary chunked HTTP is not automatically SigV4 streaming. |
| SVC-024 | [SMTP](https://www.rfc-editor.org/rfc/rfc5321.html) | SMTP replies and final acceptance are protocol-level states. |
| SVC-025 | [SMTP TLS](https://www.rfc-editor.org/rfc/rfc3207.html) | STARTTLS changes protocol state and requires capability renegotiation. |
| SVC-026 | [OpenAI streaming](https://developers.openai.com/api/docs/guides/streaming-responses) | Responses uses typed semantic streaming events. |
| SVC-027 | [Anthropic streaming](https://platform.claude.com/docs/en/build-with-claude/streaming) | Content blocks, incremental tool JSON and cumulative usage require distinct handling. |
| SVC-028 | [Gemini REST streaming](https://colab.research.google.com/github/google-gemini/gemini-api-cookbook/blob/main/quickstarts/rest/Streaming_REST.ipynb/) | streamGenerateContent supports SSE with alt=sse. |
| SVC-029 | [OpenRouter streaming](https://github.com/OpenRouterTeam/docs/blob/main/api_reference/streaming.mdx) | Endpoint-specific terminal and usage events differ. |
| SVC-030 | [Modern transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http) | 2026 revision removes GET/session transport behavior and defines request-scoped responses. |
| SVC-031 | [Modern versioning](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning) | Per-request metadata replaces initialization; dual-era compatibility is explicit. |
| SVC-032 | [Legacy transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports) | Compatibility behavior must remain version-specific. |
| SVC-033 | [D templates](https://dlang.org/spec/template.html) | Template bodies need explicit instantiation for semantic verification. |
| SVC-034 | [Zstandard upstream](https://github.com/facebook/zstd) | Use the maintained C implementation and its documented streaming interfaces. |
| SVC-035 | [zlib manual](https://zlib.net/manual.html) | gzip framing and streaming state are handled by zlib. |
| SVC-036 | [Brotli upstream](https://github.com/google/brotli) | Brotli C encoder/decoder APIs are the native backend. |
| SVC-037 | [libarchive upstream](https://github.com/libarchive/libarchive) | Optional ZIP/tar support wraps the maintained C archive implementation. |
| SVC-038 | [SDL homepage](https://www.libsdl.org/) | SDL3 provides portable C window/input/render interfaces. |
| SVC-039 | [SDL license](https://www.libsdl.org/license.php) | SDL2 and newer use the zlib license. |
| SVC-040 | [WebKitGTK license](https://webkitgtk.org/reference/webkit2gtk/unstable/) | WebKitGTK includes BSD and LGPL-2.1 licensing; it is not wholly permissive. |

## Verification receipts

- verification/service-contracts.json: DMD 2.114 / LDC 1.43 compile-only public-contract and golden REST checks with DIP1000.
- verification/service-c-headers.json: standalone C11 shim header syntax checks, not runtime ABI/link tests.
- scaffold/tests/test_migration_manifest.py: deterministic generation, checksum drift, collisions, module validation, symlink rejection and source protection.
- research/golden-rest-service-sample.d: compiler-checked DI/SQL/serde/validation/controller composition sample.

## Measurement and CI primary sources

- SVC-041: [Oha 1.16.0 protocol and flags](https://github.com/hatoo/oha/blob/v1.16.0/README.md) — Fixed-rate latency correction and output modes are documented by the pinned load generator.
- SVC-042: [Oha 1.16.0 result schema](https://github.com/hatoo/oha/blob/v1.16.0/schema.json) — The pinned JSON schema defines p50/p99/p99.9 latency fields and second-based units.
- SVC-043: [Linux process counters](https://docs.kernel.org/filesystems/proc.html) — Process CPU and RSS/high-water counters have explicit scope and units.
- SVC-044: [GitHub hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) — The hosted-runner table identifies Ubuntu ARM64 and macOS ARM64 labels.
- SVC-045: [GitHub ephemeral runners](https://docs.github.com/en/actions/reference/runners/self-hosted-runners) — Ephemeral runner registration limits jobs per runner; infrastructure must wipe the machine.
- SVC-046: [GitHub runner security](https://docs.github.com/en/actions/reference/security/secure-use) — Self-hosted execution is a trust boundary, not isolation guaranteed by a label.
- SVC-047: [GitHub required ruleset API](https://docs.github.com/en/rest/repos/rules) — Repository rulesets can require named status checks, current-base testing and code-owner review.
- SVC-048: [GitHub environment API](https://docs.github.com/en/rest/deployments/environments) — Environment protection supports required reviewers, prevention of self-review and protected-branch restrictions.
- SVC-049: [GitHub download-artifact release](https://github.com/actions/download-artifact/releases/tag/v8.0.0) — The selected immutable action revision enforces download digest mismatch failure by default.
- SVC-050: [WinFlexBison release](https://github.com/lexxmark/winflexbison/releases/tag/v2.5.25) — The selected host build utility release contains Bison 3.8.2 and Flex 2.6.4.
- SVC-051: [Meson package](https://pypi.org/project/meson/1.12.1/) — The selected Windows Meson build utility release is 1.12.1.

Immutable CI assets also have direct tool receipts: download-artifact v8.0.0 resolves via upstream git ls-remote to `70fc10c6e5e1ce46ad2ea6f2b72d43f7d47b13c3`; the upstream Docker Registry returned Alpine3.22 multiarch index `sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f`; the downloaded WinFlexBison2.5.25 ZIP (1,083,989 bytes) hashed to `8d324b62be33604b2c45ad1dd34ab93d722534448f55a16ca7292de32b6ac135`. These are retrieval/byte-verification facts, not independent publisher-signature attestations.

## Static target proof sources

- SVC-52: [ELF program headers](https://gabi.xinuos.com/elf/07-pheader.html) — ELF program headers identify loadable segments and an optional interpreter.
- SVC-53: [ELF dynamic linking](https://gabi.xinuos.com/elf/08-dynamic.html) — PT_INTERP and active DT_NEEDED entries express dynamic loader/shared-library requirements.
- SVC-54: [GNU readelf](https://sourceware.org/binutils/docs/binutils/readelf.html) — The program/header/dynamic options inspect exact linked ELF artifacts.
