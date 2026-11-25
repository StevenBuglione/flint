/++
The per-endpoint fast path's startup proof and request rules (docs/spring/phase1/fast-path.md), against the
strategies `WebMvcConfigurationSupport` really builds. Each test offers a `FastExchange` to the `DispatcherServlet`
as the container does, and checks what the fast path answers and when it declines.
+/
module fast_path_tests;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
import flint.engine.aot.fast : FastExchange, FastField, FastOutcome, FastValueVisitor;
import flint.engine.aot.mapping : AotHandlerMapping = HandlerMapping;
import flint.http : HttpHeaders, HttpStatus, ProblemDetail, ResponseEntity;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.http.converter.json : JacksonJsonHttpMessageConverter;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.test.web.servlet.setup : StaticBeanFactory;
import flint.jakarta.validation : Valid;
import flint.web.bind : MethodArgumentNotValidException;
import flint.web.bind.annotation : CrossOrigin, DeleteMapping, ExceptionHandler, GetMapping,
    PathVariable, PostMapping, RequestBody, RequestParam, RestController, RestControllerAdvice;
import flint.web.servlet : DispatcherServlet, HandlerInterceptor;
import flint.web.servlet.config.annotation : InterceptorRegistry, WebMvcConfigurationSupport, WebMvcConfigurer;
import flint.web.servlet.mvc.method.aot : handlerDescriptorsOf, requestMappingsOf;
import flint.web.servlet.mvc.method.fast : FastPathConfigurer;

@safe:

struct Hello
{
    long id;
    string text;
}

@RestController
class HelloController
{
    long calls;

    @GetMapping("/hello")
    Hello hello(@RequestParam(value: "name", defaultValue: "World") string name)
    {
        return Hello(++calls, "Hello, " ~ name ~ "!");
    }
}

@RestController
@CrossOrigin
class CorsController
{
    @GetMapping("/cors")
    Hello cors(@RequestParam(value: "name", defaultValue: "World") string name)
    {
        return Hello(1, name);
    }
}

@RestController
class EntityController
{
    @GetMapping("/entity")
    ResponseEntity entity()
    {
        return ResponseEntity.of(Hello(1, "x"), HttpStatus.CREATED);
    }
}

final class Box
{
    string text; ///
}

@RestController
class NullController
{
    long calls;

    @GetMapping("/nothing")
    Box nothing()
    {
        ++calls;
        return null;
    }
}

/// S1: path variables of each bound type, beside a DELETE on the same pattern and a non-numeric literal.
@RestController
class OwnerController
{
    long calls; ///

    @GetMapping(value: ["/owners/{ownerId}"], produces: ["application/json"])
     ///
    Hello owner(@PathVariable("ownerId") int ownerId)
    {
        ++calls;
        return Hello(ownerId, "owner");
    }

    @GetMapping("/owners/{ownerId}/pets/{petId}")
     ///
    Hello pet(@PathVariable("ownerId") long ownerId, @PathVariable("petId") string petId)
    {
        ++calls;
        return Hello(ownerId, petId);
    }

    @DeleteMapping("/owners/{ownerId}")
     ///
    Hello remove(@PathVariable("ownerId") int ownerId)
    {
        return Hello(ownerId, "deleted");
    }

    // Overlaps /owners/{ownerId} only for a value that is not a canonical number.
    @GetMapping("/owners/find")
     ///
    Hello find()
    {
        return Hello(0, "find");
    }
}

/// S1: a template that a literal GET mapping overlaps for one canonical id.
@RestController
class ShadowController
{
    @GetMapping("/items/{id}")
     ///
    Hello item(@PathVariable("id") int id)
    {
        return Hello(id, "item");
    }

    // A literal that a canonical id also matches: the template route may not claim /items/7.
    @GetMapping("/items/7")
     ///
    Hello seven()
    {
        return Hello(7, "seven");
    }
}

/// S2: ResponseEntity returns with a fixed producible type, each status and body shape.
@RestController
class EntityRoutesController
{
    long calls; ///

