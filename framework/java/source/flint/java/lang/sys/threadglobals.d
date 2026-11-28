// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Process-wide `Thread` defaults behind a small trusted accessor. `java.lang.thread` stays `@safe`; this
/// audited `sys` leaf owns the one mutable global.
module flint.java.lang.sys.threadglobals;

import flint.java.lang.thread : Thread;

@safe:

private __gshared Thread.UncaughtExceptionHandler defaultHandler;

// SAFETY: `defaultHandler` is one process-wide pointer reference. A pointer load or store is atomic on the
// supported targets and retains the handler through the GC's global scan; Java gives no ordering for this value.
@trusted Thread.UncaughtExceptionHandler getDefaultUncaughtExceptionHandler() nothrow @nogc
{
    return defaultHandler;
}

// SAFETY: as `getDefaultUncaughtExceptionHandler`: one aligned pointer store, and no borrowed storage escapes.
@trusted void setDefaultUncaughtExceptionHandler(Thread.UncaughtExceptionHandler handler) nothrow @nogc
{
    defaultHandler = handler;
}
