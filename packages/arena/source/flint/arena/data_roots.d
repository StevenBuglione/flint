/++
Importing this module takes the loader's read-only-after-relocation memory (PT_GNU_RELRO) out of the collector's
root ranges at startup, so collections stop scanning vtables, TypeInfo and generated tables that can never point
into the GC heap (performance playbook R-33). druntime registers each D object's writable segment whole; the RELRO
part of it is read-only before any D code runs. Flint Boot imports it.
+/
module flint.arena.data_roots;

@safe:

static import flint.arena.sys.gc.data_roots;

/// Bytes the startup trim took out of the root ranges; zero when the program has no RELRO region to trim.
alias trimmedRootBytes = flint.arena.sys.gc.data_roots.trimmedBytes;

// After druntime registered the data segments (rt_init runs module constructors after it initialises the sections
// and the collector), and before the program starts threads.
shared static this()
{
    flint.arena.sys.gc.data_roots.trimReadOnlyRoots();
}
