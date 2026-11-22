# flint:wasm-bridge — implementation specification

Catalogue tier 5. Research cut: 2026-11-21. This file specifies implementation work; declarations in contracts are type-checking interfaces, not runtime implementations.

## 1. Purpose and reference parity

Encode bounded DOM/Canvas/WebGPU command batches in BetterC D, exposing a versioned scalar ABI to a small JavaScript host driver.

- [ ] LDC wasm32 core-module build, linear-memory command buffer and per-frame batch flushing.
- [ ] DOM create/text/attribute/append/remove operations with generation-tagged node handles.
- [ ] Canvas fill-rectangle and WebGPU clear-pass baseline commands; no arbitrary JavaScript evaluation.
- [ ] Host validation rejects malformed lengths, stale handles, invalid UTF-8 and unknown opcodes before mutation.

## 2. Exact package recipe and dependency boundary

Write this recipe to `packages/wasm-bridge/dub.sdl` in the implementation repository:

```sdl
name "wasm-bridge"
description "Flint wasm-bridge subpackage"
license "Apache-2.0"
targetType "library"
sourcePaths "source"
importPaths "source"
dflags "-preview=dip1000"
dependency "flint:arena" version="*"

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

Allowed direct Flint dependencies: `flint:arena`. The canonical allowlist is [packages.json](../../scaffold/policy/packages.json). Importing a higher catalogue tier or an unlisted same-tier package fails Gate 2.

## 3. Public D contract

Canonical declaration module: [flint.wasm_bridge](../../contracts/source/flint/wasm_bridge.d). These exact signatures are compiled with DIP1000. Implement the declarations with the semantics below; do not put unresolved declaration stubs into production artifacts.

```d
module flint.wasm_bridge;
import flint.arena : Error, Result;

@safe:
@nogc:
nothrow:
enum abiVersion = 1u;
enum Opcode : ushort
{
    createElement = 1,
    setText = 2,
    setAttribute = 3,
    appendChild = 4,
    remove = 5,
    canvas = 6,
    webgpu = 7
}

enum TagName : ushort
{
    div = 1,
    span = 2,
    button = 3,
    input = 4,
    canvas = 5,
    paragraph = 6
}

struct NodeHandle
{
    uint index;
    uint generation;
}

struct EventRecord
{
    uint nodeIndex;
    uint nodeGeneration;
    uint type;
    int value;
}

