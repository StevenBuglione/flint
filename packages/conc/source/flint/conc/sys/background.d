module flint.conc.sys.background;

import core.thread : Thread;
import flint.arena : Error, Status;

@safe:

// SAFETY: Druntime retains this owned safe entry for the thread's lifetime. The worker's
// shutdown protocol publishes completion before releasing resources.
@trusted package(flint.conc) Error startDaemon(void delegate() @safe nothrow @nogc run)
{
    if (run is null)
        return Error(Status.invalidArgument, "missing background entry");
    try
    {
        auto worker = new Thread(run);
        worker.isDaemon = true;
        worker.start();
        return Error.init;
    }
    catch (Exception)
    {
        return Error(Status.unavailable, "could not start background worker");
    }
}
