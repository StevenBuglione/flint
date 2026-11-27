// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 CoderMalfunctionError API, pinned by a Temurin 21.0.13+9 oracle.
module coder_malfunction_error_test;

import flint.java.lang : IllegalStateException, RuntimeException;
import flint.java.nio.charset.codermalfunctionerror : CoderMalfunctionError;
import std.exception : collectException;

@safe:

static assert(!__traits(compiles, new CoderMalfunctionError()));
static assert(!__traits(compiles, new CoderMalfunctionError("message")));
static assert(!is(CoderMalfunctionError : RuntimeException));
static assert(is(CoderMalfunctionError : Exception));

@("CoderMalfunctionError(Exception) keeps the cause and uses its Java toString as the message")
unittest
{
    auto loop = new RuntimeException("loop failed");
    auto error = new CoderMalfunctionError(loop);
    assert(error.getCause() is loop);
    assert(error.getMessage() == "flint.java.lang.RuntimeException: loop failed");
    assert(error.getLocalizedMessage() == error.getMessage());
    assert(error.toString() == "flint.java.nio.charset.codermalfunctionerror.CoderMalfunctionError: "
            ~ "flint.java.lang.RuntimeException: loop failed");

    auto bare = new CoderMalfunctionError(new IllegalStateException());
    assert(bare.getMessage() == "flint.java.lang.IllegalStateException");

    auto checked = new CoderMalfunctionError(new Exception("io"));
    assert(checked.getMessage() == "object.Exception: io");
}

@("CoderMalfunctionError(null) has no message and no cause")
unittest
{
    auto error = new CoderMalfunctionError(null);
    assert(error.getMessage() is null && error.getCause() is null);
    assert(error.toString() == "flint.java.nio.charset.codermalfunctionerror.CoderMalfunctionError");
}

@("CoderMalfunctionError.initCause always refuses, because the constructor set the cause")
unittest
{
    auto loop = new RuntimeException("loop failed");
    auto error = new CoderMalfunctionError(loop);
    auto ise = collectException!IllegalStateException(error.initCause(new RuntimeException("x")));
    assert(ise !is null && ise.getMessage() == "Can't overwrite cause with flint.java.lang.RuntimeException: x");
    ise = collectException!IllegalStateException(error.initCause(null));
    assert(ise !is null && ise.getMessage() == "Can't overwrite cause with a null");
    assert(error.getCause() is loop);

    auto nullCause = new CoderMalfunctionError(null);
    ise = collectException!IllegalStateException(nullCause.initCause(loop));
    assert(ise !is null);
    assert(ise.getMessage() == "Can't overwrite cause with flint.java.lang.RuntimeException: loop failed");
    assert(nullCause.getCause() is null);
}

@("CoderMalfunctionError escapes a catch of RuntimeException, as Java's Error does")
unittest
{
    static void malfunction()
    {
        throw new CoderMalfunctionError(new RuntimeException("loop failed"));
    }

    bool runtimeCaught;
    CoderMalfunctionError caught;
    try
    {
        try
            malfunction();
        catch (RuntimeException)
            runtimeCaught = true;
    }
    catch (CoderMalfunctionError error)
        caught = error;
    assert(!runtimeCaught && caught !is null);
}
