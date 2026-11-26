/++
`FiberLocal!T`, the fiber counterpart of a Java `ThreadLocal`, in a leaf with no reactor imports.

A module that only keeps per-request state (a transaction holder, the MDC, the locale context) imports this
leaf and pays for the key and its access. It does not compile and link the reactor's loop, sockets and
offload pool, which importing `flint.engine.reactor` does. `flint.engine.reactor` re-exports `FiberLocal`
and `maxFiberLocalWords`, and installs the task-fiber resolver on each worker thread while its loop runs.

The file name matters: LDC compiles a DUB package in one invocation and emits the whole package's template instances
and compiler-generated helpers into the object of the first source file. As that file, this leaf would reference the
reactor, conc and arena objects and link them all (S-19), so its name sorts after `internal/`.
+/
module flint.engine.reactor.local;

import core.atomic : atomicLoad, cas;
import flint.arena : Error, Status;
import flint.engine.reactor.sys.locals : cellStamp, loadCell, localStorable, localWords, storeCell;

@safe:

/// Words that all `FiberLocal` declarations of a process may claim together, one per local plus its value.
enum uint maxFiberLocalWords = 128;

/// Resolves a cell on the calling thread's active task fiber. False when no task fiber is active, so the
/// thread's own words serve. True with an empty cell when that fiber's storage is too small for it.
package(flint.engine.reactor) alias TaskCellResolver = bool function(size_t first, size_t end,
        bool writing, out void*[] cell, out size_t stamp) nothrow @nogc;

/// The resolver of the loop running on this thread; null off a reactor worker. Set and cleared by that
/// worker around its loop, so it is per-thread state, as the loop it names is.
package(flint.engine.reactor) TaskCellResolver taskCellResolver;

private shared uint claimedLocalWords;
// FiberLocal values read or written off any task fiber: on a loop callback, an offload thread or a thread
// outside the reactor. Thread-local by design; the stamp is constant because the thread never retires. The
// reactor swaps a caller's values out while it runs a loop on that thread.
package(flint.engine.reactor) void*[maxFiberLocalWords] threadLocalWords;
private enum size_t threadStamp = 1;

/// A value each task fiber sees separately, the fiber counterpart of a Java `ThreadLocal`. A task starts
/// with `T.init`; what it sets is gone once it ends, even though its fiber slot is reused. Off a task fiber
/// the value is thread-local. Declare it as `shared FiberLocal!T`: only its storage key is shared.
///
/// `T` is a class or interface reference or plain data without copy or destruction hooks, at most
/// `maxFiberLocalWords - 1` words. A set value may not borrow stack or request storage.
struct FiberLocal(T) if (localStorable!T && localWords!T < maxFiberLocalWords)
{
    /// One past the first word claimed for this local, or zero before the first `set`.
    private uint key;

    /// The calling task's value, or `T.init` when it set none.
    T get() shared nothrow @nogc
    {
        const offset = atomicLoad(key);
        if (offset == 0)
            return T.init;
        size_t stamp;
        auto cell = localCell(offset, localWords!T, stamp);
        if (cell.length == 0 || cellStamp(cell) != stamp)
            return T.init;
        return loadCell!T(cell);
    }

    /// Replace the calling task's value. Fails with `resourceExhausted` when the process claimed
    /// `maxFiberLocalWords` or the task fiber's `ReactorOptions.fiberLocalWords` is too small.
    Error set(T value) shared nothrow @nogc
    {
        const offset = claimLocal(key, localWords!T);
        if (offset == 0)
            return Error(Status.resourceExhausted, "FiberLocal words exhausted for this process");
        size_t stamp;
        auto cell = localCell(offset, localWords!T, stamp, true);
        if (cell.length == 0)
            return Error(Status.resourceExhausted, "raise ReactorOptions.fiberLocalWords for this FiberLocal");
        storeCell!T(cell, stamp, value);
        return Error.init;
    }

    /// Forget the calling task's value, so `get` returns `T.init` and its references are released.
    void remove() shared nothrow @nogc
    {
        const offset = atomicLoad(key);
        if (offset == 0)
            return;
        size_t stamp;
        auto cell = localCell(offset, localWords!T, stamp);
        cell[] = null; // empty when the cell was never allocated
    }
}

/// The offset of a local's cell, claiming `words` plus a stamp on first use. Zero when the process ran out.
private uint claimLocal(ref shared uint key, size_t words) nothrow @nogc
{
    const current = atomicLoad(key);
    if (current != 0)
        return current;
    for (;;)
    {
        const used = atomicLoad(claimedLocalWords);
        if (used + 1 + words > maxFiberLocalWords)
            return 0;
        if (!cas(&claimedLocalWords, used, cast(uint)(used + 1 + words)))
            continue;
        // A racing first `set` may have published first; its claim wins and this one stays unused.
        if (cas(&key, 0U, used + 1))
            return used + 1;
        return atomicLoad(key);
    }
}

/// The calling context's cell for `offset`, with the stamp of its current owner. Empty when the active task
/// fiber's storage is too small for this cell.
private void*[] localCell(uint offset, size_t words, out size_t stamp, bool writing = false) nothrow @nogc
{
    const first = offset - 1;
    const end = first + 1 + words;
    void*[] cell;
    if (taskCellResolver !is null && taskCellResolver(first, end, writing, cell, stamp))
        return cell;
    stamp = threadStamp;
    return threadLocalWords[first .. end];
}
