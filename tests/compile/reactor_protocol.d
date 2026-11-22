module reactor_protocol;

import flint.arena : Status;
import flint.conc : Context, Deadline;
import flint.reactor : Completion, ConnectionId, Reactor, TaskContext;

@safe:

void onRead(Completion completion, scope const(ubyte)[] payload) nothrow @nogc
{
    if (completion.status == Status.ok)
        assert(payload.length == completion.bytes);
}

void onWrite(Completion completion) nothrow @nogc
{
}

void onTimer() nothrow @nogc
{
}

void onTask() nothrow @nogc
{
    auto loop = Reactor.current();
    if (loop.currentTask().ok())
        loop.yieldUntil(Deadline.afterMillis(10));
}

void submit(ConnectionId connection, Context context) nothrow @nogc
{
    auto loop = Reactor.current();
    auto read = loop.read(connection, 256, context, &onRead);
    if (read.ok())
        loop.cancel(read.value);

    ubyte[3] output = [1, 2, 3];
    loop.write(connection, output[], context, &onWrite);

    auto timer = loop.schedule(Deadline.afterMillis(50), &onTimer);
    if (timer.ok())
        loop.cancel(timer.value);

    loop.post(connection.ownerCore, &onTask, TaskContext(1, context));
}
