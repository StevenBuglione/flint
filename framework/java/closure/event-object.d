module app;

import flint.java.util.eventobject : EventObject;

@safe:

int main(string[] args)
{
    Object source = args.length > 1 ? new Object : null;
    auto event = new EventObject(source);
    return event.getSource() is source ? cast(int)(event.toString().length & 127) : 1;
}
