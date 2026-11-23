# Phase 1: the web stack (spring-web, spring-webmvc, the servlet layer, MockMvc)

Status: design, owned by the web-mvc session. Implementation moves to `flint-framework` at cutover.

This note records how Flint ports the Phase 1 web stack of Spring Framework v7.1.0 and the error handling of Spring Boot v4.2.0. It follows ADR-030 and the rulebook ([`../api-mapping.md`](../api-mapping.md)). Where it needs a rule the rulebook doesn't have yet, it proposes one under "Rulebook proposals".

## Goal

gs-rest-service, gs-relational-data-access and spring-petclinic-rest give byte-identical status, headers and bodies to Spring Boot v4.2.0, error bodies included, and beat Go on every metric. This note covers the web part of that proof:
- the `flint.http` and `flint.web` types application code touches;
- `DispatcherServlet` and its strategies, driven by Flint AOT's request-mapping tables;
- a minimal servlet API over `flint.engine.web`, with no servlet container;
- MockMvc.

## Packages

The engine rename (`flint.web` → `flint.engine.web`, DUB `flint:web` → `flint:engine-web`) has not landed yet. Until it does, these packages use interim DUB names and directories. A mechanical rename at cutover gives them their final names.

| Spring artifact | Final DUB name | Interim DUB name and directory | D modules |
| --- | --- | --- | --- |
| spring-web | `flint:web` | `flint:framework-web`, `packages/framework-web` | `flint.http`, `flint.http.converter`, `flint.http.converter.json`, `flint.http.server`, `flint.web`, `flint.web.bind`, `flint.web.bind.annotation`, `flint.web.server`, `flint.web.util`, `flint.web.cors`, `flint.web.method`, `flint.web.method.annotation`, `flint.web.context.request` |
| spring-webmvc | `flint:webmvc` | `flint:framework-webmvc`, `packages/framework-webmvc` | `flint.web.servlet`, `flint.web.servlet.config.annotation`, `flint.web.servlet.handler`, `flint.web.servlet.mvc.method`, `flint.web.servlet.mvc.method.annotation`, `flint.web.servlet.mvc.support` |
| jakarta.servlet-api 6.1 (EPL-2.0 module) | `flint:jakarta-servlet` | same, `packages/jakarta-servlet` | `flint.jakarta.servlet`, `flint.jakarta.servlet.http` |
| spring-test (MockMvc part) | see open question 1 | `flint:framework-test`, `packages/framework-test` | `flint.test.web.servlet`, `flint.test.web.servlet.request`, `flint.test.web.servlet.result`, `flint.mock.web` |
| spring-boot-webmvc (error handling) | `flint:boot-webmvc` | handed to the boot session | `flint.boot.webmvc.autoconfigure.error` |

Dependency edges:
- `framework-web` depends on `flint:core` and `flint:java` (framework-core) and on `flint:jackson-databind` (third-party-apis) only for the Jackson converter.
- `jakarta-servlet` depends on nothing in the API layer. Its transport bridge depends on `flint:engine-web`.
- `framework-webmvc` depends on `framework-web`, `jakarta-servlet`, `flint:context` and `flint:engine-aot`.
- `framework-test` depends on `framework-webmvc` and on the JsonPath engine (open question 2).

`flint.web.servlet` (spring-webmvc) and `flint.jakarta.servlet` (the servlet API) are different namespaces, as in Java.

## API decisions

### Value types are structs

