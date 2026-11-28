// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 CharacterCodingException family.
module character_coding_exception_test;

import flint.java.io : IOException;
import flint.java.lang : IllegalStateException;
import flint.java.nio.charset.charactercodingexception : CharacterCodingException;
import flint.java.nio.charset.malformedinputexception : MalformedInputException;
import flint.java.nio.charset.unmappablecharacterexception : UnmappableCharacterException;

@safe:

static assert(is(CharacterCodingException : IOException));
static assert(is(MalformedInputException : CharacterCodingException));
static assert(is(UnmappableCharacterException : CharacterCodingException));
// Java declares no message constructor on CharacterCodingException.
static assert(!__traits(compiles, new CharacterCodingException("detail")));

private bool rejectsSecondCause(IOException failure)
{
    try
        failure.initCause(new Exception("second"));
    catch (IllegalStateException)
        return true;
    return false;
}

@("CharacterCodingException has no detail and leaves the cause open")
unittest
{
    auto failure = new CharacterCodingException;
    assert(failure.getMessage() is null && failure.getCause() is null);
    auto cause = new IOException("decoder");
    assert(failure.initCause(cause) is failure && failure.getCause() is cause);
    assert(rejectsSecondCause(failure));
}

@("Malformed and unmappable input report their length in the message, with the cause open")
unittest
{
    auto malformed = new MalformedInputException(3);
    assert(malformed.getInputLength() == 3);
    assert(malformed.getMessage() == "Input length = 3");
    auto unmappable = new UnmappableCharacterException(-2);
    assert(unmappable.getInputLength() == -2);
    assert(unmappable.getMessage() == "Input length = -2");
    assert((new MalformedInputException(int.min)).getMessage() == "Input length = -2147483648");

    foreach (IOException failure; [cast(IOException) malformed, unmappable])
    {
        assert(failure.getCause() is null);
        assert(failure.initCause(null) is failure && failure.getCause() is null);
        assert(rejectsSecondCause(failure));
    }

    CharacterCodingException caught;
    try
        throw new UnmappableCharacterException(1);
    catch (CharacterCodingException value)
        caught = value;
    assert(cast(UnmappableCharacterException) caught !is null);
}
