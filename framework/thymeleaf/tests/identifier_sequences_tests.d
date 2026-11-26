module identifier_sequences_tests;

import flint.java.lang : IllegalArgumentException;
import flint.thymeleaf.context : IdentifierSequences;
import flint.thymeleaf.exceptions : TemplateProcessingException;
import std.typecons : Nullable;

@safe:

@("identifier sequences advance only on demand and stay independent") unittest
{
    auto sequences = new IdentifierSequences();
    auto other = new IdentifierSequences();
    auto field = Nullable!string("field");
    auto empty = Nullable!string("");
    auto unicode = Nullable!string("é");
    auto decomposed = Nullable!string("e\u0301");

    assert(sequences.getNextIDSeq(field) == 1);
    assert(sequences.getNextIDSeq(field) == 1);
    assert(sequences.getAndIncrementIDSeq(field) == 1);
    assert(sequences.getAndIncrementIDSeq(field) == 2);
    assert(sequences.getPreviousIDSeq(field) == 2);
    assert(sequences.getNextIDSeq(field) == 3);
    assert(other.getNextIDSeq(field) == 1);
    assert(sequences.getAndIncrementIDSeq(empty) == 1);
    assert(sequences.getPreviousIDSeq(empty) == 1);
    assert(sequences.getAndIncrementIDSeq(unicode) == 1);
    assert(sequences.getNextIDSeq(decomposed) == 1);
}

@("identifier sequences report missing and absent ids with the pinned diagnostics") unittest
{
    auto sequences = new IdentifierSequences();
    auto id = Nullable!string("missing");
    assert(sequences.getNextIDSeq(id) == 1);
    try
    {
        sequences.getPreviousIDSeq(id);
        assert(false, "expected the previous-id lookup to fail");
    }
    catch (TemplateProcessingException error)
    {
        assert(error.msg == `Cannot obtain previous ID count for ID "missing"`);
    }

    expectAbsent(() => sequences.getNextIDSeq(Nullable!string.init));
    expectAbsent(() => sequences.getPreviousIDSeq(Nullable!string.init));
    expectAbsent(() => sequences.getAndIncrementIDSeq(Nullable!string.init));
}

private void expectAbsent(scope int delegate() @safe check)
{
    try
    {
        check();
        assert(false, "expected the absent id to fail");
    }
    catch (IllegalArgumentException error)
    {
        assert(error.msg == "ID cannot be null");
    }
}
