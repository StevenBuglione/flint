# flint:mq — Kafka and NATS JetStream messaging with explicit delivery ownership

Research cut: 2026-11-21. This is a normative implementation specification. Public declarations have been compiler-checked; runtime requirements below are acceptance work for the implementation milestones, not claims of an already implemented framework.

## 1. Purpose and parity checklist

- [ ] Kafka via librdkafka; native bounded NATS/JetStream adapter.
- [ ] @KafkaListener/@StreamListener compiled registrations and typed payload conversion through serde.
- [ ] Publish receipts, manual acknowledgement, bounded in-flight work, cancellation and drain.
- [ ] Explicit at-least-once processing baseline; optional broker transactions never imply exactly-once external effects.

## 2. Exact DUB recipe and dependency boundary

Install this recipe at packages/mq/dub.sdl inside the Flint root that declares all subpackages. Module: flint.mq. Direct allowed dependencies: flint:arena, flint:reactor, flint:conc, flint:serde, flint:log.

```sdl
name "mq"
description "Flint mq subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"
dependency "flint:reactor" version="*"
dependency "flint:conc" version="*"
dependency "flint:serde" version="*"
dependency "flint:log" version="*"

configuration "library" {
    targetType "library"
}
configuration "unittest" {
    targetType "library"
    sourcePaths "source" "tests"
    importPaths "source" "tests"
    excludedSourceFiles "tests/betterc.d"
}
```

The source library has no executable main. Native build/link selection follows the central C-FFI matrix. Public imports are explicit; transitive dependency reachability does not authorize undeclared direct imports. No package in this specification may import a higher catalog tier or introduce a cycle.

## 3. Concrete public D contract

The following is the authoritative declaration-only compiler input. It defines the API agents must implement; declaration-only functions are deliberately not linked as a fake working library. The corresponding file is contracts/source/flint/mq.d.

```d
// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.mq;
import flint.arena : Buffer, Error, RequestArena, Result, Text;
import flint.conc : Context;

@safe:
struct KafkaListener
{
    string topic;
    string group;
}

struct StreamListener
{
    string stream;
    string consumer;
}

enum Broker : ubyte
{
    kafka,
    natsJetStream
}

enum AckAction : ubyte
{
    ack,
    retry,
    reject
}

struct Message
{
    Text topic;
    Buffer key;
    Buffer payload;
    long offset;
    int partition;
    ulong deliveryToken;
}

struct QueueOptions
{
    Broker broker;
    string endpoints;
    string clientId;
    uint maxInFlight = 1024;
    size_t maxQueuedBytes = 16 * 1024 * 1024;
    long deliveryTimeoutNanos = 30_000_000_000L;
}

struct PublishReceipt
{
    int partition;
    long offset;
    ulong sequence;
}

alias MessageHandler = AckAction delegate(ref Message message, ref scope RequestArena arena, ref Context context) @safe nothrow @nogc;
struct QueueClient
{
    private ulong slot;
    private ulong generation;
    Error open(QueueOptions options);
    Result!PublishReceipt publish(string topic, scope const(ubyte)[] key, scope const(ubyte)[] payload,
            string deduplicationId, ref Context context) nothrow @nogc;
    Error subscribe(string topic, string consumer, MessageHandler handler);
    Error poll(ref Context context) nothrow @nogc;
    Error drain(ref Context context) nothrow @nogc;
    Error close() nothrow @nogc;
}

Error registerListeners(T)(ref QueueClient client, ref T component);
```

## 4. Internal architecture and observable semantics

QueueClient.open validates endpoints/client identity and preallocates request/receipt rings. Kafka callbacks and polling are isolated from request reactors; a dedicated polling worker drives librdkafka events and sends bounded copied completion records to owner cores. Publish uses owned copies until the delivery callback resolves. Default producer settings include enable.idempotence=true, acks=all and bounded queue bytes/messages. A returned PublishReceipt means the broker acknowledged the record under that policy. Timeout is an ambiguous outcome; do not automatically republish a nonidempotent business operation.

Consumers disable automatic commits and automatic offset storage. DeliveryToken ties topic/partition/offset to an assignment generation. AckAction.ack records processing success; commit only the highest contiguous completed offset plus one within each assigned partition. Out-of-order worker completion cannot skip an unfinished message. retry pauses/reschedules according to bounded redelivery policy; reject routes to a configured dead-letter subject/topic only after that publication succeeds. A rebalance revokes admission, drains or cancels in-flight work, commits only confirmed offsets and invalidates old delivery tokens.

