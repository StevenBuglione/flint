module flint.java.event_listener_proxy_test;

import flint.java.util.eventlistener : EventListener;
import flint.java.util.eventlistenerproxy : EventListenerProxy;

@safe:

private interface RecordingListener : EventListener
{
}

private final class Listener : RecordingListener
{
}

private final class NamedProxy(T) : EventListenerProxy!T
{
    string name;

    this(T listener, string name)
    {
        super(listener);
        this.name = name;
    }
}

private final class DefaultProxy : EventListenerProxy!()
{
    this()
    {
        super(null);
    }
}

@("A listener proxy returns its wrapped listener and is itself a listener")
unittest
{
    auto listener = new Listener;
    auto named = new NamedProxy!Listener(listener, "input");
    EventListenerProxy!Listener proxy = named;
    assert(proxy.getListener() is listener);
    assert(named.name == "input");
    assert((cast(EventListener) proxy) !is null);
}

@("A listener proxy keeps a null listener instead of rejecting it")
unittest
{
    auto proxy = new NamedProxy!RecordingListener(null, "none");
    assert(proxy.getListener() is null);
    assert((cast(EventListener) proxy) !is null);
}

@("The Java bound is a template constraint and the parameter defaults to the bound")
unittest
{
    static assert(is(DefaultProxy : EventListenerProxy!EventListener));
    static assert(!__traits(compiles, EventListenerProxy!Object));
}
