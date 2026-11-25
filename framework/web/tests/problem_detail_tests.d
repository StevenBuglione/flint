/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/http/ProblemDetailTests.java.
Copyright 2002-present the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: JUnit and AssertJ assertions become D unittests and asserts; Java's
`equals`/`hashCode` are D's `opEquals`/`toHash` (rulebook R11).
+/
module flint.http.problem_detail_tests;

import flint.http : HttpStatus, ProblemDetail;

@safe:

@("ProblemDetailTests.equalsAndHashCode")
unittest
{
    ProblemDetail pd1 = ProblemDetail.forStatus(500);
    ProblemDetail pd2 = ProblemDetail.forStatus(HttpStatus.INTERNAL_SERVER_ERROR);
    ProblemDetail pd3 = ProblemDetail.forStatus(HttpStatus.NOT_FOUND);
    ProblemDetail pd4 = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, "some detail");

    assert(pd1 == pd2);
    assert(pd2 == pd1);
    assert(pd1.toHash() == pd2.toHash());

    assert(pd3 != pd4);
    assert(pd4 != pd3);
    assert(pd3.toHash() != pd4.toHash());

    assert(pd1 != pd3);
    assert(pd1 != pd4);
    assert(pd2 != pd3);
    assert(pd2 != pd4);
    assert(pd1.toHash() != pd3.toHash());
    assert(pd1.toHash() != pd4.toHash());
}

// ProblemDetailTests.equalsAndHashCodeWithDeserialization (gh-30294) round-trips a ProblemDetail through
// Jackson's ObjectMapper. flint.http.converter.json writes ProblemDetail but does not read it yet, so the case
// compiles once reading lands (version FlintProblemDetailRead).
version (FlintProblemDetailRead)
{
    @("ProblemDetailTests.equalsAndHashCodeWithDeserialization (gh-30294)")
    unittest
    {
        import flint.jackson.databind : JsonMapper;

        ProblemDetail originalDetail = ProblemDetail.forStatus(500);
        auto mapper = JsonMapper.builder().findAndAddModules().build();
        auto bytes = mapper.writeValueAsBytes(originalDetail);
        ProblemDetail deserializedDetail = mapper.readValue!ProblemDetail(bytes);
        assert(originalDetail == deserializedDetail);
        assert(deserializedDetail == originalDetail);
        assert(originalDetail.toHash() == deserializedDetail.toHash());
    }
}

/// A subclass, to reach Spring's protected copy constructor.
private final class CopiedProblem : ProblemDetail
{
    this(ProblemDetail other)
    {
        super(other);
    }
}

@("ProblemDetail properties keep insertion order, replace in place, grow past two, and copy (Flint)")
unittest
{
    import flint.engine.aot.any : Any;

    auto pair = ProblemDetail.forStatus(400);
    pair.setProperty("timestamp", 1);
    pair.setProperty("errors", 2);
    pair.setProperty("timestamp", 10);
    assert(pair.getPropertyNames() == ["timestamp", "errors"] && pair.getProperty("timestamp").get!int == 10);
    auto pairCopy = new CopiedProblem(pair);
    pairCopy.setProperty("errors", 30);
    pairCopy.setProperty("third", 3);
    assert(pair.getProperty("errors").get!int == 2 && pair.getPropertyNames().length == 2);
    assert(pairCopy.getPropertyNames() == ["timestamp", "errors", "third"] && pairCopy.getProperty("errors").get!int == 30);
    assert(pair.toString().length != 0 && pairCopy.toString().length != 0);

    auto detail = ProblemDetail.forStatus(400);
    assert(!detail.hasProperties() && detail.getPropertyNames().length == 0 && detail.getProperty("a").isNull);
    foreach (i, name; ["a", "b", "c", "d", "e", "f"])
        detail.setProperty(name, cast(int) i);
    detail.setProperty("b", 20);
    assert(detail.getPropertyNames() == ["a", "b", "c", "d", "e", "f"]);
    assert(detail.getProperty("b").get!int == 20 && detail.getProperty("f").get!int == 5);
    assert(detail.getProperty("missing").isNull && detail.hasProperties());

    auto copy = new CopiedProblem(detail);
    assert(copy.getPropertyNames() == detail.getPropertyNames() && copy.getProperty("e").get!int == 4);
    copy.setProperty("a", 100);
    assert(detail.getProperty("a").get!int == 0, "the copy has its own properties");
}