    ///
    @GetMapping(value: ["/entities/{id}"], produces: ["application/json"])
    ResponseEntity entity(@PathVariable("id") int id)
    {
        ++calls;
        if (id == 0)
            return ResponseEntity(HttpStatus.NOT_FOUND);
        if (id == 2)
        {
            HttpHeaders headers;
            headers.set("X-Extra", "1");
            return ResponseEntity.of(Hello(id, "headers"), headers, HttpStatus.OK);
        }
        if (id == 3)
            return ResponseEntity.of("text", HttpStatus.OK);
        return ResponseEntity.of(Hello(id, "entity"), HttpStatus.CREATED);
    }
}

private final class CountingInterceptor : HandlerInterceptor
{
}

/// A dispatcher over `controller`'s rows, which keep their array invokers (contract 4) unless `arrayInvokers` is
/// false, with the configurer Flint AOT generates for a qualifying endpoint unless `generated` is false.
private DispatcherServlet dispatcher(C)(C controller, string beanName, bool arrayInvokers = true,
        WebMvcConfigurer[] configurers = null, bool generated = true)
{
    if (generated)
        configurers ~= new FastPathConfigurer;
    auto beans = new StaticBeanFactory;
    beans.addBean(beanName, controller);
    auto rows = requestMappingsOf!C(beanName);
    if (!arrayInvokers)
        foreach (ref row; rows)
            row.invokeArguments = null;
    auto table = DescriptorTable.withBuiltins();
    // Hello, which ResponseEntity returns carry inside, as Flint AOT registers every described body type.
    auto descriptors = handlerDescriptorsOf!C() ~ descriptorOf!Hello();
    foreach (descriptor; descriptors)
        table.add(descriptor);
    auto support = new WebMvcConfigurationSupport(rows, null, beans, configurers, table);
    auto converters = support.getMessageConverters();
    foreach (converter; converters)
        if (auto json = cast(JacksonJsonHttpMessageConverter) converter)
            foreach (descriptor; descriptors)
                json.getMapper().descriptors().add(descriptor);
    support.setMessageConverters(converters);
    return new DispatcherServlet(support.build());
}

/// What one offer produced.
private struct Offer
{
    FastOutcome outcome;
    int status;
    string contentType;
    string content;
    /// Through `respondFields`: whether chunked, and the fields in order.
    bool chunked;
    string[2][] fields;
    /// The materialized response, when the dispatcher asked for the servlet objects.
    MockHttpServletResponse materialized;
    /// ditto: the materialized request.
    MockHttpServletRequest materializedRequest;
}

/// Offers a request as the container does: `query` undecoded pairs (the container's decoding is engine-servlet's).
private Offer offer(DispatcherServlet servlet, string method, string path, string query = null,
        string[] accept = null, bool materializes = false, size_t origins = 0, string content = null,
        string[] contentTypes = null)
{
    Offer result;
    bool parameter(scope const(char)[] name, scope FastValueVisitor visit)
    {
        size_t start;
        while (start < query.length)
        {
            size_t end = start;
            while (end < query.length && query[end] != '&')
                ++end;
            const pair = query[start .. end];
            start = end + 1;
            size_t equals = pair.length;
            foreach (i, c; pair)
                if (c == '=' && equals == pair.length)
                    equals = i;
            if (pair[0 .. equals] == name)
                visit(equals < pair.length ? pair[equals + 1 .. $] : "");
        }
        return true;
    }

    void respond(int status, string contentType, scope const(ubyte)[] content)
    {
        result.status = status;
        result.contentType = contentType;
        result.content = (cast(const(char)[]) content).idup;
    }

    void respondFields(int status, scope const(FastField)[] fields, scope const(ubyte)[] content, bool chunked)
    {
        result.status = status;
        result.chunked = chunked;
        foreach (ref field; fields)
        {
            result.fields ~= [field.name, field.value];
            if (field.name == "Content-Type")
                result.contentType = field.value;
        }
        result.content = (cast(const(char)[]) content).idup;
    }

    void materialize(out Object request, out Object response)
    {
        assert(materializes, "no materialization was expected");
        result.materialized = new MockHttpServletResponse;
        auto servletRequest = new MockHttpServletRequest(method, path);
        foreach (value; accept)
            servletRequest.addHeader("Accept", value);
        foreach (value; contentTypes)
            servletRequest.addHeader("Content-Type", value);
        if (content.length)
            servletRequest.setContent(cast(const(ubyte)[]) content);
        request = servletRequest;
        result.materializedRequest = servletRequest;
        response = result.materialized;
    }

    scope FastExchange exchange;
    exchange.method = method;
    exchange.path = path;
    exchange.acceptCount = accept.length;
    exchange.originCount = origins;
    if (accept.length)
        exchange.accept = accept[0];
    exchange.requestBody = cast(const(ubyte)[]) content;
    exchange.contentTypeCount = contentTypes.length;
    if (contentTypes.length)
        exchange.contentType = contentTypes[0];
    exchange.parameter = &parameter;
    exchange.respond = &respond;
    exchange.respondFields = &respondFields;
    exchange.materialize = &materialize;
    result.outcome = servlet.dispatchFast(exchange);
    return result;
}

