// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module completion_handler_probe;

import flint.java.nio.channels.completionhandler : CompletionHandler;

@safe:

private final class CounterHandler : CompletionHandler!(int, int)
{
    int value;

    override void completed(int result, int attachment)
    {
        value = result + attachment;
    }

    override void failed(Throwable exc, int attachment)
    {
        value = exc is null ? attachment : -attachment;
    }
}

int main(string[] args)
{
    auto impl = new CounterHandler;
    CompletionHandler!(int, int) handler = impl;
    if (args.length > 1)
        handler.completed(cast(int) args.length, 3);
    else
        handler.failed(null, 5);
    return impl.value;
}
