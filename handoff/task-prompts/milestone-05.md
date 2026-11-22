# Milestone 05: Cloud, AI and optional composition adapters

## Shared dispatch contract

Read `AGENTS.md`, `docs/AGENT_D_DIALECT.md`, `docs/ARCHITECTURE_DAG.md`, and the package specs for mq, storage, mail, ai, mcp, template, codec, desktop. In a bootstrapped implementation repository prefix these paths with `handoff/`. Input contracts are in `handoff/contracts/source/`; do not link them as production code.

Assign exclusive package ownership. After an accepted API change, regenerate dependent compile fixtures and rerun both compilers. Every task retains raw command output under `artifacts/tasks/<task-id>/`; failures are actionable output, not a reason to disable a gate.

## M5.1: mq

Inputs: `handoff/specs/tier-6/mq.md`, `policy/packages.json`, `policy/budgets.json`, `packages/mq/dub.sdl` and its direct dependencies (arena, reactor, conc, serde, log).

Work: Wrap librdkafka delivery/consumer lifecycle and implement bounded NATS JetStream flow; generate listener dispatch.

Definition of done: Redelivery and idempotency; rebalance during handler; queue full; drain deadline; commit offsets only after successful handling; no exactly-once claim across external side effects. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :mq --compiler=dmd
dub test :mq --compiler=ldc2
python3 tools/gates.py --package mq --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M5.2: storage

Inputs: `handoff/specs/tier-6/storage.md`, `policy/packages.json`, `policy/budgets.json`, `packages/storage/dub.sdl` and its direct dependencies (arena, http, security, conc).

Work: Implement SigV4 over verified crypto primitives, bounded streaming uploads and multipart cleanup; mail can proceed independently over http/reactor.

Definition of done: Canonicalization vectors; UTF-8/query escaping; clock skew; part retry; failed multipart abort; SMTP STARTTLS required policy; envelope/header injection rejected. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :storage --compiler=dmd
dub test :storage --compiler=ldc2
python3 tools/gates.py --package storage --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M5.3: ai

Inputs: `handoff/specs/tier-7/ai.md`, `policy/packages.json`, `policy/budgets.json`, `packages/ai/dub.sdl` and its direct dependencies (arena, http, serde, conc, validate).

Work: Implement provider-neutral bounded stream events and explicit model/provider configuration, then compile-time schema/tool dispatch.

Definition of done: Split SSE/UTF-8; rate-limit retry budget; cancellation; invalid tool arguments; repeated tool IDs; provider usage absent; no cross-provider silent parameter loss. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :ai --compiler=dmd
dub test :ai --compiler=ldc2
python3 tools/gates.py --package ai --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M5.4: mcp

Inputs: `handoff/specs/tier-7/mcp.md`, `policy/packages.json`, `policy/budgets.json`, `packages/mcp/dub.sdl` and its direct dependencies (arena, http, web, serde, validate, conc).

Work: Implement stdio and 2026-07-28 HTTP as separate transport state machines; isolate the older compatibility mode.

Definition of done: Version/header mismatch; Origin rejection; bounded JSON-RPC framing; stdout cleanliness; cancellation; MRTR retries; schema validation; explicit capability negotiation. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :mcp --compiler=dmd
dub test :mcp --compiler=ldc2
python3 tools/gates.py --package mcp --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M5.5: template

Inputs: `handoff/specs/tier-8/template.md`, `policy/packages.json`, `policy/budgets.json`, `packages/template/dub.sdl` and its direct dependencies (arena, serde).

Work: Implement context-aware escaped HTML rendering with compile-time variable checking; codec proceeds independently over pinned C shims.

Definition of done: HTML/text/attribute/URL context; explicit trusted-HTML wrapper; no dynamic template code; output caps; decompression bomb/ratio/window limits; truncated streams. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :template --compiler=dmd
dub test :template --compiler=ldc2
python3 tools/gates.py --package template --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## M5.6: desktop

Inputs: `handoff/specs/tier-8/desktop.md`, `policy/packages.json`, `policy/budgets.json`, `packages/desktop/dub.sdl` and its direct dependencies (arena, conc, os, wasm-bridge).

Work: Compose SDL3 permissive native profile and explicit OS webview adapters over WASM bridge; package notices and backend capabilities.

Definition of done: Window teardown races; thread-affinity; denied external navigation; bounded JS bridge; platform integration; WebKitGTK excluded from permissive default. The complete package acceptance checklist also applies. Add negative tests for every new trusted boundary and at least one workload-specific monomorphic probe; a successful empty module does not satisfy this task.

Required commands:

```sh
dub test :desktop --compiler=dmd
dub test :desktop --compiler=ldc2
python3 tools/gates.py --package desktop --gate structural
```

For any additional package named in this slice, run the same three commands with that explicit package name before declaring it complete. Small implementation steps may be committed independently after their own tests pass. Full performance certification is accumulated and remains blocked until measured evidence exists.

## Milestone exit

Run affected-package tests through `python3 tools/flint.py test --compiler dmd` and `--compiler ldc2` for all implemented targets. Run quality and the relevant target/sanitizer jobs. Update the milestone checklist with exact source commit, commands and evidence hashes. Do not claim full certification from the structural command.