@("fast path: a proved endpoint answers with the generic path's status, Content-Type and body")
unittest
{
    auto controller = new HelloController;
    auto servlet = dispatcher(controller, "helloController");
    auto plain = offer(servlet, "GET", "/hello");
    assert(plain.outcome == FastOutcome.written);
    assert(plain.status == 200 && plain.contentType == "application/json");
    assert(plain.content == `{"id":1,"text":"Hello, World!"}`, plain.content);
    assert(offer(servlet, "GET", "/hello", null, ["*/*"]).content == `{"id":2,"text":"Hello, World!"}`);
    assert(offer(servlet, "HEAD", "/hello", null, ["application/json"]).outcome == FastOutcome.written);
    assert(offer(servlet, "GET", "/hello", "name=Ann").content == `{"id":4,"text":"Hello, Ann!"}`);
    // several values join with ',', an empty single value takes the default, name[] is the fallback
    assert(offer(servlet, "GET", "/hello", "name=a&name=b").content == `{"id":5,"text":"Hello, a,b!"}`);
    assert(offer(servlet, "GET", "/hello", "name=").content == `{"id":6,"text":"Hello, World!"}`);
    assert(offer(servlet, "GET", "/hello", "name[]=x").content == `{"id":7,"text":"Hello, x!"}`);
    assert(offer(servlet, "GET", "/hello", "name=&name=").content == `{"id":8,"text":"Hello, ,!"}`);
    assert(controller.calls == 8);

    // The joined value is bound in one decoding pass into a 1,024-byte buffer: exactly full still binds, one more
    // byte, alone or joined, declines to the generic path before the handler runs.
    import std.array : replicate;

    const full = "x".replicate(1024);
    assert(offer(servlet, "GET", "/hello", "name=" ~ full).content == `{"id":9,"text":"Hello, ` ~ full ~ `!"}`);
    assert(offer(servlet, "GET", "/hello", "name=" ~ full ~ "x").outcome == FastOutcome.declined);
    const half = "y".replicate(512);
    assert(offer(servlet, "GET", "/hello", "name=" ~ half ~ "&name=" ~ half).outcome == FastOutcome.declined);
    const fits = "z".replicate(511);
    assert(offer(servlet, "GET", "/hello", "name=" ~ fits ~ "&name=" ~ fits ~ "z")
            .content == `{"id":10,"text":"Hello, ` ~ fits ~ "," ~ fits ~ `z!"}`);
    assert(controller.calls == 10);
}

@("fast path: requests outside the proof are declined before the handler runs")
unittest
{
    auto controller = new HelloController;
    auto servlet = dispatcher(controller, "helloController");
    assert(offer(servlet, "POST", "/hello").outcome == FastOutcome.declined);
    assert(offer(servlet, "OPTIONS", "/hello").outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/hello", null, ["application/xml"]).outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/hello", null, ["text/html"]).outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/hello", null, ["application/json;q=0.9"]).outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/hello", null, ["*/*", "*/*"]).outcome == FastOutcome.declined);
    assert(controller.calls == 0, "a declined request must not have run the handler");
    // S6: a GET no route takes is the generic dispatch on the servlet objects.
    foreach (path; ["/hello/", "/nope", "/deep/er/nope.json", "/a/../nope", "/x;y/nope"])
        unmatchedLikeGeneric(servlet, path);
    // An encoded path the generic lookup decodes to /hello: the handler answers it on the servlet objects (its body
    // carries the call count, so it is not compared byte for byte).
    auto encoded = offer(servlet, "GET", "/hell%6F", null, null, true);
    assert(encoded.outcome == FastOutcome.materialized && encoded.materialized.getStatus() == 200);
    unmatchedLikeGeneric(servlet, "/nope", ["text/html"]);
}

