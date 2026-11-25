module flint.os.interrupt_test;

version (Posix)
{
    import core.atomic : atomicLoad, atomicOp, atomicStore;
    import core.lifetime : move;
    import core.memory : GC;
    import core.sys.posix.signal : SIGINT, SIGTERM, SIG_IGN, kill, sigaction, sigaction_t, sigemptyset;
    import core.sys.posix.unistd : getpid;
    import core.thread.osthread : Thread;
    import core.time : msecs;
    import flint.arena : Status;
    import flint.os : InterruptSubscription, ShutdownSignal, onInterrupt, onShutdownSignal, watchShutdownSignals;

    private shared uint first;
    private shared uint second;

    private shared uint terminations;
    private shared uint interruptions;

    private extern (C) void foreignAction(int number) nothrow @nogc
    {
        if (number == SIGINT)
            atomicOp!"+="(first, 100U);
    }

    /// Ignore both signals for the test's duration, so the restored disposition cannot end the runner.
    private struct Ignored
    {
        sigaction_t interrupt, terminate;

        static Ignored install() @trusted
        {
            Ignored saved;
            sigaction_t ignored;
            sigemptyset(&ignored.sa_mask);
            ignored.sa_handler = SIG_IGN;
            assert(sigaction(SIGINT, &ignored, &saved.interrupt) == 0);
            assert(sigaction(SIGTERM, &ignored, &saved.terminate) == 0);
            return saved;
        }

        void restore() @trusted
        {
            sigaction(SIGINT, &interrupt, null);
            sigaction(SIGTERM, &terminate, null);
        }
    }

    private bool ignoring(int number) @trusted
    {
        sigaction_t active;
        assert(sigaction(number, null, &active) == 0);
        return active.sa_handler == SIG_IGN;
    }

    private void waitUntil(ref shared uint counter, uint value)
    {
        foreach (_; 0 .. 1000)
        {
            if (atomicLoad(counter) >= value)
                return;
            Thread.sleep(1.msecs);
        }
        assert(0, "signal callback did not execute");
    }

    @("SIGINT is dispatched to multiple safe subscriptions and the previous ignored action returns")
    unittest
    {
        const caller = Thread.getThis();
        sigaction_t ignored, before;
        sigemptyset(&ignored.sa_mask);
        ignored.sa_handler = SIG_IGN;
        assert(sigaction(SIGINT, &ignored, &before) == 0);
        scope (exit)
            sigaction(SIGINT, &before, null);

        auto one = onInterrupt(() @safe {
            assert(Thread.getThis() !is caller);
            atomicOp!"+="(first, 1U);
        });
        assert(one.ok, one.error.message);
        auto two = onInterrupt(() @safe { atomicOp!"+="(second, 1U); });
        assert(two.ok, two.error.message);

        assert(kill(getpid(), SIGINT) == 0);
        waitUntil(first, 1);
        waitUntil(second, 1);
        assert(one.value.close().code == Status.ok);
        assert(kill(getpid(), SIGINT) == 0);
        waitUntil(second, 2);
        assert(atomicLoad(first) == 1);
        assert(two.value.close().code == Status.ok);

        sigaction_t restored;
        assert(sigaction(SIGINT, null, &restored) == 0);
        assert(restored.sa_handler == SIG_IGN);
        assert(kill(getpid(), SIGINT) == 0);
        assert(atomicLoad(second) == 2);
    }

    @("a different live SIGINT handler keeps ownership")
    unittest
    {
        sigaction_t foreign, before;
        sigemptyset(&foreign.sa_mask);
        foreign.sa_handler = &foreignAction;
        assert(sigaction(SIGINT, &foreign, &before) == 0);
        scope (exit)
            sigaction(SIGINT, &before, null);
        const subscription = onInterrupt(() @safe {});
        assert(subscription.error.code == Status.conflict);
        sigaction_t active;
        assert(sigaction(SIGINT, null, &active) == 0);
        assert(active.sa_handler == &foreignAction);
    }

    @("SIGTERM and SIGINT reach a shutdown subscription with their kind, and SIGTERM skips an interrupt subscription")
    unittest
    {
        auto saved = Ignored.install();
        scope (exit)
            saved.restore();

        auto shutdown = onShutdownSignal((ShutdownSignal signal) @safe {
            atomicOp!"+="(signal == ShutdownSignal.terminate ? terminations : interruptions, 1U);
        });
        assert(shutdown.ok, shutdown.error.message);
        auto interruptOnly = onInterrupt(() @safe { atomicOp!"+="(second, 1000U); });
        assert(interruptOnly.ok, interruptOnly.error.message);
        const before = atomicLoad(second);

        assert(kill(getpid(), SIGTERM) == 0);
        waitUntil(terminations, 1);
        assert(atomicLoad(interruptions) == 0 && atomicLoad(second) == before);
        assert(kill(getpid(), SIGINT) == 0);
        waitUntil(interruptions, 1);
        waitUntil(second, before + 1000);
        assert(atomicLoad(terminations) == 1);

        // The interrupt subscription leaves, so SIGINT stays claimed and SIGTERM keeps its single owner.
        assert(interruptOnly.value.close().code == Status.ok);
        assert(!ignoring(SIGINT) && !ignoring(SIGTERM));
        assert(shutdown.value.close().code == Status.ok);
        assert(ignoring(SIGINT) && ignoring(SIGTERM));
    }

    @("the first shutdown signal cancels the graceful context and a second one, even coalesced, the forced context")
    unittest
    {
        auto saved = Ignored.install();
        scope (exit)
            saved.restore();

        foreach (signal; [SIGTERM, SIGINT])
        {
            auto watched = watchShutdownSignals();
            assert(watched.ok, watched.error.message);
            auto signals = &watched.value;
            auto graceful = signals.graceful();
            auto forced = signals.forced();
            assert(!graceful.cancelled() && !forced.cancelled() && signals.received() == 0);

            assert(kill(getpid(), signal) == 0);
            foreach (_; 0 .. 1000)
            {
                if (graceful.cancelled())
                    break;
                Thread.sleep(1.msecs);
            }
            assert(graceful.cancelled() && !forced.cancelled());
            assert(signals.first() == (signal == SIGTERM ? ShutdownSignal.terminate : ShutdownSignal.interrupt));

            // Two signals before the coordinator wakes still count as two.
            assert(kill(getpid(), signal) == 0);
            assert(kill(getpid(), signal) == 0);
            foreach (_; 0 .. 1000)
            {
                if (forced.cancelled())
                    break;
                Thread.sleep(1.msecs);
            }
            assert(forced.cancelled() && signals.received() >= 2);
            assert(signals.close().code == Status.ok);
            assert(ignoring(SIGINT) && ignoring(SIGTERM));
        }
    }

    private shared bool callbackRegistered;
    private shared uint coordinatedCalls;
    private __gshared InterruptSubscription selfClosing;

    private size_t druntimeThreads()
    {
        return Thread.getAll().length;
    }

    private void waitForThreads(size_t count)
    {
        foreach (_; 0 .. 1000)
        {
            if (druntimeThreads() == count)
                return;
            Thread.sleep(1.msecs);
        }
        assert(0, "the coordinator did not leave druntime's thread list");
    }

    @("the coordinator waits unknown to druntime, and joins it only to run callbacks, which may allocate and collect")
    unittest
    {
        auto saved = Ignored.install();
        scope (exit)
            saved.restore();
        const threads = druntimeThreads();

        auto subscription = onShutdownSignal((ShutdownSignal) @trusted {
            atomicStore(callbackRegistered, Thread.getThis() !is null);
            auto block = new ubyte[](4096);
            GC.collect();
            block[0] = 1;
            atomicOp!"+="(coordinatedCalls, 1U);
        });
        assert(subscription.ok, subscription.error.message);
        // Waiting, the coordinator is no druntime thread: a collection neither signals nor scans it.
        assert(druntimeThreads() == threads);
        GC.collect();

        const before = atomicLoad(coordinatedCalls);
        assert(kill(getpid(), SIGTERM) == 0);
        waitUntil(coordinatedCalls, before + 1);
        assert(atomicLoad(callbackRegistered));
        // Registered for its callbacks from the first one on, then gone once the last subscription closes.
        assert(druntimeThreads() == threads + 1);
        assert(kill(getpid(), SIGINT) == 0);
        waitUntil(coordinatedCalls, before + 2);
        assert(subscription.value.close().code == Status.ok);
        assert(druntimeThreads() == threads);
    }

    @("a callback that closes the last subscription retires its own coordinator, and a new subscription starts another")
    unittest
    {
        auto saved = Ignored.install();
        scope (exit)
            saved.restore();
        const threads = druntimeThreads();

        auto subscribed = onShutdownSignal((ShutdownSignal) @trusted {
            assert(selfClosing.close().code == Status.ok);
            atomicOp!"+="(coordinatedCalls, 1U);
        });
        assert(subscribed.ok, subscribed.error.message);
        move(subscribed.value, selfClosing);
        const before = atomicLoad(coordinatedCalls);
        assert(kill(getpid(), SIGTERM) == 0);
        waitUntil(coordinatedCalls, before + 1);
        waitForThreads(threads);
        assert(ignoring(SIGINT) && ignoring(SIGTERM));

        auto next = onShutdownSignal((ShutdownSignal) @safe { atomicOp!"+="(coordinatedCalls, 1U); });
        assert(next.ok, next.error.message);
        assert(kill(getpid(), SIGINT) == 0);
        waitUntil(coordinatedCalls, before + 2);
        assert(next.value.close().code == Status.ok);
        waitForThreads(threads);
    }

    @("a custom SIGTERM handler keeps ownership and the shutdown subscription gives SIGINT back")
    unittest
    {
        auto saved = Ignored.install();
        scope (exit)
            saved.restore();
        sigaction_t foreign;
        sigemptyset(&foreign.sa_mask);
        foreign.sa_handler = &foreignAction;
        assert(sigaction(SIGTERM, &foreign, null) == 0);

        const subscription = onShutdownSignal((ShutdownSignal) @safe {});
        assert(subscription.error.code == Status.conflict);
        const watched = watchShutdownSignals();
        assert(watched.error.code == Status.conflict);
        sigaction_t active;
        assert(sigaction(SIGTERM, null, &active) == 0);
        assert(active.sa_handler == &foreignAction);
        assert(ignoring(SIGINT));
    }
}
