/++
The static-data audit: the runtime half of the rule "class metadata never owns a GC monitor"
(docs/spring/phase1/gc.md, section 3c). In debug and test builds (and with `FLINT_GC_STATIC_VERIFY=1`), a watcher
checks, every few milliseconds and so after every collection:
$(UL
    $(LI every ClassInfo's monitor word, from ModuleInfo's class lists, in every binary;)
    $(LI every word the executable's static-data map drops from the roots, when it has one (flint.arena.sys.gc.static_map).)
)
A word that points into the GC heap aborts the program with the class's name, or the word's address. In audit mode
nothing is trimmed, so the object stays alive until the check sees it.

The watcher is a low-level thread: druntime neither signals nor scans it, and it touches no GC memory. It reads
words and asks the collector, under its lock, whether a value is a live GC block.
+/
module flint.arena.sys.gc.static_audit;

import core.atomic : atomicLoad, atomicStore;
import core.thread.types : ThreadID;
import flint.arena.sys.gc.static_map : Span, auditedSpans, executableImage;

@safe:

/// The classes known through ModuleInfo, as their ClassInfo objects' addresses (malloc'd, process lifetime).
private __gshared const(void)** classes;
private __gshared size_t classCount;
private __gshared ThreadID watcher;
private __gshared bool watching;
private shared bool stopping;
/// Tests that construct a violation on purpose pause the watcher around it.
private shared bool suspended;

/// What the audit found wrong, if anything.
struct Violation
{
    /// The class whose monitor points into the GC heap; null for a dropped word outside class metadata.
    const(char)[] className;
    /// The offending word's address.
    size_t address;
    /// Its value: an address in the GC heap.
    size_t value;
}

/// Collect the class list and start the watcher. Called once from a module constructor.
// SAFETY: The watcher's delegate context is a __gshared Runner; the thread reads only this module's state.
@trusted void startAudit() nothrow
{
    import core.thread.osthread : createLowLevelThread;

    if (watching || !collectClasses())
        return;
    watcher = createLowLevelThread(&runner.run);
    watching = watcher != ThreadID.init;
}

/// The ClassInfo objects of every module, once.
// SAFETY: ModuleInfo's class lists are static data for the program's lifetime; their addresses are copied into a
// malloc'd array owned by this module.
private @trusted bool collectClasses() nothrow
{
    import core.stdc.stdlib : malloc;

    if (classes !is null)
        return true;
    size_t count;
    try
    {
        foreach (m; ModuleInfo)
            if (m !is null)
                count += m.localClasses.length;
        classes = cast(const(void)**) malloc((count + 1) * (void*).sizeof);
        if (classes is null)
            return false;
        foreach (m; ModuleInfo)
            if (m !is null)
                foreach (c; m.localClasses)
                    if (c !is null && classCount < count)
                        classes[classCount++] = cast(const(void)*) c;
    }
    catch (Exception)
    {
        // ModuleInfo's iteration is not declared nothrow, but it walks a fixed table once constructors have run.
    }
    return classes !is null;
}

/// Stop and join the watcher, before druntime shuts the collector down.
// SAFETY: Joins only the thread startAudit started, once, from the module destructor.
@trusted void stopAudit() nothrow @nogc
{
    import core.thread.osthread : joinLowLevelThread;

    if (!watching)
        return;
    atomicStore(stopping, true);
    joinLowLevelThread(watcher);
    watching = false;
}

/// Whether the watcher runs.
// SAFETY: Written only by startAudit and stopAudit, from module constructors and destructors.
@trusted bool auditing() nothrow @nogc
{
    return watching;
}

/// Pause or resume the watcher (tests that build a violation on purpose).
void suspendAudit(bool pause) nothrow @nogc
{
    atomicStore(suspended, pause);
}

/// The watcher's entry, as a delegate whose context is static data, not a GC closure.
private struct Runner
{
    void run() nothrow
    {
        while (!atomicLoad(stopping))
        {
            pause();
            if (atomicLoad(suspended))
                continue;
            const found = findViolation();
            if (found.address != 0)
                report(found);
        }
    }
}

private __gshared Runner runner;

// SAFETY: nanosleep on a local timespec.
private @trusted void pause() nothrow @nogc
{
    import core.sys.posix.time : nanosleep, timespec;

    timespec delay = timespec(0, 5_000_000);
    nanosleep(&delay, null);
}

/// The first violation of the rule, or `Violation.init`.
// SAFETY: Reads the monitor word of each ClassInfo (the second word of the object, druntime's layout) and the words
// of the audited spans: all static data mapped for the program's lifetime. GC.addrOf takes the collector's lock.
@trusted Violation findViolation() nothrow
{
    foreach (c; classes[0 .. classCount])
    {
        const monitor = (cast(const(size_t)*) c)[1];
        if (inHeap(monitor))
            return Violation((cast(const TypeInfo_Class) c).name, cast(size_t) c + size_t.sizeof, monitor);
    }
    foreach (span; auditedSpans())
    {
        for (size_t at = cast(size_t)((span.begin + 7) & ~7UL); at + 8 <= span.end; at += 8)
        {
            const value = *cast(const(size_t)*) at;
            if (inHeap(value))
                return Violation(classAt(at), at, value);
        }
    }
    return Violation.init;
}

// SAFETY: Only asks the collector about the value; it is never dereferenced.
private @trusted bool inHeap(size_t value) nothrow
{
    import core.memory : GC;

    // Most static words are zero, small integers, or addresses inside the executable: none is a GC block.
    const image = executableImage();
    if (value < 0x10000 || value >> 47 != 0 || (value >= image.begin && value < image.end))
        return false;
    return GC.addrOf(cast(void*) value) !is null;
}

/// The name of the class whose ClassInfo object contains `address`, if one does.
// SAFETY: Reads ClassInfo objects through the static list; their size is TypeInfo_Class's instance size.
private @trusted const(char)[] classAt(size_t address) nothrow @nogc
{
    enum size = __traits(classInstanceSize, TypeInfo_Class);
    foreach (c; classes[0 .. classCount])
        if (address >= cast(size_t) c && address < cast(size_t) c + size)
            return (cast(const TypeInfo_Class) c).name;
    return null;
}

/// Abort with the violation, as an assertion would: the program broke the rule and its next collection may free an
/// object only class metadata references.
// SAFETY: Writes a bounded message to stderr with write(2) and aborts; reads only the violation's fields.
private @trusted void report(const Violation found) nothrow @nogc
{
    import core.stdc.stdlib : abort;
    import core.sys.posix.unistd : write;

    void put(scope const(char)[] text)
    {
        write(2, text.ptr, text.length);
    }

    put("Flint GC static-data audit: ");
    if (found.className.length != 0)
    {
        put("class metadata of ");
        put(found.className);
        put(" owns a GC monitor. Class metadata must never own a GC monitor: give the lock its own `new Mutex()`");
        put(" instead of `new Mutex(typeid(...))` or setSameMutex on a TypeInfo (docs/spring/phase1/gc.md, 3c).\n");
    }
    else
    {
        put("a static word the root map drops points into the GC heap; run with FLINT_GC_STATIC_TRIM=0 and report");
        put(" it (docs/spring/phase1/gc.md, 3c).\n");
    }
    abort();
}

version (unittest)
{
    private final class Probe
    {
    }
}

@("the audit names a class whose metadata owns a GC monitor, and is clean again once the monitor is gone")
@system unittest
{
    import core.sync.mutex : Mutex;

    assert(collectClasses());
    suspendAudit(true);
    scope (exit)
        suspendAudit(false);
    assert(findViolation().address == 0, "the test binary already breaks the rule");
    auto info = typeid(Probe);
    auto lock = new Mutex(info); // flint: allow-class-monitor (the audit's negative test: it must abort on this)
    const found = findViolation();
    assert(found.className == info.name, "the audit did not name the class that owns a GC monitor");
    assert(found.value != 0 && lock !is null);
    (cast(void**) cast(void*) info)[1] = null; // the monitor goes back before the watcher resumes
    assert(findViolation().address == 0);
}