@("fast path: no table without the rows' array invokers, with an interceptor, or for a @CrossOrigin handler")
unittest
{
    auto controller = new HelloController;
    assert(offer(dispatcher(controller, "helloController", false), "GET", "/hello").outcome == FastOutcome.declined);
    auto interceptors = cast(WebMvcConfigurer) new class WebMvcConfigurer
    {
        override void addInterceptors(InterceptorRegistry registry)
        {
            registry.addInterceptor(new CountingInterceptor);
        }
    };
    assert(offer(dispatcher(controller, "helloController", true, [interceptors]), "GET", "/hello")
            .outcome == FastOutcome.declined);
    // A @CrossOrigin handler is S3's: see the CORS case below.
    assert(controller.calls == 0);
}

@("fast path: a ResponseEntity return is HttpEntityMethodProcessor's, so the proof leaves the row out")
unittest
{
    assert(offer(dispatcher(new EntityController, "entityController"), "GET", "/entity").outcome == FastOutcome
            .declined);
}

@("fast path: a null @ResponseBody value is a 200 without Content-Type or body, as writeWithMessageConverters")
unittest
{
    auto controller = new NullController;
    auto answer = offer(dispatcher(controller, "nullController"), "GET", "/nothing");
    assert(answer.outcome == FastOutcome.written && answer.status == 200);
    assert(answer.contentType is null && answer.content.length == 0);
    assert(controller.calls == 1);
}

@("fast path: pay-for-use; without the generated configurer there is no table, even for a fast row")
unittest
{
    auto controller = new HelloController;
    assert(offer(dispatcher(controller, "helloController", true, null, false), "GET", "/hello")
            .outcome == FastOutcome.declined);
    assert(controller.calls == 0);
}

@("fast path S1: a @PathVariable int, long or string binds from the template; other values decline")
unittest
{
    auto controller = new OwnerController;
    auto servlet = dispatcher(controller, "ownerController");
    const one = offer(servlet, "GET", "/owners/1", null, ["*/*"]);
    assert(one.outcome == FastOutcome.written && one.status == 200 && one.contentType == "application/json");
    assert(one.content == `{"id":1,"text":"owner"}`, one.content);
    assert(offer(servlet, "GET", "/owners/0").content == `{"id":0,"text":"owner"}`);
    assert(offer(servlet, "GET", "/owners/999999999").content == `{"id":999999999,"text":"owner"}`);
    assert(offer(servlet, "GET", "/owners/12/pets/max").content == `{"id":12,"text":"max"}`);
    assert(controller.calls == 4);
    // Everything the fast path does not bind exactly goes generic, before the handler runs.
    foreach (path; [
        "/owners/abc", "/owners/-1", "/owners/007", "/owners/+5", "/owners/0x1A",
        "/owners/1234567890", "/owners/", "/owners//",
        "/owners/1/", "/owners/1/pets/a%20b", "/owners/1/pets/a;v=1", "/owners/1/pets/", "/owners",
        "/owners/1/x"
    ])
        unmatchedLikeGeneric(servlet, path); // S6: the generic dispatch, on the servlet objects
    assert(offer(servlet, "DELETE", "/owners/1").outcome == FastOutcome.declined);
    // The literal /owners/find is not a canonical number, so it does not overlap the numeric template; it is
    // a route of its own.
    assert(offer(servlet, "GET", "/owners/find").content == `{"id":0,"text":"find"}`);
}

@("fast path S1: a template that another GET mapping could also match gets no route")
unittest
{
    auto servlet = dispatcher(new ShadowController, "shadowController");
    unmatchedLikeGeneric(servlet, "/items/3"); // S6: the generic dispatch, on the servlet objects
    // The literal route itself is still proved.
    assert(offer(servlet, "GET", "/items/7").content == `{"id":7,"text":"seven"}`);
}