alias ByteVisitor = void delegate(scope const(ubyte)[]) @safe nothrow @nogc;
struct CommandBuffer
{
@safe:
nothrow:
@nogc:
    private ubyte[] storage_;
    private uint used_ = 32;
    private uint commandCount_;
    private uint sequence_;
    private uint epoch_ = 1;
    private uint activeBorrows_;
    @disable this(this);
    static Result!CommandBuffer fromStorage(return scope ubyte[] callerStorage, uint sessionEpoch = 1);
    Error createElement(NodeHandle node, TagName tag) scope;
    Error setText(NodeHandle node, scope const(ubyte)[] utf8) scope;
    Error setAttribute(NodeHandle node, scope const(ubyte)[] name, scope const(ubyte)[] value) scope;
    Error appendChild(NodeHandle parent, NodeHandle child) scope;
    Error remove(NodeHandle node) scope;
    Error canvas(NodeHandle node, scope const(ubyte)[] commands) scope;
    Error webgpu(NodeHandle node, scope const(ubyte)[] commands) scope;
    Error visit(scope ByteVisitor visitor) scope const;
    uint usedBytes() scope const;
    uint capacityBytes() scope const;
    void clear() scope;
}
```

## 4. Internal architecture, ownership and safety

1. CommandBuffer borrows caller storage; construction requires at least 32 bytes and no more than 16MiB. `fromStorage(storage, sessionEpoch)` rejects epoch 0 with invalidArgument, stores the supplied nonzero epoch in every header, and initializes an empty 32-byte batch with sequence 0. The default epoch is 1 for a host that explicitly establishes session 1. Methods are @safe nothrow @nogc and return Error on exhaustion without partially appending a record. No allocator, D runtime or JS object reference appears inside the module.
2. All multi-byte fields are explicitly little-endian; never cast a pointer to a packed struct. The host decoder uses DataView and overflow-safe bounds comparisons. SharedArrayBuffer and threads are excluded from ABI v1, so command publication has one writer and one consumer.
3. Node handles contain index plus generation. Index 0 generation 1 is the preexisting mount node. Removed nodes invalidate their descendant handles; reuse increments generation and wraps by retiring the slot permanently. Batch creation order is explicit.
4. A frame is first fully validated into bounded host operations, then applied. The decoder limits the complete batch to 1048576 bytes and 4096 commands even if guest capacity is higher. Node indices range from 0 through 65535; each individual UTF-8 text, attribute-name or attribute-value field is at most 65536 bytes. Tree depth is at most 64 edges below a mounted or detached root, whose depth is 0. Reparent validation includes every descendant of the moved subtree. An invalid batch applies no DOM operations and reports invalidArgument.
5. Only title, aria-label, class, value and data-* attributes are accepted. Attribute names beginning on, and src/href/style/srcdoc are rejected in ABI v1. Text uses textContent, never innerHTML. Detached node/tree construction is allowed in the owning host registry; an already mounted subtree cannot be reparented beneath a detached parent or another host root.
6. Host refreshes its ArrayBuffer/DataView after any guest call that could grow memory. At the start of a new frame, the guest calls `clear()` once, which empties records and advances the sequence exactly once modulo 2^32 without changing the session epoch. Encoding, visiting or flushing the batch does not advance it again. The guest flushes its signals and returns; the host validates and applies that batch before the next guest frame. The counter host makes at most one such call per visible requestAnimationFrame when an initial render or pending increment requires it. Page-hidden mode pauses animation work; pending input remains bounded.

### Concrete implementation files

- `packages/wasm-bridge/source/flint/wasm_bridge/package.d`: public declarations, UDA definitions and entry points.
- `packages/wasm-bridge/source/flint/wasm_bridge/internal.d`: shared non-template state machines and checked arithmetic.
- `packages/wasm-bridge/tests/contract_tests.d`: behavioral tests identified in section 6.
- `packages/wasm-bridge/tests/fuzz/`: deterministic seed corpus and bounded fuzz entry points; no fuzz data downloaded at test time.

The public surface defaults to `@safe`. Pointer arithmetic and native handle conversions are confined to those reviewed boundaries. Every implementation path in this contract is also `nothrow @nogc`; no D runtime/GC, class, dynamic array append, associative array, exception, TypeInfo, or Phobos runtime dependency is permitted.

## 5. Measured budget contract

**Per-package size definition:** the byte ceiling bounds framework overhead over an exercised baseline with the same direct Flint dependencies and the same selected native-provider workload. When a C/Rust provider is selected, the baseline performs that operation directly through the pinned upstream C ABI, without importing this Flint package; it must retain the same provider features and native work. An ABI-only adapter may be shared, but moving Flint validation, ownership or business logic into the baseline is prohibited. Adding an unused archive to a link line is not equivalent work. Preserve both complete stripped binary sizes and SHA256 values; the capped metric is `max(0, O3_feature - O3_baseline, Oz_feature - Oz_baseline)`. A valid zero delta is allowed. The full feature size remains visible and is not the wrapper delta. The fixed application caps count every retained native byte. Freeze both probe sources before establishing a baseline; no padding, unrelated feature retention or whole-archive tricks may inflate the reference. See the package's `bench/PROBE_CONTRACT.md` and the central producer protocol.

These are engineering ceilings, not measured performance claims. Use the fixed runner and sampling procedure in [CI performance budgets](../../docs/CI_PERFORMANCE_BUDGETS.md). Per-package timing excludes rebuilding dependencies; whole-application gates include the selected closure.

| Measurement | Ceiling |
| --- | --- |
| DMD cold / incremental package build | 0.80s / 0.60s |
| LDC cold / incremental package build | 4.80s / 2.40s |
| Incremental stripped linked bytes | 49152 bytes |
| Compiler peak RSS | 536870912 bytes |
| Template instantiations in the package fixture | 2000 |

Compile regression >10% or binary growth >5% fails independently of these hard ceilings. Native dependencies and final shared-library closure are reported separately and counted in the application deployment metric; they are never hidden by quoting only D wrapper size.

Required benchmark: Measure 1, 100 and 4096 operations with native and wasm32 encoders. Host tests compare DOM mutation counts with command counts. Record raw and deterministic gzip size of the core module; the complete bench-wasm retains the 100000-byte gzip hard cap.

## 6. Acceptance, edge cases and required tests

| Test ID | Stimulus | Required result |
| --- | --- | --- |
| BRIDGE-01 | Batch at exact capacity and one byte beyond | Exact fit succeeds; overflow is resourceExhausted and leaves prior batch unchanged. |
| BRIDGE-02 | Malformed record length, integer wrap, unknown opcode or invalid UTF-8 | Whole batch rejected before any DOM mutation. |
| BRIDGE-03 | Stale generation, duplicate create and cross-root parent | InvalidArgument/conflict; no access to unrelated page nodes. |
| BRIDGE-04 | Text includes <script>, quoted event handler and Unicode | Rendered as text; no script or HTML interpretation. |
| BRIDGE-05 | memory.grow between frames | Host recreates views and renders correctly; old detached views are never reused. |
| BRIDGE-06 | WebGPU absent, invalid RGBA, oversized Canvas geometry | unsupported for unavailable GPU, invalidArgument for malformed commands. |
| BRIDGE-07 | Native D and wasm32 serialize the same command list | Byte-for-byte identical little-endian fixtures. |
| BRIDGE-08 | Epoch 0, wrong active epoch, or an unsolicited larger epoch | Reject before mutation; only an explicit host session reset changes the accepted epoch. |
| BRIDGE-09 | Sequence duplicate, reverse order, half-range jump, or wrap from 0xffffffff to 0 | Reject serial differences 0 or >=0x80000000; accept a forward difference of 1..0x7fffffff, including wrap. clear advances exactly once. |
| BRIDGE-10 | Detached tree creation, mounted-to-detached reparent, or reparented subtree exceeding depth 64 | Detached construction succeeds; invalid reparenting rejects the entire batch. Include a deep descendant that a parent-only check would miss. |
| BRIDGE-11 | 65536-byte UTF-8 field, 65537-byte field, node index 65535 and 65536 | Accept in-range valid input subject to batch capacity; reject oversized fields and out-of-range indices. |
| BRIDGE-12 | Rectangle at fixed 300-by-150 canvas edges and one pixel beyond | Exact-fit and zero-area in-range rectangles succeed; outside geometry rejects before mutation. |

The following is a real D test/usage fixture to place in the package tests. Runtime assertions become passing only after the specified implementation exists:

```d
import flint.wasm_bridge : CommandBuffer, NodeHandle;
import flint.arena : Status;
unittest {
    ubyte[256] memory;
    auto buffer = CommandBuffer.fromStorage(memory[], 7);
    assert(buffer.ok());
    immutable ubyte[] text = [104, 105];
    assert(buffer.value.setText(NodeHandle(0, 1), text).code == Status.ok);
    assert(buffer.value.usedBytes() > 32);
}
```

For parser/codec boundaries fuzz every length from 0 through 256, then 1KiB/1MiB boundary seeds; reject overflows before allocation. Run a 60-second ASan smoke on every PR and a 30-minute corpus job nightly. A platform-specific test is required on the platform that owns the native boundary; a Linux compile-only job does not count as a Windows runtime pass.

From the implementation repository root:

```sh
dub test :wasm-bridge --compiler=dmd
dub test :wasm-bridge --compiler=ldc2
python3 tools/gates.py --package wasm-bridge --gate structural
```

Do not mark this package complete until behavioral fixtures, compile-fail safety fixtures, the package budget fixture and all applicable native/WASM jobs pass. A declaration-only typecheck is API verification, not a package acceptance result.

## 7. Primary sources

- https://dlang.org/spec/betterc.html
- https://www.w3.org/TR/wasm-js-api-2/
- https://gpuweb.github.io/gpuweb/

## 8. ABI v1 byte specification

Every integer and float uses little-endian encoding. `totalBytes` includes the 32-byte batch header and all padding. Record sizes include their 16-byte header, payload and zero padding to a multiple of eight. Unknown flags or nonzero reserved/padding bytes reject the batch. No unaligned native struct dereferences are used.

| Batch offset | Type | Required value |
| --- | --- | --- |
| 0 | u32 | Magic `0x544e4c46` (bytes FLNT) |
| 4 | u16 | ABI version 1 |
| 6 | u16 | Flags 0 |
| 8 | u32 | Total bytes, at least 32 and at most host limit 1048576 |
| 12 | u32 | Command count, at most 4096 |
| 16 | u32 | Frame sequence modulo 2^32; after the first accepted batch require a forward serial difference of 1..0x7fffffff |
| 20 | u32 | Nonzero host session epoch; must equal the explicitly established active mount epoch |
| 24 | u32 | Reserved 0 |
| 28 | u32 | Reserved 0 |

The host establishes a nonzero session epoch before accepting any batch and supplies that same value to `CommandBuffer.fromStorage`. Header epoch equality is mandatory on the first and every subsequent batch; a numerically larger epoch does not reset replay protection. The first valid batch in a newly established host session may contain any u32 sequence. Thereafter compute `delta = (incomingSequence - lastAcceptedSequence) mod 2^32` and accept only `1 <= delta <= 0x7fffffff`. Difference 0 is a duplicate; differences 0x80000000 through 0xffffffff are ambiguous or backward and reject. Thus 0xffffffff followed by 0 is a valid forward step. The host records the last sequence only after a batch succeeds.

`clear()` resets used bytes to 32 and command count to 0, advances the sequence once modulo 2^32, and writes the same epoch into the new header, including for an empty frame. A new session requires an explicit host operation that selects a new nonzero epoch, clears/remounts the owned DOM subtree and discards its node registry, generations and previous sequence. Construct a new guest command buffer with the matching epoch; receipt of a batch alone cannot perform this reset.

A record header is opcode:u16 at offset0, flags:u16=0 at2, recordBytes:u32 at4, nodeIndex:u32 at8 and nodeGeneration:u32 at12. Before any arithmetic, require `recordBytes >= 16`, `recordBytes % 8 == 0`, and `recordBytes <= totalBytes - cursor`. After parsing exactly commandCount records, cursor must equal totalBytes.

| Opcode | Name | Payload starting at record+16 |
| --- | --- | --- |
| 1 | createElement | tag:u16, reserved:u16=0, zero padding; tag1 div,2 span,3 button,4 input,5 canvas,6 p |
| 2 | setText | byteLength:u32, UTF-8 bytes, zero padding |
| 3 | setAttribute | nameBytes:u32,valueBytes:u32,name UTF-8,value UTF-8,zero padding |
| 4 | appendChild | childIndex:u32,childGeneration:u32; record handle is parent |
| 5 | remove | No payload; record size16 |
| 6 | canvas | Exactly24 payload bytes: subopcode:u32=1,x:i32,y:i32,width:u32,height:u32,rgba:u32 |
| 7 | webgpu | Exactly20 payload bytes plus four zero padding bytes: subopcode:u32=1,r:f32,g:f32,b:f32,a:f32 |

Canvas baseline subopcode1 fills a rectangle. Every canvas created by ABI v1 has a fixed backing surface of 300 by 150 pixels; the host owns these dimensions, and v1 has no resize opcode or permitted width/height attribute. Require `0 <= x <= 300`, `0 <= y <= 150`, `width <= 300 - x` and `height <= 150 - y` before drawing. This subtraction-based check rejects coordinate addition overflow and rectangles outside the surface; an in-range zero-area rectangle is valid. Width/height also remain within the general 16384 dimension limit. rgba uses red in bits31..24, green23..16, blue15..8 and alpha7..0. GPU baseline subopcode1 clears this canvas surface in a WebGPU render pass; each component must be finite and in [0,1]. Device absence returns unsupported. These are concrete minimum operations; a later expanded graphics or resize ABI requires a version increment and new validation fixtures.

Host exports to the app a mount handle `(0,1)` plus the agreed nonzero session epoch. A valid create allocates the requested unused handle, using the host registry's next generation. The registry has 65536 slots, including mount index 0; indices outside 0..65535 reject. Operations in one batch are validated against a shadow registry in order, so a newly created node may be appended and updated in that batch. Detached nodes and detached tree assembly are permitted. Once a subtree is mounted, moving it beneath a detached parent is forbidden; references to another host root are also forbidden. A detached subtree may be attached to the mount or to an already mounted descendant. Remove on the mount node is forbidden. Cycles and any reparenting that places a descendant beyond depth 64 reject the complete batch; depth counts edges, with the mount and each detached root at depth 0. The depth check covers the complete moved subtree. Each UTF-8 field is bounded to 65536 bytes independently of the 1048576-byte/4096-command batch limits.

The small golden counter application exports scalar functions `flint_init(uint sessionEpoch)`, `flint_tick(uint delta)`, `flint_buffer_ptr()` and `flint_buffer_len()` from its reviewed WASM boundary module. Init and tick return a u32 Status; pointer/length return a u32 linear-memory offset and byte count. Init accepts the host-established nonzero epoch, initializes the persistent graph/buffer and rejects repeated initialization with conflict. Tick rejects calls before successful initialization and deltas above 1024 with invalidArgument; otherwise it clears one frame, adds the bounded delta with checked signed-integer overflow, and flushes text observers. The first tick with delta 0 emits the initial value; a later unchanged value emits an empty batch with an advanced sequence. The host aggregates at most 1024 counter increments per pending frame and applies each resulting batch once. Pointer/length exports are consumed only after successful initialization/tick, with fresh memory views. These export names and the counter aggregation are application glue rather than additional members of this library module. `EventRecord` remains a scalar node/generation/type/value data record; this counter example does not define a general event-ingress export, text-input buffer, or implicit resize command.
