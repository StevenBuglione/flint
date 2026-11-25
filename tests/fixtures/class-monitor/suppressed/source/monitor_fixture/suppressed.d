/// FLINT-E0536 fixture: a deliberate negative test suppresses its finding with a reason; a copy without one fails.
module monitor_fixture.suppressed;

import core.sync.mutex : Mutex;

@system:

/// The class whose metadata the negative test gives a GC monitor on purpose.
final class Probe
{
}

/// The suppressed lines pass, and the identical unsuppressed line still fails.
Object[] negativeTest()
{
    Object[] made;
    made ~= new Mutex(typeid(Probe)); // flint: allow-class-monitor (the verifier's negative test)
    // flint: allow-class-monitor (the verifier's negative test, shared)
    made ~= cast(Object) new shared Mutex(typeid(Probe));
    made ~= new Mutex(typeid(Probe)); // expect: FLINT-E0536
    return made;
}