@("fast path S2: a ResponseEntity is written as HttpEntityMethodProcessor writes it, or handed to it")
unittest
{
    auto controller = new EntityRoutesController;
    auto servlet = dispatcher(controller, "entityRoutesController");
    // A body: the entity's status, the negotiated Content-Type, and chunked (the processor flushes).
    const created = offer(servlet, "GET", "/entities/1", null, ["*/*"]);
    assert(created.outcome == FastOutcome.written && created.status == 201 && created.chunked);
    assert(created.fields == [["Content-Type", "application/json"]]);
    assert(created.content == `{"id":1,"text":"entity"}`, created.content);
    // No body: no Content-Type, not chunked (Content-Length: 0).
    const missing = offer(servlet, "GET", "/entities/0");
    assert(missing.outcome == FastOutcome.written && missing.status == 404 && !missing.chunked);
    assert(missing.fields.length == 0 && missing.content.length == 0);
    // Headers of the entity's own: the handler ran once, and the generic processor writes the materialized
    // response, headers included.
    auto extra = offer(servlet, "GET", "/entities/2", null, null, true);
    assert(extra.outcome == FastOutcome.materialized);
    assert(extra.materialized.getStatus() == 200);
    assert(extra.materialized.getHeader("X-Extra") == "1");
    assert(extra.materialized.getContentAsString() == `{"id":2,"text":"headers"}`,
            extra.materialized.getContentAsString());
    assert(controller.calls == 3);
    // The proved body type is remembered per Accept key; a body of another type in the same slot is proved again
    // (a string goes to the string converter, so the generic processor writes it), and the first type still writes.
    auto text = offer(servlet, "GET", "/entities/3", null, ["*/*"], true);
    assert(text.outcome == FastOutcome.materialized
            && text.materialized.getContentAsString() == "text", text.materialized.getContentAsString());
    const again = offer(servlet, "GET", "/entities/1", null, ["*/*"]);
    assert(again.outcome == FastOutcome.written && again.content == `{"id":1,"text":"entity"}`, again.content);
    assert(controller.calls == 5);
    // A mapping without produces keeps the generic path (the producible type would depend on the body).
    assert(offer(dispatcher(new EntityController, "entityController"), "GET", "/entity").outcome == FastOutcome
            .declined);
}

@("fast path S3: a @CrossOrigin handler writes DefaultCorsProcessor's Vary fields first; an Origin goes generic")
unittest
{
    auto servlet = dispatcher(new CorsController, "corsController");
    const plain = offer(servlet, "GET", "/cors", "name=Ann");
    assert(plain.outcome == FastOutcome.written && plain.status == 200 && !plain.chunked);
    assert(plain.fields == [
        ["Vary", "Origin"], ["Vary", "Access-Control-Request-Method"],
        ["Vary", "Access-Control-Request-Headers"], ["Content-Type", "application/json"]
    ], plain.fields[0][0]);
    assert(plain.content == `{"id":1,"text":"Ann"}`, plain.content);
    // Any Origin field (a CORS request, or a same-origin one) is DefaultCorsProcessor's to answer.
    assert(offer(servlet, "GET", "/cors", null, null, false, 1).outcome == FastOutcome.declined);
    // A handler without @CrossOrigin writes no Vary, Origin or not.
    const hello = offer(dispatcher(new HelloController, "helloController"), "GET", "/hello", null, null, false, 1);
    assert(hello.outcome == FastOutcome.written && hello.fields == [
        ["Content-Type", "application/json"]
    ]);
}

/// S5: an owner as petclinic-rest posts it.
struct PostedOwner
{
    string firstName; ///
    string telephone; ///
}

// Rejects a blank first name and a non-numeric telephone, as the DTO's constraints would.
private final class PostedOwnerValidator : imported!"flint.validation".Validator
{
    bool supports(string typeName)
    {
        return typeName.length != 0;
    }

