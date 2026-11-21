module flint.conc.sys.atomics;

import core.atomic : MemoryOrder, atomicLoad, atomicStore, casWeak, pause;
import core.thread.osthread : Thread;

@safe:

package(flint.conc) struct SpinLock
{
    private shared uint held;

    void lock() nothrow @nogc
    {
        uint attempts;
        for (;;)
        {
            if (atomicLoad!(MemoryOrder.raw)(held) == 0 && casWeak!(MemoryOrder.acq, MemoryOrder.raw)(&held, 0U, 1U))
                return;
            pause();
            if (++attempts == 64)
            {
                yieldThread();
                attempts = 0;
            }
        }
    }

    void unlock() nothrow @nogc
    {
        atomicStore!(MemoryOrder.rel)(held, 0U);
    }
}

// SAFETY: Yield supplies no pointers to druntime and retains no application data.
package(flint.conc) void yieldThread() @trusted nothrow @nogc
{
    Thread.yield();
}
