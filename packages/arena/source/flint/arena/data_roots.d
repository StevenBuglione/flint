/++
Importing this module takes the loader's read-only-after-relocation memory (PT_GNU_RELRO) out of the collector's
root ranges at startup, so collections stop scanning vtables, TypeInfo and generated tables that can never point
into the GC heap (performance playbook R-33). druntime registers each D object's writable segment whole; the RELRO
part of it is read-only before any D code runs. Flint Boot imports it.
+/
module flint.arena.data_roots;

@safe:

static import flint.arena.sys.gc.data_roots;

static import flint.arena.sys.gc.static_audit;
static import flint.arena.sys.gc.static_map;

/// Bytes the startup trim took out of the root ranges; zero when the program has no RELRO region to trim.
alias trimmedRootBytes = flint.arena.sys.gc.data_roots.trimmedBytes;
/// What became of the executable's static-data map (docs/spring/phase1/gc.md, section 3c).
alias StaticMapState = flint.arena.sys.gc.static_map.MapState;
/// ditto
alias staticMapState = flint.arena.sys.gc.static_map.staticMapState;
/// Bytes of writable static data the map took out of the roots (or would, in audit mode).
alias staticTrimmedBytes = flint.arena.sys.gc.static_map.staticTrimmedBytes;
/// Whether the static-data audit watcher runs.
alias staticAuditRunning = flint.arena.sys.gc.static_audit.auditing;

// After druntime registered the data segments (rt_init runs module constructors after it initialises the sections
// and the collector), and before the program starts threads.
shared static this()
{
    flint.arena.sys.gc.data_roots.trimReadOnlyRoots();
    flint.arena.sys.gc.static_map.applyStaticMap();
    // Debug and test builds audit the rule "class metadata never owns a GC monitor" in every binary; a flint-built
    // program's map asks for it in its debug and test profiles. FLINT_GC_STATIC_VERIFY=1 or 0 overrides both.
    bool byDefault;
    debug byDefault = true;
    if (flint.arena.sys.gc.static_map.staticMapState() == StaticMapState.audited
            || flint.arena.sys.gc.static_map.auditWanted(byDefault))
        flint.arena.sys.gc.static_audit.startAudit();
}

// Before druntime terminates the collector the watcher asks about addresses.
shared static ~this()
{
    flint.arena.sys.gc.static_audit.stopAudit();
}