ADR-030 section 5 makes `HttpHeaders`, `MediaType`, `HttpStatus` and `ResponseEntity` structs, so they carry no class metadata.
- **`HttpStatus` and `HttpMethod`** are structs with `static immutable` constants (`HttpStatus.NOT_FOUND`), Java's methods (`value()`, `series()`, `getReasonPhrase()`, `is4xxClientError()`, `name()`, `valueOf(int)`, `resolve(int)`) and `alias this` to `HttpStatusCode`, so every API that takes an `HttpStatusCode` takes an `HttpStatus`. See proposal R15.
- **`HttpStatusCode`** is a struct holding the code, with `valueOf(int)` returning the `HttpStatus` constant when one exists.
- **`HttpHeaders`** is a struct with reference semantics: it holds one pointer to a case-insensitive, insertion-ordered store, allocated on first write. Copies share the store, as Java references do, so `ResponseEntity.ok().headers(h)` and later `h.add(...)` behave as in Java. `new HttpHeaders()` works because D dereferences struct pointers on member access.
- **`MediaType`** is a struct wrapping spring-core's `MimeType` (also a struct, framework-core) through `alias this`, so `MediaType` converts to `MimeType` where Java widens. Its constants (`MediaType.APPLICATION_JSON`, `APPLICATION_JSON_VALUE`) keep Java's names.

### `ResponseEntity` is erased

`ResponseEntity<T>` appears in signatures as the non-template struct `ResponseEntity` (rule R12 plus the erased core of ADR-030 section 5). It holds an `HttpStatusCode`, an `HttpHeaders` and the body as `flint.engine.aot.Any`. Java's factories are kept: `ok()`, `ok(body)`, `of(Optional)`, `ofNullable(body)`, `status(code)`, `created(uri)`, `accepted()`, `noContent()`, `badRequest()`, `notFound()`, `unprocessableContent()`, `internalServerError()`, `ResponseEntity.BodyBuilder` and `HeadersBuilder`. Each templated `body(T)` is one line that captures `T`'s descriptor into an `Any`.

`RequestEntity` and `HttpEntity` follow the same shape.

### Annotations

`flint.web.bind.annotation` is a leaf module of UDA structs (R2). `@RestController` is `@Controller @ResponseBody`, and `@GetMapping` is `@RequestMapping(method: RequestMethod.GET)`. Flint AOT composes these at build time, as Spring's `MergedAnnotations` does at run time. `value` and `path` are aliases (`@AliasFor`), and either spelling works: `@GetMapping("/greeting")`, `@GetMapping(path: "/greeting")`. Array attributes take D arrays: `@RequestMapping(value: ["/a", "/b"])`.

`@RequestParam(value: "name", defaultValue: "World")` keeps Java's `ValueConstants.DEFAULT_NONE` sentinel for "no default".

### Exceptions

- `ResponseStatusException : ErrorResponseException : NestedRuntimeException : RuntimeException` (R8).
- `ErrorResponse` is a Java interface with abstract and default methods, so its defaults are `mixin ErrorResponse.Defaults` (R3).
- The framework's control-flow exceptions (`NoResourceFoundException`, `HttpRequestMethodNotSupportedException`, `MethodArgumentNotValidException`, `MissingServletRequestParameterException`, `MethodArgumentTypeMismatchException`, `HttpMessageNotReadableException`) skip backtrace capture. They are thrown on the 404, 405, 400 and validation paths, which have their own p99 tests.

### `WebMvcConfigurer` and `HandlerInterceptor`

Both are all-default interfaces, so both are abstract classes (deviation D-3). `HandlerInterceptor` is used through `InterceptorRegistry.addInterceptor`, which takes the abstract class.

### Strings (R14)

`UriComponentsBuilder`, `UriComponents`, `UriUtils` and `AntPathMatcher`/`PathPattern` index UTF-8 bytes. Their ported tests run again with non-ASCII paths and query values (percent-encoding works on UTF-8 bytes in both Java and D, so encoded output is identical).

## Request execution

### Handlers run on reactor fibers

ADR-030 section 4 retires the single worker thread. A request runs on its reactor fiber from the first byte to the last:
1. `flint.engine.web` parses the request into the request arena (`nothrow @nogc`, unchanged).
2. The servlet bridge wraps it as a `HttpServletRequest` without copying. Strings that user code can see are copied out of the arena into GC memory on first access, so arena memory never reaches user code.
3. `DispatcherServlet.service` runs on the same fiber, with the GC and exceptions allowed. `JdbcTemplate` and other blocking-style calls suspend the fiber through `TaskWaker`, as a virtual thread parks.
4. The `HttpServletResponse` buffers the body in a GC buffer. When the response commits, the bridge copies status, headers and body into the request arena and hands them to the transport.

