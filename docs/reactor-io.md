# Reactor I/O and timer contract

This extends the [reactor handoff contract](../handoff/contracts/source/flint/engine/reactor.d) with the submission and cancellation operations required by the [reactor specification](../handoff/specs/tier-0/reactor.md). The existing signatures and backend enum values retain their meaning.

```d
alias TaskFn = void function() @safe nothrow @nogc;
alias ReadFn = void function(Completion, scope const(ubyte)[]) @safe nothrow @nogc;

struct IoId
{
    ConnectionId connection;
    uint slot;
    uint generation;
}

struct TaskContext
{
    ulong requestId;
    Context cancellation;
    ulong traceIdHigh;
    ulong traceIdLow;
    ulong spanId;
    this(ulong requestId, Context cancellation = Context.init) nothrow @nogc;
}

struct WorkerStats
{
    ulong gcAllocated;
    size_t gcCollections;
    bool affinityPinned;
    ulong cpuNanos;
    ulong voluntarySwitches;
    ulong involuntarySwitches;
    uint outstandingOperations;
}

// Additional Reactor methods
static Reactor current() nothrow @nogc;
Result!IoId read(ConnectionId connection, size_t maxBytes, Context context, ReadFn completion) nothrow @nogc;
Result!IoId write(ConnectionId connection, scope const(ubyte)[] source, Context context, CompletionFn completion) nothrow @nogc;
Error cancel(IoId operation) nothrow @nogc;
Result!TimerId schedule(Deadline deadline, TaskFn task) nothrow @nogc;
Error cancel(TimerId timer) nothrow @nogc;
Result!ushort localPort() const nothrow @nogc;
Backend activeBackend() const nothrow @nogc;
Error post(uint ownerCore, TaskFn task, TaskContext context) nothrow @nogc;
Result!TaskContext currentTask() const nothrow @nogc;
Error yieldUntil(Deadline deadline) nothrow @nogc;
Error yieldUntil(Deadline deadline, ref scope const Context watched) nothrow @nogc;
Result!TaskWaker currentWaker() const nothrow @nogc;
Error wake(TaskWaker waker) nothrow @nogc;
Result!WorkerStats workerStats(uint core) const nothrow @nogc;
```

- `Reactor.current()` provides a non-owning reference for callbacks on a reactor worker. Its default value outside a worker cannot be used to submit work. Submit I/O and timers, and cancel tickets, on the owning loop. Cross-loop connection closes go through the bounded mailbox.
- The loop admits one read and one write per connection. Each successful submission has one final callback. The read callback borrows a slice through its return. A successful read with zero bytes signals EOF. Writes copy the source before returning, and retry partial writes until the copy is sent or the operation has a terminal status. A failed write may report a prefix that reached the socket.
- Cancel requests match both the connection identity and the operation generation. The owning loop resolves cancellation against the final completion. It retains kernel-visible storage until that completion and keeps callback storage live through callback return. Stale tickets cannot cancel a reused slot. Cancelled timers never invoke their callback after cancellation has won on the owning loop.
- `localPort()` returns the bound port after `listen`, including the assigned port when the caller requests port zero. The active backend can be inspected after creation. `Backend.epoll` is appended to the enum. On Linux, `automatic` tries the pinned io_uring provider and falls back to epoll when the required capability is unavailable. Explicit `ioUring` requires the provider and kernel operations.
- `ReactorOptions` adds `maxPendingIoPerCore` (128), `ioBufferBytes` (4096), `mailboxCapacity` (256) and `maxTimersPerCore` (1024). The reactor reserves these resources at startup and reports pool or mailbox exhaustion to the caller.
- Posted tasks retain their own cancellation context and run on fibers pinned to the chosen worker. When a task yields to a finite monotonic deadline, its owner resumes it on expiry, cancellation, `wake` or shutdown. The `watched` overload also resumes it when the loop sees that context cancelled or expired. `currentWaker()` returns a `TaskWaker` (owner, fiber slot and the slot's task generation) for the active fiber. A completion, timer or other task on the same loop passes it to `wake`, which marks the suspended fiber due for the loop's next pass. Waking a running or due fiber is a no-op, and a handle whose task has ended is rejected with `notFound`. Waiters therefore re-check their condition after every resumption and clear their registration before an unrelated wait (ADR-017, Public API additions). `currentTask()` exposes the active fiber's context. After the loop has joined, `workerStats()` exposes allocation and collection deltas, affinity, CPU time, context switches and outstanding operation counts.

The Linux adapter uses a single-threaded opaque C ring through `native/ffi/flint_reactor_uring.h`. A successful preparation transfers the buffer to that operation until its original CQE. Cancellation uses a separate CQE with reserved token zero. Accept uses token one. The adapter retains stable operation tokens across submission and reports errors from feature probing through the backend selector. The D loop drains original and cancellation CQEs before destroying the ring.

## Application-owned callbacks and native readiness

`listenWith`, `readWith`, and `writeWith` retain application delegates through listener lifetime or the final I/O callback. A listener can run concurrently on different cores. Every read and write completion runs on the connection owner. `postWith` retains a task delegate for a fiber on the posting owner core and copies its `TaskContext`.

Linux clients can register caller-owned descriptors using `watchNative`. The callback runs outside owner fibers and receives level-triggered read, write, and error flags. The library owning the descriptor calls `unwatchNative` before releasing it. A removed slot advances its identity before reuse, so a queued event from the earlier registration cannot notify the new callback. `maxNativeWatchesPerCore` bounds this table.

The epoll loop observes the native watch poller as a child descriptor. The io_uring loop uses an asynchronous readable poll for that child with reserved token two. Shutdown retires that poll and any cancellation acknowledgement before releasing the epoll descriptor.
