/// Startup-owned reactor transfer and joined coordinator thread.
module flint_micro.sys.driver;

import core.lifetime : move;
import core.thread : Thread;
import flint.reactor : Reactor;

@safe:

/// Transfer a just-created reactor into its initially empty driver.
// SAFETY: Both reactor values have coordinator-owned lifetimes. The destination is empty,
// and no owner loop has started. move leaves the source empty and invokes no foreign callbacks.
@trusted void takeOwner(ref Reactor startup, ref Reactor destination)
{
    move(startup, destination);
}

/// Start a driver holding its heap-owned reactor state.
// SAFETY: The bound callback is a startup-owned heap delegate with no borrowed stack state.
// The coordinator retains the Thread object until it has stopped and joined its reactor.
@trusted Thread startDriver(void delegate() @safe nothrow execute)
{
    return new Thread(execute).start();
}

/// Join a stopped or draining driver and check whether its callback threw.
// SAFETY: Only the coordinator calls join, after requesting reactor shutdown. Suppress rethrow here
// and return whether an exception occurred, so no callback failure can yield a successful trial.
@trusted bool joinDriver(Thread driver)
{
    return driver.join(false) is null;
}