The engine needs one addition for this: a route kind whose handler may allocate and throw, run on the request fiber. Today the engine offers `nothrow @nogc` owner-loop handlers and the `@WorkerController` thread. This addition is coordinated with the session that owns the engine rename.

### `DispatcherServlet`

`DispatcherServlet` keeps Spring's shape and strategy interfaces:

```
DispatcherServlet.doDispatch
  HandlerMapping.getHandler            RequestMappingHandlerMapping (AOT tables), then the resource handler
  HandlerInterceptor.preHandle
  HandlerAdapter.handle                RequestMappingHandlerAdapter
    HandlerMethodArgumentResolver*     @PathVariable, @RequestParam, @RequestHeader, @CookieValue,
                                       @RequestBody, HttpServletRequest/Response, HttpEntity, UriComponentsBuilder
    invoke                             generated thunk
    HandlerMethodReturnValueHandler*   ResponseEntity/HttpEntity, @ResponseBody, void + @ResponseStatus
  HandlerInterceptor.postHandle / afterCompletion
  processHandlerException
    ExceptionHandlerExceptionResolver  @ExceptionHandler in the controller, then @ControllerAdvice beans in order
    ResponseStatusExceptionResolver    @ResponseStatus on the exception type, ResponseStatusException
    DefaultHandlerExceptionResolver    Spring's standard exceptions to sendError(status)
```

The strategies are ordinary D classes, so a user can register their own resolver or converter exactly as in Spring.

### AOT request-mapping tables

Flint AOT emits one table per controller, in plain non-template D:

```d
// generated: GreetingController
immutable RequestMappingInfo[1] mappings = [
    RequestMappingInfo(patterns: ["/greeting"], methods: [RequestMethod.GET], produces: [], consumes: [],
                       params: [], headers: [], handler: &invoke_greeting, parameters: greetingParameters[]),
];
```

Each `MethodParameter` row names its resolver kind, the binding name, `required`, `defaultValue` and the descriptor of its declared type. The invoker thunk takes the controller object and an `Any[]` of resolved arguments and returns an `Any`. `RequestMappingHandlerMapping` builds its `PathPattern` lookup from all tables at startup.

The table types live in `flint.web.method` (`HandlerMethod`, `MethodParameter`) and `flint.web.servlet.mvc.method` (`RequestMappingInfo`). They are the contract with the flint-aot session. Until the generator emits them, `flint.web.servlet.mvc.method.annotation.internal` builds the identical rows at compile time from a controller's UDAs. That template is one of the request-mapping internals the rulebook allows to reflect, and it is deleted when the generator lands.

### Message conversion

`HttpMessageConverter` keeps Spring's interface: `canRead`, `canWrite`, `getSupportedMediaTypes`, `read`, `write`. `Class<?>` becomes the type's descriptor (R4). The default list matches Spring Boot's: `ByteArrayHttpMessageConverter`, `StringHttpMessageConverter` (UTF-8 for `text/plain`, as Boot configures it), `ResourceHttpMessageConverter`, and `JacksonJsonHttpMessageConverter`. The Jackson converter calls the third-party-apis session's `flint.jackson.databind.ObjectMapper` with the body's descriptor.

Content negotiation follows `AbstractMessageConverterMethodProcessor.writeWithMessageConverters`: the `Accept` header, the producible types, specificity and quality sorting, and the selected type's parameters (`application/json` without a charset, as Spring 7 writes it).

## Byte-identical output

The proof-harness suites compare status, headers and bodies with Spring Boot on Tomcat. What Flint must reproduce, and where it comes from:

