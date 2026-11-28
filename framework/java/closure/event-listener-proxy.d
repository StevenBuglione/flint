module app;

import flint.java.util.eventlistenerproxy : EventListenerProxy;

@safe:

private final class Proxy : EventListenerProxy!()
{
    this(EventListenerProxy!() listener)
    {
        super(listener);
    }
}

int main(string[] args)
{
    auto inner = new Proxy(null);
    auto outer = args.length > 1 ? new Proxy(inner) : new Proxy(null);
    auto listener = outer.getListener();
    return listener is inner ? 0 : (listener is null ? 1 : 2);
}
