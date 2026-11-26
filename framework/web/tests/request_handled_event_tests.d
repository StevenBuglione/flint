/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/web/context/support/
(RequestHandledEventTests.java, ServletRequestHandledEventTests.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors. D assertions use Flint's exception class names.
+/
module flint.web.request_handled_event_tests;

import std.typecons : Nullable;

import flint.java.lang : IllegalArgumentException, IllegalStateException;
import flint.web.context.support : RequestHandledEvent, ServletRequestHandledEvent;

@safe:

@("RequestHandledEventTests.descriptionWithNullableFields")
unittest
{
    auto event = new RequestHandledEvent(new Object, Nullable!string.init, Nullable!string.init, 400, null);

    assert(event.getDescription() == "session=[null]; user=[null]; time=[400ms]");
    assert(event.getSessionId().isNull);
    assert(event.getUserName().isNull);
}

@("RequestHandledEventTests.descriptionWithoutFailure")
unittest
{
    auto source = new Object;
    auto event = new RequestHandledEvent(source, Nullable!string("123-456"), Nullable!string("user"), 400, null);

    assert(event.getDescription() == "session=[123-456]; user=[user]; time=[400ms]");
    assert(event.getShortDescription() == "session=[123-456]; user=[user]; ");
    assert(event.getSource() is source);
    assert(event.getProcessingTimeMillis() == 400);
    assert(event.getSessionId().get == "123-456");
    assert(event.getUserName().get == "user");
    assert(!event.wasFailure());
    assert(event.getFailureCause() is null);
}

@("RequestHandledEventTests.descriptionWithFailure")
unittest
{
    auto failure = new IllegalStateException("Expected failure");
    auto event = new RequestHandledEvent(new Object, Nullable!string("123-456"),
            Nullable!string("user"), 400, failure);

    assert(event.getDescription() == "session=[123-456]; user=[user]; time=[400ms]; "
            ~ "failure=[flint.java.lang.IllegalStateException: Expected failure]");
    assert(event.toString() == "RequestHandledEvent: " ~ event.getDescription());
    assert(event.wasFailure());
    assert(event.getFailureCause() is failure);
}

@("ServletRequestHandledEventTests.descriptionWithoutStatusCode")
unittest
{
    auto event = new ServletRequestHandledEvent(new Object, "/", "example.com", "GET", "dispatcher",
            Nullable!string("123-456"), Nullable!string("user"), 400);

    assert(event.getDescription() == "url=[/]; client=[example.com]; method=[GET]; status=[-1]; "
            ~ "servlet=[dispatcher]; session=[123-456]; user=[user]; time=[400ms]");
    assert(event.getStatusCode() == -1);
    assert(!event.wasFailure());
}

@("ServletRequestHandledEventTests.descriptionWithFailure")
unittest
{
    auto failure = new IllegalStateException("Test");
    auto event = new ServletRequestHandledEvent(new Object, "/", "example.com", "GET", "dispatcher",
            Nullable!string("123-456"), Nullable!string("user"), 400, failure, 500);

    assert(event.getDescription() == "url=[/]; client=[example.com]; method=[GET]; status=[500]; "
            ~ "servlet=[dispatcher]; session=[123-456]; user=[user]; time=[400ms]; "
            ~ "failure=[flint.java.lang.IllegalStateException: Test]");
    assert(event.getShortDescription() == "url=[/]; client=[example.com]; session=[123-456]; user=[user]; ");
    assert(event.toString() == "ServletRequestHandledEvent: " ~ event.getDescription());
    assert(event.getFailureCause() is failure);
    assert(event.getRequestUrl() == "/");
    assert(event.getClientAddress() == "example.com");
    assert(event.getMethod() == "GET");
    assert(event.getServletName() == "dispatcher");
    assert(event.getStatusCode() == 500);
}

@("RequestHandledEvent.nullSourceAndEmptySession")
unittest
{
    import std.exception : assertThrown;

    auto source = new Object;
    auto event = new RequestHandledEvent(source, Nullable!string(""), Nullable!string.init, long.min);

    assert(event.getShortDescription() == "session=[]; user=[null]; ");
    assert(event.getDescription() == "session=[]; user=[null]; time=[-9223372036854775808ms]");
    assertThrown!IllegalArgumentException(new RequestHandledEvent(null, Nullable!string.init,
            Nullable!string.init, 0));
}

@("ServletRequestHandledEvent.failureWithoutStatus")
unittest
{
    auto failure = new Exception("I/O failure");
    auto event = new ServletRequestHandledEvent(new Object, "/", "example.com", "GET", "dispatcher",
            Nullable!string.init, Nullable!string.init, 400, failure);

    assert(event.getStatusCode() == -1);
    assert(event.getFailureCause() is failure);
    assert(event.wasFailure());
}