NATS supports INFO/CONNECT, PING/PONG, MSG/HMSG, PUB/HPUB, +OK/-ERR and bounded line/payload framing. Do not parse payloads by line splitting: payload length is authoritative. JetStream uses pull consumers with explicit ack, a bounded batch equal to free local capacity and optional Nats-Msg-Id deduplication. Stream names, subjects and durable consumer names are validated. AckSync is used when the application asks for acknowledged consumption; deduplication windows and broker durability remain explicit limits.

All callbacks receive a per-delivery arena that remains live until the handler completes and its ack decision is accepted by the client. Payloads crossing a thread boundary are copied into owned bounded blocks; no arena handle becomes a Kafka C callback user pointer. maxInFlight=1024 and maxQueuedBytes=16 MiB bound the default producer/consumer memory. Exceeding capacity suspends an admitted fiber or returns resourceExhausted; it never grows an unbounded D associative array.

drain stops new publishes/subscriptions, waits for admitted work, flushes producer receipts and commits only contiguous completed offsets before the Context deadline. close afterward is idempotent. A handler must make side effects idempotent or use an outbox; broker acknowledgement cannot make an arbitrary SQL/email side effect atomic.

### Required implementation layout

- source/flint/mq.d: messaging API and UDAs.
- source/flint/mq/kafka.d: polling worker and partition generations.
- source/flint/mq/nats.d: bounded protocol state machine.
- source/flint/mq/jetstream.d: pull/ack/dedup semantics.
- source/flint/mq/ffi/kafka.d and c/mq.c: librdkafka-only boundary.

## 5. Native boundary, ownership and safety

Use pinned librdkafka C API and contracts/c/mq.h; never reimplement the Kafka protocol. rd_kafka_consumer_poll/rd_kafka_poll run on the polling worker, delivery callbacks do not execute business logic directly, and flush/close respect deadlines. Optional codecs are pinned transitive C dependencies and appear in the SBOM. NATS protocol is implemented only in its documented small transport surface; TLS uses the existing OpenSSL wrapper. SASL mechanisms require their own explicitly licensed build configuration; do not silently pull an LGPL SASL implementation into the permissive default.

All public modules default to @safe. Mark steady-state methods @nogc/nothrow exactly as in the contract; initialization, deliberate full-D worker adapters and shutdown management may allocate where the signature permits. Raw pointers and foreign calls belong only in the package's ffi/sys boundary. Every @trusted function must have an adjacent // SAFETY: comment covering ownership, bounds, lifetime, callback/thread behavior and exception containment. A C callback never unwinds a D exception across the ABI. Cancellation must join or detach owned native work safely before recycling any arena generation.

@nogc proves absence of D GC allocation in checked code, not absence of C malloc, retained C buffers or global GC pauses triggered by other threads. CI counts D allocations/collections and C allocations separately. There is no GC.disable shortcut in a passing production profile. These packages target full native D, not -betterC; dual-target core interfaces are consumed without importing native APIs into WASM.

### Exact native selections

| Lock ID | Version | License selection | Link profile |
| --- | --- | --- | --- |
| librdkafka | 2.16.0 | BSD-2-Clause AND MIT AND Apache-2.0 | static-runtime-library |
| openssl | 3.5.9 | Apache-2.0 | static-runtime-library |
| zlib | 1.4 | Zlib | static-runtime-library |
| zstd | 1.5.7 | BSD-3-Clause | static-runtime-library |

Immutable commit/source IDs, artifact digests, notices and target recipes are authoritative in scaffold/policy/native-lock.json and docs/C_FFI_PINNING_MATRIX.md. A source digest check is not evidence that every target binary was built or audited.

### Flint C shim ABI

This stable Flint-facing header is compiled by the target C compiler against the selected upstream headers. Its opaque pointers are internal; the public D API exposes only checked handles.

```c
/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_MQ_ABI_H
#define FLINT_MQ_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_kafka_client flint_kafka_client;
flint_kafka_client *flint_kafka_new(const char *brokers, const char *client_id);
int flint_kafka_produce(flint_kafka_client *client, const char *topic,
                        const uint8_t *key, size_t key_length,
                        const uint8_t *payload, size_t payload_length,
                        uint64_t token);
int flint_kafka_poll(flint_kafka_client *client, int timeout_ms);
int flint_kafka_commit(flint_kafka_client *client, const char *topic,
                       int32_t partition, int64_t next_offset);
int flint_kafka_flush(flint_kafka_client *client, int timeout_ms);
void flint_kafka_free(flint_kafka_client *client);
#ifdef __cplusplus
}
#endif
#endif
```

