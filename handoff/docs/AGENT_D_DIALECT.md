# Agent D: canonical Flint application dialect

This document is normative for generated and handwritten Flint code. It fixes a small, teachable D style while leaving bounded metaprogramming inside framework packages. Read the exact compiler/tool versions and flags in the research report; do not silently accept a different language edition or disable checks to make a task pass.

## 1. Compilation and module shape

Every application and public framework module begins with an explicit module declaration, selective imports, and `@safe:`. Name modules with lowercase identifiers; map hyphenated DUB package names to underscore module names (`flint:wasm-bridge` → `flint.wasm_bridge`). Avoid a flat `flint/serde.d` when there are `flint.serde.*` submodules: use `flint/serde/package.d`.

Always compile Flint code with `-preview=dip1000` on both pinned DMD and LDC. Keep bounds checks enabled in every `@safe` function, including release. `-boundscheck=off`, disabling DIP1000, or adding an unsafe cast to silence a lifetime error is not an agent workaround. A compiler upgrade is a dedicated change with all positive and negative probes rerun.

Use selective imports (`import flint.log : Logger, LogOptions;`). Application modules may import public Flint modules and the specifically approved standard modules in the policy. Importing an umbrella module to save typing is prohibited. No application import of `flint.*.internal`, `.sys` or `.ffi`. Pure formatting, time conversion, argument handling and file access run in the appropriate CLI/startup/worker boundary; they do not slip into hot handlers through a helper.

## 2. Data, services and polymorphism

Use structs for DTOs, configuration and value objects. Use final classes when service identity or runtime interface implementation is required. Use interfaces only for a real substitution boundary; do not create an interface for each small helper. Prefer constructor injection. No field injection, service locator, mutable global registry or reflection-scanned service discovery.

The following declaration is the standard owned application DTO style. Owned strings are fine in startup/worker code. The corresponding hot DTO replaces string with arena-backed Text.

```d
module example.user_types;
import flint.serde : JsonName;
import flint.validate : Min, NotBlank;
import flint.arena : Text;
@safe:
struct User
{
    @Min(1) ulong id;
    @JsonName("display_name") @NotBlank string displayName;
}
struct HotUser
{
    @Min(1) ulong id;
    @JsonName("display_name") @NotBlank Text displayName;
}
```

Empty UDAs use `@Service`, `@Singleton`, `@Valid`, etc. Parameterized UDAs use a struct constructor, such as `@JsonName("display_name")`. UDAs do not execute method interception by themselves. A registered framework binder must inspect the attribute and generate the intended wrapper. Annotating an arbitrary method does not automatically add transactions, retries, authorization or scheduling.

Declare concrete public parameter/return types. Allow local `auto` only when its initializer makes the type obvious. Do not expose `auto` return inference in published contracts. Use `enum` for compile-time constants, and ordinary immutable/const values for runtime state. Avoid `alias this`, implicit operator conversions, postblit-dependent resource ownership, overloaded comma operators and custom allocator hooks in application code.

## 3. Error and cancellation rules

Expected operational failures return `Error` or `Result!T`. Success is `error.code == Status.ok`; a default Result is therefore successful only when its value's default is meaningful to that API. Functions returning optional values document how `notFound` differs from an empty value. Error.message on the hot path is a static immutable string. Error.offset is a byte offset for parse/input errors or size_t.max when no input location applies; it is never an encoded pointer.

Use `Context` explicitly on cancellable operations and propagate its earliest monotonic deadline. Never catch a cancellation and retry indefinitely. Exceptions are allowed at startup/worker boundaries where the signature permits them. Convert expected failures at those boundaries; do not catch all Throwable values and continue after an invariant failure. A nothrow function may still terminate on an invariant failure, so nothrow is not an uptime guarantee.

## 4. The hot-path contract

The native hot profile is `@safe nothrow @nogc`. This profile bans GC allocation, implicit closure allocation and calls without the required attributes. It also uses bounded buffers, per-core ownership and explicit backpressure; the language attributes alone do not provide those latter guarantees.