    void validate(Any target, imported!"flint.validation".Errors errors)
    {
        const owner = target.get!PostedOwner;
        if (owner.firstName.length == 0)
            errors.rejectValue("firstName", "NotBlank", "must not be blank");
        foreach (c; owner.telephone)
            if (c < '0' || c > '9')
            {
                errors.rejectValue("telephone", "Pattern", "must match \"^[0-9]*$\"");
                break;
            }
    }
}

/// S5: `POST /owners`, consuming and producing JSON, with a validated body.
@RestController
class PostingController
{
    long calls; ///

    ///
    @PostMapping(value: ["/owners"], consumes: ["application/json"], produces: ["application/json"])
    PostedOwner addOwner(@Valid @RequestBody PostedOwner owner)
    {
        ++calls;
        return owner;
    }
}

/// S5: the advice petclinic-rest's resembles: a 400 problem listing the rejected fields.
@RestControllerAdvice
class PostingAdvice
{
    ///
    @ExceptionHandler
    ResponseEntity handle(MethodArgumentNotValidException ex)
    {
        auto detail = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, "Validation failed");
        string fields;
        foreach (error; ex.getBindingResult().getFieldErrors().toArray())
            fields ~= (fields.length ? "," : "") ~ ex.getObjectName() ~ "." ~ error.getField();
        detail.setTitle(fields);
        return ResponseEntity.badRequest().body(detail);
    }
}

// The same controller, advice and validator, through the generic dispatch (MockMvc) and through the fast path.
private DispatcherServlet postingDispatcher(PostingController controller)
{
    import flint.web.servlet.mvc.method.aot : exceptionHandlersOf;

    auto beans = new StaticBeanFactory;
    beans.addBean("postingController", controller);
    beans.addBean("postingAdvice", new PostingAdvice);
    auto rows = requestMappingsOf!PostingController("postingController");
    auto table = DescriptorTable.withBuiltins();
    auto descriptors = handlerDescriptorsOf!PostingController() ~ handlerDescriptorsOf!PostingAdvice();
    foreach (descriptor; descriptors)
        table.add(descriptor);
    auto support = new WebMvcConfigurationSupport(rows, exceptionHandlersOf!PostingAdvice("postingAdvice"),
            beans, [cast(WebMvcConfigurer) new FastPathConfigurer], table);
    support.setValidator(new PostedOwnerValidator);
    auto converters = support.getMessageConverters();
    foreach (converter; converters)
        if (auto json = cast(JacksonJsonHttpMessageConverter) converter)
            foreach (descriptor; descriptors)
                json.getMapper().descriptors().add(descriptor);
    support.setMessageConverters(converters);
    return new DispatcherServlet(support.build());
}

// The generic dispatch's response to the same request.
private MockHttpServletResponse generic(DispatcherServlet servlet, string content,
        string[] contentTypes, string[] accept = null)
{
    import flint.jakarta.servlet : ServletRequest, ServletResponse;

    auto request = new MockHttpServletRequest("POST", "/owners");
    foreach (value; accept)
        request.addHeader("Accept", value);
    foreach (value; contentTypes)
        request.addHeader("Content-Type", value);
    request.setContent(cast(const(ubyte)[]) content);
    auto response = new MockHttpServletResponse;
    servlet.service(cast(ServletRequest) request, cast(ServletResponse) response);
    return response;
}

@("fast path S5: a validated POST binds and writes as the generic path; a failure goes to the advice")
unittest
{
    auto controller = new PostingController;
    auto servlet = postingDispatcher(controller);
    const valid = `{"firstName":"George","telephone":"6085551023"}`;
    const invalid = `{"firstName":"","telephone":"01234abcde"}`;
    foreach (accept; [cast(string[]) null, ["*/*"], ["application/json"]])
    {
        // A valid body: the handler runs once, and the response is the generic one.
        const before = controller.calls;
        auto fast = offer(servlet, "POST", "/owners", null, accept, false, 0, valid, [
            "application/json"
        ]);
        auto reference = generic(servlet, valid, ["application/json"], accept);
        assert(fast.outcome == FastOutcome.written && controller.calls == before + 2);
        assert(fast.status == reference.getStatus() && fast.contentType == reference.getContentType());
        assert(fast.content == reference.getContentAsString(), fast.content);
        // An invalid body: the handler does not run; the advice answers on the materialized request, as generic.
        auto failed = offer(servlet, "POST", "/owners", null, accept, true, 0, invalid, [
            "application/json"
        ]);
        auto expected = generic(servlet, invalid, ["application/json"], accept);
        assert(failed.outcome == FastOutcome.materialized && controller.calls == before + 2);
        assert(failed.materialized.getStatus() == 400 && expected.getStatus() == 400);
        assert(failed.materialized.getContentType() == expected.getContentType());
        assert(failed.materialized.getContentAsString() == expected.getContentAsString(),
                failed.materialized.getContentAsString());
    }
}

