module app;

import flint.java.util.eventlistener : EventListener;

@safe:

private final class Listener : EventListener
{
}

int main(string[] args)
{
    Object value = args.length > 1 ? new Listener : new Object;
    return cast(EventListener) value is null ? 1 : 0;
}
