module mapping_exception_tests;

import flint.data.mapping : MappingException;
import flint.java.lang : IllegalStateException, RuntimeException;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

@("mapping error messages preserve absent and present empty values")
unittest
{
    RuntimeException absent = new MappingException(Nullable!string.init);
    RuntimeException empty = new MappingException(Nullable!string(""));
    assert(absent.getMessage() is null);
    assert(empty.getMessage() !is null && empty.getMessage().length == 0);

    auto cause = new Exception("field read failed");
    assert(absent.initCause(cause) is absent && absent.getCause() is cause);
}

@("mapping errors preserve the cause in both two-argument cases")
unittest
{
    auto cause = new Exception("field read failed");
    auto message = Nullable!string("could not obtain the mapped identifier");
    RuntimeException error = new MappingException(message, cause);
    assert(error.getMessage() == message.get);
    assert(error.getCause() is cause && error.next is null);
    assertThrown!IllegalStateException(error.initCause(null));

    RuntimeException explicitNull = new MappingException(message, null);
    assert(explicitNull.getCause() is null);
    assertThrown!IllegalStateException(explicitNull.initCause(cause));
}