Inside a hot function, do not use `new`, dynamic array append/resize/concatenation, associative arrays, heap-escaping delegates, formatting that allocates, regex compilation, lazy module initialization or exceptions. Do not place a forbidden call under `debug` to exploit language exceptions to attribute checking. Precompute tables and construct services/fibers/pools before admitting requests. An FFI function declared @nogc may still malloc or block: review the pinned C call and benchmark it separately.

@nogc is a local allocation contract. It does not stop another thread from starting a process-wide D GC collection, and it says nothing about C malloc, OS pages or retained memory. The CI gate measures per-thread allocation deltas across synchronized request phases and process collection counts across the same barrier. A periodic GC.collect timer is not a safe substitute for an allocation policy. Do not disable GC indefinitely while allowing unbounded ordinary D allocation.

## 5. Region ownership and lifetime

RequestArena borrows backing storage and cannot outlive it. Use a scope local for stack-backed arenas. Arena APIs accept `ref scope RequestArena`; instance methods have `scope` on their implicit this. These annotations were required by actual DMD/LDC compile probes, not just stylistic preference.

A Buffer is an owner/epoch/offset/length handle, not a raw pointer. RequestArena.read/write pass a scope slice only during a scope callback. Reset is rejected while a callback is active and invalidates all prior handles by advancing the epoch. Negative compiler probes reject callback-slice escape and returning an arena backed by a local array. Runtime probes additionally test stale handles, cross-arena use and reentrant reset.

```d
module example.request_scratch;
import flint.arena : RequestArena, Status;
@safe:
Status fillScratch() nothrow @nogc
{
    ubyte[4096] backing;
    scope RequestArena arena = RequestArena(backing[]);
    auto block = arena.allocate(128, 16);
    if (!block.ok())
        return block.error.code;
    return arena.write(block.value,
        (scope ubyte[] bytes) @safe nothrow @nogc
        {
            bytes[] = 0;
        });
}
```

A private field alone does not disable D's synthesized aggregate construction. Opaque handle structs must define an explicit private constructor, reject `.init`, and validate fields on every access anyway. Do not treat an application-level handle as an authorization token.

Never store a GC pointer/class/interface/delegate in a request arena or a raw cross-thread queue. To retain data after the request, copy into an owned destination before resetting the arena. GC-managed references retained by C callbacks require an explicit registered root/handle adapter: create on the owner thread, register before publication, wait for the final callback, unregister, then free. GC.addRange marks a foreign region for scanning; it does not itself turn that foreign region into owned GC storage or prove callback lifetime. Root registration is native-only and absent from the BetterC core.

## 6. Threads, fibers and task context

Flint pins fibers to their owner loop. D's Fiber documentation permits moving a suspended fiber; Flint intentionally disallows it to make TLS, socket, arena and request ownership deterministic. D thread-local state is not fiber-local state. Every yield/resume installs/restores the appropriate task context, or code passes LogContext explicitly.

Send only validated transfer values or retained owned-buffer IDs through a channel. No stack pointer, borrowed slice, RequestArena Buffer or closure capturing a request crosses threads. Worker input is copied before submit returns; output has explicit ownership until joined/retired. Queue-full errors propagate to callers instead of running blocking work inline on the reactor. Cooperatively cancelled C calls may continue running; the completion owns its resources until it retires.

## 7. BetterC subset

The following core is shared by native full-D and browser builds: arena handles/arithmetic, JSON/TOML scanning/writing, validation descriptors, WASM command buffers and signals. Allowed constructs are primitives, enums, structs, fixed arrays, borrowed slices, checked indexing, templates/CTFE, UDAs, static foreach, scope cleanup and explicit C ABI entrypoints. Slices are allowed; a runtime-resized D array is not.