@("fast path S5: what the route does not bind exactly declines before anything runs")
unittest
{
    auto controller = new PostingController;
    auto servlet = postingDispatcher(controller);
    const valid = `{"firstName":"George","telephone":"6085551023"}`;
    // Another Content-Type value, two fields, none; an empty or malformed body; a GET.
    assert(offer(servlet, "POST", "/owners", null, null, false, 0, valid,
            ["application/json;charset=UTF-8"]).outcome == FastOutcome.declined);
    assert(offer(servlet, "POST", "/owners", null, null, false, 0, valid, [
        "application/json", "application/json"
    ]).outcome == FastOutcome.declined);
    assert(offer(servlet, "POST", "/owners", null, null, false, 0, valid).outcome == FastOutcome.declined);
    assert(offer(servlet, "POST", "/owners", null, null, false, 0, "", ["application/json"])
            .outcome == FastOutcome.declined);
    assert(offer(servlet, "POST", "/owners", null, null, false, 0, `{"firstName":`,
            ["application/json"]).outcome == FastOutcome.declined);
    assert(controller.calls == 0);
    unmatchedLikeGeneric(servlet, "/owners"); // S6: the generic 405, on the servlet objects
}

// S6: a GET no route takes is materialized and dispatched generically: the same status, error message, Content-Type
// and body as the same request through the servlet's own service. A route that matches the path but does not bind
// it declines instead (the container then takes the generic path itself).
private void unmatchedLikeGeneric(DispatcherServlet servlet, string path, string[] accept = null)
{
    import flint.jakarta.servlet : ServletRequest, ServletResponse;

    auto fast = offer(servlet, "GET", path, null, accept, true);
    assert(fast.outcome != FastOutcome.written, path);
    if (fast.outcome == FastOutcome.declined)
        return;
    auto request = new MockHttpServletRequest("GET", path);
    foreach (value; accept)
        request.addHeader("Accept", value);
    auto expected = new MockHttpServletResponse;
    servlet.service(cast(ServletRequest) request, cast(ServletResponse) expected);
    auto actual = fast.materialized;
    assert(actual.getStatus() == expected.getStatus(), path);
    assert(actual.getErrorMessage() == expected.getErrorMessage(), path ~ ": " ~ actual.getErrorMessage());
    assert(actual.getContentType() == expected.getContentType(), path);
    assert(actual.getContentAsString() == expected.getContentAsString(), path);
    // web-http's review: the whole set of request attributes the dispatch leaves (the error page reads any of them),
    // by name and by the type of the value.
    assert(attributeTypes(fast.materializedRequest) == attributeTypes(request), path);
}

// A request's attributes, as `name: type` in name order.
private string[] attributeTypes(MockHttpServletRequest request)
{
    import std.algorithm.sorting : sort;

    string[] result;
    foreach (name; request.getAttributeNames())
        result ~= name ~ ": " ~ request.getAttribute(name).typeName();
    result.sort();
    return result;
}

@("fast path S6: an unmatched GET skips the first mapping's lookup and answers the generic 404")
unittest
{
    auto servlet = dispatcher(new HelloController, "helloController");
    // The generic dispatch's 404 comes from the resource handler's NoResourceFoundException.
    auto fast = offer(servlet, "GET", "/nope", null, null, true);
    assert(fast.materialized.getStatus() == 404);
    assert(fast.materialized.getErrorMessage() == "No static resource nope.", fast.materialized.getErrorMessage());
}
