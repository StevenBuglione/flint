/++
Sleep on a 32-bit word until another thread changes it (futex on Linux, os_sync_wait_on_address on macOS,
WaitOnAddress on Windows, a bounded sleep elsewhere). Moved from engine-sql's lease wait so other packages share
the one audited copy (flint.conc.park).
+/
module flint.conc.sys.park;

@safe:

version (linux)
{
    version (X86_64)
        private enum futexCall = 202;
    else version (AArch64)
        private enum futexCall = 98;
    else version (RISCV64)
        private enum futexCall = 98;
}
else version (OSX)
{
    // <os/os_sync_wait_on_address.h>, libSystem since macOS 14.4 (ADR-024). Flags 0 keeps the wait
    // process private, as FUTEX_PRIVATE_FLAG does.
    private enum osClockMachAbsoluteTime = 32; // OS_CLOCK_MACH_ABSOLUTE_TIME
    private extern (C) @system nothrow @nogc
    {
        int os_sync_wait_on_address_with_timeout(void* address, ulong value, size_t size, uint flags,
                uint clock, ulong timeoutNanos);
        int os_sync_wake_by_address_all(void* address, size_t size, uint flags);
        int os_sync_wake_by_address_any(void* address, size_t size, uint flags);
    }
}

version (Windows)
{
    // WaitOnAddress and WakeByAddressAll, resolved from KernelBase so no synchronization.lib reaches the link
    // (ADR-026). A race resolves the same pointers.
    private alias Word = shared(uint)*;
    private extern (Windows) alias AddressWait = int function(Word, scope uint*, size_t, uint) @system nothrow @nogc;
    private extern (Windows) alias AddressWake = void function(scope Word) @system nothrow @nogc;
    private __gshared AddressWait waitOnAddress;
    private __gshared AddressWake wakeByAddressAll;
    private __gshared AddressWake wakeByAddressSingle;

    // SAFETY: GetProcAddress returns either null or the named export, whose signature the aliases above state.
    private bool addressWaits() @trusted nothrow @nogc
    {
        import core.sys.windows.winbase : GetModuleHandleW, GetProcAddress;

        if (waitOnAddress is null)
        {
            auto kernel = GetModuleHandleW("kernelbase.dll"w.ptr);
            if (kernel !is null)
            {
                wakeByAddressAll = cast(AddressWake) GetProcAddress(kernel, "WakeByAddressAll");
                wakeByAddressSingle = cast(AddressWake) GetProcAddress(kernel, "WakeByAddressSingle");
                waitOnAddress = cast(AddressWait) GetProcAddress(kernel, "WaitOnAddress");
            }
        }
        return waitOnAddress !is null && wakeByAddressAll !is null && wakeByAddressSingle !is null;
    }
}

/// Sleep while `word` holds `expected`, at most `nanos`; it may also return early, so re-check after it.
// SAFETY: The kernel compares the aligned 32-bit word with expected and sleeps at most nanos.
// It reads the word only during the call and retains neither address. Without a futex this sleeps.
void park(ref shared uint word, uint expected, long nanos) @trusted nothrow @nogc
{
    version (Windows)
    {
        // Timeouts and spurious returns go back to a caller that retries its acquisition.
        uint compare = expected;
        const millis = nanos <= 1_000_000 ? 1 : cast(uint)(nanos / 1_000_000);
        if (addressWaits())
            cast(void) waitOnAddress(&word, &compare, uint.sizeof, millis);
        else
            sleepBriefly(nanos);
    }
    else version (OSX)
    {
        // EINTR, EFAULT and ETIMEDOUT all return to a caller that retries its acquisition.
        cast(void) os_sync_wait_on_address_with_timeout(cast(void*)&word, expected, uint.sizeof,
                0, osClockMachAbsoluteTime, nanos > 0 ? cast(ulong) nanos : 1);
    }
    else static if (is(typeof(futexCall)))
    {
        import core.sys.linux.unistd : syscall;
        import core.sys.posix.time : timespec;

        enum waitPrivate = 128; // FUTEX_WAIT | FUTEX_PRIVATE_FLAG
        timespec limit;
        limit.tv_sec = nanos / 1_000_000_000;
        limit.tv_nsec = nanos % 1_000_000_000;
        // EINTR, EAGAIN and ETIMEDOUT all return to a caller that retries its acquisition.
        syscall(futexCall, cast(void*)&word, waitPrivate, expected, &limit, null, 0);
    }
    else
        sleepBriefly(nanos);
}

/// Wake every thread parked on `word`.
// SAFETY: The kernel uses the word address only as a key for waking its current waiters.
void wakeAll(ref shared uint word) @trusted nothrow @nogc
{
    version (Windows)
    {
        if (addressWaits())
            wakeByAddressAll(&word);
    }
    else version (OSX)
        cast(void) os_sync_wake_by_address_all(cast(void*)&word, uint.sizeof, 0);
    else static if (is(typeof(futexCall)))
    {
        import core.sys.linux.unistd : syscall;

        enum wakePrivate = 129; // FUTEX_WAKE | FUTEX_PRIVATE_FLAG
        syscall(futexCall, cast(void*)&word, wakePrivate, int.max, null, null, 0);
    }
}

/// Wake one thread parked on `word`.
// SAFETY: The kernel uses the word address only as a key for waking one of its current waiters.
void wakeOne(ref shared uint word) @trusted nothrow @nogc
{
    version (Windows)
    {
        if (addressWaits())
            wakeByAddressSingle(&word);
    }
    else version (OSX)
        cast(void) os_sync_wake_by_address_any(cast(void*)&word, uint.sizeof, 0);
    else static if (is(typeof(futexCall)))
    {
        import core.sys.linux.unistd : syscall;

        enum wakePrivate = 129; // FUTEX_WAKE | FUTEX_PRIVATE_FLAG
        syscall(futexCall, cast(void*)&word, wakePrivate, 1, null, null, 0);
    }
}

/// Where no address wait exists, sleep for the timeout, at most 2 ms, before the caller re-checks its word.
private void sleepBriefly(long nanos) nothrow @nogc
{
    import core.thread.osthread : Thread;
    import core.time : dur;

    Thread.sleep(dur!"nsecs"(nanos > 0 && nanos < 2_000_000 ? nanos : 2_000_000));
}

@("a parked thread wakes when another thread changes its word, and a stale expectation returns at once")
@system unittest
{
    import core.atomic : atomicLoad, atomicOp, atomicStore;
    import core.thread.osthread : Thread;
    import core.time : MonoTime, msecs;

    shared uint word;
    // The word already differs: the call returns without sleeping.
    const started = MonoTime.currTime;
    park(word, 1, 2_000_000_000);
    assert(MonoTime.currTime - started < 1_000.msecs);

    shared bool woke;
    auto sleeper = new Thread({
        while (atomicLoad(word) == 0)
            park(word, 0, 5_000_000_000);
        atomicStore(woke, true);
    });
    sleeper.start();
    Thread.sleep(20.msecs);
    atomicOp!"+="(word, 1);
    wakeOne(word);
    sleeper.join();
    assert(atomicLoad(woke));
    // Waking a word nobody waits on is harmless.
    wakeAll(word);
}
