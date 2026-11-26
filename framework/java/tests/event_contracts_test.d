module flint.java.event_contracts_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.util.eventlistener : EventListener;
import flint.java.util.eventobject : EventObject;

@safe:

private final class Source : Object
{
    override string toString()
    {
        return "origin";
    }
}

private final class DerivedEvent : EventObject
{
    this(Object source)
    {
        super(source);
    }

    void replaceSource(Object value)
    {
        source = value;
    }
}

private interface RecordingListener : EventListener
{
}

private final class Listener : RecordingListener
{
}

@("Java events keep the source identity and dispatch its string representation")
unittest
{
    auto origin = new Source;
    auto child = new DerivedEvent(origin);
    EventObject event = child;
    assert(event.getSource() is origin);
    assert(event.toString() == typeid(child).name ~ "[source=origin]");

    child.replaceSource(null);
    assert(event.getSource() is null);
    assert(event.toString() == typeid(child).name ~ "[source=null]");

    Object observer = new Listener;
    assert(cast(EventListener) observer !is null);
    assert(cast(EventListener) origin is null);
}

@("Java events reject a null source eagerly")
unittest
{
    import std.exception : collectException;

    auto failure = collectException!IllegalArgumentException(new EventObject(null));
    assert(failure !is null && failure.getMessage() == "null source");
}

private final class ProjectedEvent : EventObject
{
    this(Object source)
    {
        super(source);
    }

    override Object getSource()
    {
        throw new Exception("source projection");
    }
}

@("Java event source overrides do not change display of the stored source")
unittest
{
    import std.exception : collectException;

    EventObject event = new ProjectedEvent(new Source);
    auto failure = collectException(event.getSource());
    assert(failure !is null && failure.msg == "source projection");
    assert(event.toString() == typeid(event).name ~ "[source=origin]");
}