### Native preparation before DUB

On the Linux glibc release runner, the exact preparation command is:

```bash
python3 tools/native_build.py --profile mq --target linux-x86_64-glibc --phase build --emit-dub
```

Use --phase plan to inspect resolved commands without claiming a build. The build installs pinned archives and a verified libflint_ffi.a from implemented native shims, then writes a delimited platform-specific lflags block into affected DUB recipes. Installation receipts are cumulative. Cross-target commands replace the target with the exact central matrix target and use its SDK/toolchain. C shim source must exist at the implementation milestone; missing shims must fail the build rather than produce a fake library.

## 6. Numeric compile and size budgets

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

| Measurement | Hard ceiling |
| --- | --- |
| Cold DMD fixture build | 1.50 s |
| Incremental DMD leaf edit | 0.60 s |
| Cold LDC fixture build | 9.00 s |
| Incremental LDC leaf edit | 4.50 s |
| Incremental linked code/data contribution | 1048576 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instances per canonical fixture | 2000 |

These are engineering ceilings from scaffold/policy/packages.json, measured with the fixed runner/toolchain/workload policy. They are not measured achievements of these declarations. Also fail >10% compile-time/compiler-RSS/template growth or >5% binary growth against the approved baseline. The whole selected application includes native libraries in its cap; a smaller wrapper-only delta cannot excuse a larger deployment artifact. A changed profile is a different benchmark identity and cannot be compared as if equivalent.

## 7. Required unit, protocol, fuzz and benchmark acceptance

| Test identity | Passing condition |
| --- | --- |
| kafka_delivery | Successful/failed/timeout delivery reports correlate to exactly one publish token. |
| partition_order | Complete offsets 10,12,11 out of order; commits never advance past the contiguous completed range. |
| rebalance_race | Revoke a partition with active workers; old-generation acks cannot commit into the new assignment. |
| jetstream_redelivery | Lose an ack and verify redelivery; handler idempotency fixture prevents duplicate database effect. |
| nats_parser | Payloads with CRLF, fragmented headers, max-length line/payload and malformed lengths are fuzzed. |
| bounded_queue | Broker outage for ten minutes keeps queued memory ≤16 MiB plus fixed metadata and rejects overload. |
| drain_deadline | Shutdown under in-flight traffic; confirmed receipts are delivered, ambiguous ones are explicitly reported. |
| mq_bench | Measure 256-byte/8-KiB payload throughput and p99 at 1/16 partitions with broker durability settings committed. |

Every runtime test above must be a deterministic D unittest/integration fixture or a versioned external conformance command with a checked result. Run native boundary corpora under AddressSanitizer and the supported LDC sanitizer configuration. Compile-fail tests assert a nonzero compiler exit and a stable diagnostic category. Fuzz seeds include truncated input, maximum lengths, empty values, cancellation and generation reuse. Never mark an unimplemented test as passing or replace it with a declaration-only compile.

### Commands at the implemented monorepo root

```bash
dub test :mq --compiler=dmd
dub test :mq --compiler=ldc2
python3 tools/gates.py --package mq --gate structural
python3 tools/gates.py --gate all --evidence artifacts/current.json --baseline artifacts/base.json
```

The structural gate is useful before runtime implementation. The all gate must fail on absent runtime/baseline evidence; obtaining a real approved first baseline is an explicit milestone task. Task completion requires the package tests and its declared protocol/ownership checks, not merely a passing parse.

## 8. Evidence and design decisions

All links below are primary sources consulted for the 2026-11-21 research cut. The architecture, limits, typed APIs and error policies above are Flint design decisions derived from the stated constraints; upstream documentation does not establish Flint's speed or correctness.

- [librdkafka overview](https://docs.confluent.io/kafka-clients/librdkafka/current/overview.html) — Manual offset management and delivery callbacks are upstream-supported control points.
- [librdkafka configuration](https://docs.confluent.io/platform/current/clients/librdkafka/html/md_CONFIGURATION.html) — Producer idempotence and transaction settings are separate configuration decisions.
- [JetStream semantics](https://github.com/nats-io/nats.docs/blob/master/using-nats/jetstream/model_deep_dive.md) — Deduplication and acknowledged acks improve broker delivery guarantees without atomically covering external side effects.

Related decisions: docs/ARCHITECTURE_DAG.md, docs/AGENT_D_DIALECT.md, docs/C_FFI_PINNING_MATRIX.md and docs/CI_PERFORMANCE_BUDGETS.md. The package graph, public contract and measured-evidence schema must evolve together.
