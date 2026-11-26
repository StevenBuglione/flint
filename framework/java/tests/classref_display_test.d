module flint.java.classref_display_test;

import flint.java.classref : ClassRef, classOf;
import flint.java.lang : valueOf;
import flint.java.util : ArrayList, List;

@safe:

@("ClassRef renders its stored name and keeps absent list elements visible")
unittest
{
    const named = classOf!Object;
    const absent = ClassRef.init;

    assert(valueOf(named) == named.name);
    assert(valueOf(named).ptr is named.name.ptr);
    assert(valueOf(absent) == "null");
    assert(absent.name is null);

    List!ClassRef values = new ArrayList!ClassRef();
    values.add(named);
    values.add(absent);
    assert(values.toString() == "[" ~ named.name ~ ", null]");
}