| Output | Spring Boot v4.2.0 on Tomcat | Owner in Flint |
| --- | --- | --- |
| Status line | `HTTP/1.1 200 ` (Tomcat writes no reason phrase) | engine transport |
| Message-converter bodies | `Transfer-Encoding: chunked`, because the converter flushes and commits the response before it completes | servlet bridge |
| Bodies set without a converter flush (`sendError` with no error page, empty bodies) | `Content-Length` | servlet bridge |
| Header order | application headers in insertion order, then `Content-Type`, `Content-Language`, `Content-Length` or `Transfer-Encoding`, `Date`, `Connection` | servlet bridge and transport |
| `Content-Type` for JSON | `application/json` | Jackson converter |
| 404 for an unmapped path | `NoResourceFoundException` → `sendError(404)` → error dispatch to `/error` → `{"timestamp":"…","status":404,"error":"Not Found","path":"/nope"}` | webmvc, Boot error controller |
| 405 | `HttpRequestMethodNotSupportedException` → `Allow` header → error body with status 405 | webmvc |
| 400 for a validation failure | `MethodArgumentNotValidException` → error body; `"errors"` and `"message"` only when `server.error.include-binding-errors` and `include-message` say so | webmvc, Boot error controller |
| `ProblemDetail` (`flint.mvc.problemdetails.enabled=true`, or an `ErrorResponse` returned from `@ExceptionHandler`) | `application/problem+json`, `{"type":"about:blank","title":"Not Found","status":404,"detail":"…","instance":"/nope"}` | webmvc, Jackson |
| Error `timestamp` | `java.util.Date` through Jackson 3: `yyyy-MM-dd'T'HH:mm:ss.SSSXXX` in UTC, so `+00:00` | Boot error controller, Jackson |

Tomcat's error-page forward (`StandardHostValve`) is reproduced by the servlet bridge: `sendError` records the status and message, and when the handler returns the bridge dispatches once to the error controller with the `jakarta.servlet.error.*` request attributes set, as Tomcat does.

## Proof

- **Upstream tests.** Each ported class ports its JUnit tests (`HttpStatusTests`, `HttpHeadersTests`, `MediaTypeTests`, `ResponseEntityTests`, `ProblemDetailTests`, `UriComponentsBuilderTests`, `RequestMappingHandlerMappingTests`, `RequestResponseBodyMethodProcessorTests`, `ExceptionHandlerExceptionResolverTests`, `DefaultHandlerExceptionResolverTests`, `ResponseEntityExceptionHandlerTests`, MockMvc's own tests). Counts of ported, passing and excluded tests, with reasons, are kept in "Upstream test counts" below.
- **gs-rest-service.** Its `GreetingController` and `GreetingControllerTests` run unchanged except for the rulebook's syntax: through MockMvc, and over real HTTP through the servlet bridge.
- **p99.** The 200, 404 and validation-error paths are measured separately under `load_bench`.
- **API coverage.** `api/mapping.json` classifies every element of the ported packages; whole subpackages outside Phase 1 are `deferred` with their phase.

## Rulebook proposals

- **R15: Java enums.** An enum with only constants becomes a D `enum` with the same member names. An enum with fields, methods or interfaces becomes a struct with `static immutable` constants and Java's `name()`, `ordinal()`, `values()`, `valueOf(String)` and `toString()`. If it implements a Java interface that other types also implement (`HttpStatus implements HttpStatusCode`), the interface becomes a struct too and the enum struct converts to it through `alias this`.

## Open questions

1. **spring-test's DUB name.** Spring's artifact name gives `flint:test`, which is the base library's name, and `org.springframework.test` → `flint.test` shares a namespace with the base library `flint.test`. The modules don't collide (`flint.test.web.servlet` is new), but the DUB name does. Proposal: `flint:framework-test`.
2. **JsonPath.** MockMvc's `jsonPath(...)` needs the Jayway JsonPath engine (Apache-2.0). Coordinated with the third-party-apis session: who ports it, and over which JSON tree.
3. **Engine route kind.** The fiber route kind that may allocate and throw (above), coordinated with the owner of `flint.engine.web`.

## Upstream test counts

| Upstream test class | Ported | Passing | Excluded (reason) |
| --- | --- | --- | --- |
| (filled in as each slice lands) | | | |