No classes/interfaces, associative arrays, TypeInfo/ModuleInfo dependence, GC allocation, D exceptions, built-in D threading, synchronized blocks, TLS-dependent state or static module constructors/destructors enter that core. Do not import ordinary Phobos implementation code on the assumption that it is BetterC-compatible. Only the minimal compiler-known/core declarations proven by the link probes are allowed. The D specification explicitly cautions that a successful import does not establish usable BetterC runtime behavior.

Core and adapters share code without preprocessor-copy forks. Use distinct modules for native owned-string deserialization, YAML C integration, page allocation and host callbacks. The WASM fixture imports the core explicitly and builds only those imported modules; it must not compile a whole native source tree indiscriminately. Explicit C imports and exports define every browser ABI symbol. WASM memory views must be refreshed in JS after memory.grow; copying a raw D struct layout into a browser protocol is prohibited.

## 8. Metaprogramming and compile-time budgets

Applications may instantiate public APIs such as AppContext!(...), CrudRepository!(...), encodeJson!T and Mock!Contract. Heavy implementation-level templates, __traits, static foreach over symbols and string mixins belong only to approved framework internals (DI/serde/web/data/CLI/test/validation generators). An application author does not write code-generation loops to recreate framework behavior.

Generator input lists are explicit and bounded: DI 128 beans/512 edges; serializers 128 fields per DTO and depth 64; validation patterns 256 NFA states; test mocks 64 methods in the performance fixture. Template recursion is replaced by iterative CTFE or generated tables. No scan of all members of arbitrary imported modules. No generated import statements: import policy cannot safely audit code that manufactures module names. Generated code uses fully qualified symbols already explicitly imported.

Never import std.regex into core. Avoid std.all, package-wide Phobos umbrella imports and formatting-heavy compile-time error paths. Cache a descriptor once per type rather than rebuilding it in every route/field operation. Release optimization is not enabled in the DMD edit loop. Compiler traces, template counts and RSS are budget evidence, not anecdotal claims that code looks simple.

## 9. Unsafe boundary review

Every @trusted function must carry an adjacent `// SAFETY:` explanation stating caller preconditions, ownership, bounds/alignment, threading and lifetime proof. Keep it limited to one foreign operation or one clearly bounded conversion. A comment is necessary but is not proof: the compiler tests, boundary tests, fuzz corpus and sanitizer jobs are also required.

Allowed unsafe locations are explicit modules in `ffi/`, `sys/`, arena and reactor boundaries, as listed by policy; they are not arbitrary modules whose path happens to contain those words. Public FFI declarations are @system, with safe checked wrappers. Never mark an entire large module @trusted or use a trusted lambda in business logic. Do not cast away shared, const, immutable, scope or a function's safety/GC attributes to get a clean build.

A boundary change is complete only when it has its negative misuse test, success/error-path tests, allocation/lifetime instrumentation and sanitizer evidence on the supported platform. LDC's supported sanitizer set must be queried: the pinned LDC rejects `undefined`, so address sanitizer is used for D and UBSan for C shims via Clang, with a separate uninstrumented interoperability test. No CI file may pretend an unsupported compiler flag is a passing gate.

## 10. Reviewable agent output

Each slice includes the exact affected module list, tests and compiler commands, observed output, and a link to the relevant spec/ADR. State whether a result is syntax-checked, linked, behavior-tested or benchmarked. Never replace an implementation with a declaration/no-op and call the runtime test complete. Additions to public APIs must update contracts, specs, golden usage and negative fixtures together. Performance baselines are data with provenance; missing data blocks release.

## Primary references

- [D function attributes and scope](https://dlang.org/spec/function.html).
- [BetterC specification](https://dlang.org/spec/betterc.html).
- [Memory safety specification](https://dlang.org/spec/memory-safe-d.html).
- [GC API](https://dlang.org/library/core/memory/gc.html).
- [Fiber contract](https://dlang.org/library/core/thread/fiber/fiber.html).
- [UDA specification](https://dlang.org/spec/attribute.html#uda).

Accessed 2026-11-21. The limits and style rules here are Flint design choices; source-backed language facts and actual compiler receipts are separated in the research evidence.
