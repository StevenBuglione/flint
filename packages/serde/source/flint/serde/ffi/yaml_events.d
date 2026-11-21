/// Scoped adapter for the pinned libyaml event shim.
module flint.serde.ffi.yaml_events;

import flint.arena : Error, Status;

@safe:

version (FlintNativeLibyaml)
{
    import core.stdc.stdlib : free, malloc;

    /// Portable event kinds emitted by the native shim.
    enum EventKind : uint
    {
        streamStart = 1,
        streamEnd,
        documentStart,
        documentEnd,
        scalar,
        sequenceStart,
        sequenceEnd,
        mappingStart,
        mappingEnd
    }

    /// Core YAML tags recognized by the restricted data profile.
    enum Tag : uint
    {
        infer,
        quotedText,
        boolean,
        integer,
        number,
        nullValue,
        sequence,
        mapping
    }

    private struct NativeEvent
    {
        const(ubyte)* bytes;
        size_t length;
        size_t offset;
        EventKind kind;
        Tag tag;
    }

    private extern (C) nothrow @nogc
    {
        int flint_yaml_open(const(ubyte)* input, size_t length, void** output) @system;
        int flint_yaml_next(void* owner, NativeEvent* output) @system;
        void flint_yaml_close(void* owner) @system;
    }

    private alias EventVisitor = Error delegate(EventKind, Tag, size_t, scope const(ubyte)[]) @safe nothrow @nogc;
    private alias ScratchVisitor = Error delegate(scope ubyte[]) @safe nothrow @nogc;

    /// Validate events and expose each one during a non-escaping callback.
    // The parser closes before input can expire, including on errors.
    // SAFETY: The scope callback borrows each libyaml event view only before the next read.
    Error visitEvents(scope const(ubyte)[] input, scope EventVisitor visitor) @trusted nothrow @nogc
    {
        void* owner;
        const opened = flint_yaml_open(input.ptr, input.length, &owner);
        if (opened != 0)
            return yamlFailure(opened, 0);
        scope (exit)
            flint_yaml_close(owner);

        for (;;)
        {
            NativeEvent event;
            const status = flint_yaml_next(owner, &event);
            if (status != 0)
                return yamlFailure(status, event.offset);
            if (event.offset > input.length || (event.length != 0 && event.bytes is null))
                return Error(Status.invalidArgument, "invalid YAML event view", input.length);
            scope view = event.length == 0 ? null : event.bytes[0 .. event.length];
            const failure = visitor(event.kind, event.tag, event.offset, view);
            if (failure.code != Status.ok)
                return failure;
            if (event.kind == EventKind.streamEnd)
                return Error.init;
        }
    }

    private Error yamlFailure(int status, size_t offset) nothrow @nogc
    {
        if (status == 2)
            return Error(Status.outOfMemory, "libyaml allocation failed", offset);
        return Error(Status.invalidArgument, "invalid YAML, alias, anchor, or unsupported tag", offset);
    }

    /// Supply temporary native storage without transferring ownership or using the D GC.
    // SAFETY: The scope callback accesses only the allocated range, which free releases before return.
    Error withScratch(size_t length, scope ScratchVisitor visitor) @trusted nothrow @nogc
    {
        if (length == 0)
            return visitor(null);
        auto storage = cast(ubyte*) malloc(length);
        if (storage is null)
            return Error(Status.outOfMemory, "YAML normalization allocation failed");
        scope (exit)
            free(storage);
        return visitor(storage[0 .. length]);
    }
}
