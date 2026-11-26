/// Behavioral checks against Thymeleaf 3.1.7.RELEASE's exception constructors and message formatting.
module flint.thymeleaf.exception_tests;

import flint.java.lang : IllegalStateException, RuntimeException;
import flint.thymeleaf.exceptions : TemplateEngineException, TemplateInputException, TemplateProcessingException;
import std.typecons : Nullable;

@safe:

@("Thymeleaf exceptions preserve the cause and source location") unittest
{
    auto cause = new RuntimeException("processing failed");
    auto origin = Nullable!string("parsing/parsingexception01.html");
    auto failure = new TemplateInputException("failed", origin, 7, 8, cause);
    TemplateEngineException boundary = failure;
    assert(boundary.getCause() is cause);
    auto readMessage = () pure nothrow @nogc => boundary.getMessage();
    assert(readMessage() == `failed (template: "parsing/parsingexception01.html" - line 7, col 8)`);
    assert(failure.getTemplateName() == origin);
    assert(failure.hasLineAndCol() && failure.getLine().get() == 7 && failure.getCol().get() == 8);
}

@("Thymeleaf exception coordinates and names remain independently nullable") unittest
{
    auto failure = new TemplateProcessingException(null);
    assert(failure.getMessage() == "null");
    assert(!failure.hasTemplateName() && failure.getTemplateName().isNull);

    failure.setLineAndCol(-2, 0);
    assert(failure.getLine().isNull && failure.getCol().get() == 0 && !failure.hasLineAndCol());
    assert(failure.getMessage() == "null");
    failure.setTemplateName(Nullable!string(""));
    assert(failure.hasTemplateName() && failure.getTemplateName().get() == "");
    assert(failure.getMessage() == `null (template: "" - , col 0)`);
    failure.setLineAndCol(2, -1);
    assert(failure.getMessage() == `null (template: "" - line 2)`);
    failure.setLineAndCol(-1, -1);
    assert(failure.getCol().isNull && failure.getMessage() == `null (template: "")`);
    failure.setTemplateName(Nullable!string.init);
    assert(failure.getMessage() == "null");

    auto empty = new TemplateProcessingException("");
    assert(empty.getMessage() !is null && empty.getMessage().length == 0);
}

@("Thymeleaf cause initialization follows the selected constructor") unittest
{
    auto caused = new TemplateInputException("message", cast(Throwable) null);
    try
    {
        caused.initCause(new RuntimeException("replacement"));
        assert(0, "expected an explicitly supplied null cause to be final");
    }
    catch (IllegalStateException)
    {
        assert(caused.getCause() is null);
    }

    auto located = new TemplateInputException("message", Nullable!string("text.html"), 1, 0);
    auto cause = new RuntimeException("later");
    assert(located.initCause(cause) is located && located.getCause() is cause);
}
