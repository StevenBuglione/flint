module flint.java.runtime_subclass_cause_test;

import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.java.nio.charset : IllegalCharsetNameException, UnsupportedCharsetException;
import flint.java.time : DateTimeException;
import flint.java.util : ConcurrentModificationException, NoSuchElementException;
import flint.java.util.formatter : MissingFormatArgumentException, UnknownFormatConversionException;
import std.exception : assertThrown;

@safe:

private void checkOpenCause(RuntimeException failure)
{
    assert(failure.getCause() is null);
    assertThrown!IllegalArgumentException(failure.initCause(failure));
    auto cause = new IllegalArgumentException("cause");
    assert(failure.initCause(cause) is failure);
    assert(failure.getCause() is cause);
    assertThrown!IllegalStateException(failure.initCause(null));
}

private void checkFixedCause(RuntimeException failure, Throwable cause)
{
    assert(failure.getCause() is cause);
    assertThrown!IllegalStateException(failure.initCause(null));
}

@("NoSuchElementException cause initialization")
unittest
{
    checkOpenCause(new NoSuchElementException);
    checkOpenCause(new NoSuchElementException("detail"));
    auto cause = new IllegalArgumentException("cause");
    checkFixedCause(new NoSuchElementException("detail", cause), cause);
    checkFixedCause(new NoSuchElementException("detail", null), null);
}

@("ConcurrentModificationException cause initialization")
unittest
{
    checkOpenCause(new ConcurrentModificationException);
    checkOpenCause(new ConcurrentModificationException("detail"));
    auto cause = new IllegalArgumentException("cause");
    checkFixedCause(new ConcurrentModificationException("detail", cause), cause);
    checkFixedCause(new ConcurrentModificationException("detail", null), null);
}

@("DateTimeException cause initialization")
unittest
{
    checkOpenCause(new DateTimeException("detail"));
    auto cause = new IllegalArgumentException("cause");
    checkFixedCause(new DateTimeException("detail", cause), cause);
    checkFixedCause(new DateTimeException("detail", null), null);
}

@("UnsupportedCharsetException cause initialization")
unittest
{
    checkOpenCause(new UnsupportedCharsetException("unknown"));
}

@("IllegalCharsetNameException cause initialization")
unittest
{
    checkOpenCause(new IllegalCharsetNameException("invalid?"));
}

@("UnknownFormatConversionException cause initialization")
unittest
{
    checkOpenCause(new UnknownFormatConversionException("z"));
}

@("MissingFormatArgumentException cause initialization")
unittest
{
    checkOpenCause(new MissingFormatArgumentException("%s"));
}
