module flint.web.api_version_exception_tests;

import flint.web.accept : InvalidApiVersionException, MissingApiVersionException, NotAcceptableApiVersionException;
import flint.web.server : ResponseStatusException;
import std.typecons : Nullable, nullable;

@safe:

@("InvalidApiVersionException keeps the requested version and default reason")
unittest
{
    auto error = new InvalidApiVersionException("1.2.0");

    assert(error.getVersion() == "1.2.0");
    assert(error.getStatusCode().value() == 400);
    assert(error.getReason() == "Invalid API version: '1.2.0'.");
    assert(error.getMessage() == "400 BAD_REQUEST \"Invalid API version: '1.2.0'.\"");
    assert(error.getBody().getStatus() == 400);
    assert(error.getBody().getDetail() == error.getReason());
    assert(error.getCause() is null);
}

@("InvalidApiVersionException preserves explicit and empty reasons and the cause")
unittest
{
    auto cause = new Exception("version parse failed");
    auto error = new InvalidApiVersionException("β", nullable("Invalid version syntax"), cause);

    assert(error.getVersion() == "β");
    assert(error.getReason() == "Invalid version syntax");
    assert(error.getMessage() == "400 BAD_REQUEST \"Invalid version syntax\"");
    assert(error.getCause() is cause);
    assert(error.getBody().getDetail() == error.getReason());

    auto empty = new InvalidApiVersionException("β", nullable(string.init), cause);
    assert(empty.getReason() !is null);
    assert(empty.getMessage() == "400 BAD_REQUEST \"\"");
    assert(empty.getBody().getDetail() !is null);
    assert(empty.getCause() is cause);

    auto absent = new InvalidApiVersionException("β", Nullable!string.init, cause);
    assert(absent.getMessage() == "400 BAD_REQUEST \"Invalid API version: 'β'.\"");
    assert(absent.getCause() is cause);
}

@("MissingApiVersionException reports a required version as a bad request")
unittest
{
    ResponseStatusException error = new MissingApiVersionException;

    assert(error.getStatusCode().value() == 400);
    assert(error.getMessage() == "400 BAD_REQUEST \"API version is required.\"");
    assert(error.getBody().getDetail() == "API version is required.");
    assert(error.getCause() is null);
}

@("NotAcceptableApiVersionException is an invalid-version bad request")
unittest
{
    InvalidApiVersionException error = new NotAcceptableApiVersionException("2");

    assert(error.getVersion() == "2");
    assert(error.getStatusCode().value() == 400);
    assert(error.getMessage() == "400 BAD_REQUEST \"Invalid API version: '2'.\"");
}
