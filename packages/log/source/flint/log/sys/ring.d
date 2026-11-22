module flint.log.sys.ring;

// Module scope imports only declaration types; implementation imports are local.
import flint.arena : Status;
import flint.log.encoding : RecordHeader;
import flint.log.types : Field, Format;

@safe:

private shared ulong lastProducer;
private ulong threadProducer;

package(flint.log) ulong producerIdentity() nothrow @nogc
{
    import core.atomic : atomicOp;

    if (threadProducer == 0)
        threadProducer = atomicOp!"+="(lastProducer, 1UL);
    return threadProducer;
}

/// One bounded shard. Publish releases a whole slot to the single reader, which retires it after delivery.
package(flint.log) struct Ring
{
    private shared ulong owner;
    private shared ulong tail;
    private shared ulong retired;
    private shared bool publishing;
    private RecordHeader[] headers;
    private char[] storage;
    private size_t stride;

    @disable this(this);

    void initialize(size_t slots, size_t stride)
    {
        this.stride = stride;
        headers = new RecordHeader[slots];
        storage = new char[slots * stride];
    }

    bool belongsTo(ulong producer) nothrow @nogc
    {
        import core.atomic : atomicLoad, cas;

        const current = atomicLoad(owner);
        return current == producer || (current == 0 && cas(&owner, 0UL, producer));
    }

    Status publish(RecordHeader meta, scope const(char)[] text, scope const(Field)[] fields, ubyte mask) nothrow @nogc
    {
        import core.atomic : atomicLoad, atomicStore, cas;
        import flint.log.encoding : capture;

        if (!cas(&publishing, false, true))
            return Status.resourceExhausted;
        scope (exit)
            atomicStore(publishing, false);

        const cursor = atomicLoad(tail);
        if (cursor == ulong.max || cursor - atomicLoad(retired) == headers.length)
            return Status.resourceExhausted;

        const slot = cast(size_t)(cursor % headers.length);
        const offset = slot * stride;
        capture(storage[offset .. offset + meta.rawBytes], text, fields, mask);
        headers[slot] = meta;
        atomicStore(tail, cursor + 1);
        return Status.ok;
    }

    ulong published() const nothrow @nogc
    {
        import core.atomic : atomicLoad;

        return atomicLoad(tail);
    }

    ulong delivered() const nothrow @nogc
    {
        import core.atomic : atomicLoad;

        return atomicLoad(retired);
    }

    bool full() const nothrow @nogc
    {
        const head = delivered();
        return published() - head >= headers.length;
    }

    bool ready() const nothrow @nogc
    {
        return published() != delivered();
    }

    Status render(Format format, scope char[] output, ulong sequence, out RecordHeader header) const nothrow @nogc
    {
        import flint.log.encoding : formatRecord;

        const slot = cast(size_t)(delivered() % headers.length);
        header = headers[slot];
        const offset = slot * stride;
        return formatRecord(format, header, storage[offset .. offset + header.rawBytes],
                output[0 .. header.outputBytes], sequence);
    }

    void retire() nothrow @nogc
    {
        import core.atomic : atomicStore;

        atomicStore(retired, delivered() + 1);
    }
}
