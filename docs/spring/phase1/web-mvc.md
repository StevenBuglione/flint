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
| spring-web | `flint:web` | `flint:framework-web`, `framework/web` | `flint.http`, `flint.http.converter`, `flint.http.converter.json`, `flint.http.server`, `flint.web`, `flint.web.bind`, `flint.web.bind.annotation`, `flint.web.server`, `flint.web.util`, `flint.web.cors`, `flint.web.method`, `flint.web.method.annotation`, `flint.web.context.request` |
| spring-webmvc | `flint:webmvc` | `flint:framework-webmvc`, `framework/webmvc` | `flint.web.servlet`, `flint.web.servlet.config.annotation`, `flint.web.servlet.handler`, `flint.web.servlet.mvc.method`, `flint.web.servlet.mvc.method.annotation`, `flint.web.servlet.mvc.support` |
| jakarta.servlet-api 6.1 (EPL-2.0 module) | `flint:jakarta-servlet` | same, `framework/jakarta-servlet` | `flint.jakarta.servlet`, `flint.jakarta.servlet.http` |
| spring-test (MockMvc part) | see open question 1 | `flint:framework-test`, `framework/framework-test` | `flint.test.web.servlet`, `flint.test.web.servlet.request`, `flint.test.web.servlet.result`, `flint.mock.web` |
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

The rows are contract 1's `HandlerMapping` and `ExceptionHandlerSpec` (`flint.engine.aot.mapping`, docs/spring/aot-contract.md section 4.5). `RequestMappingHandlerMapping` turns each row into a `RequestMappingInfo` and a `HandlerMethod` whose bean comes from the AOT `BeanFactory`. Until the generator emits rows, `flint.web.servlet.mvc.method.aot` builds identical ones at compile time from a controller's UDAs, through engine-aot's `mergedAnnotations`. It is one of the request-mapping internals the rulebook allows to reflect, and it is deleted when the generator lands. Requested from flint-aot for contract 2: `beanType`, class-level annotations for `@CrossOrigin` combination, advice `assignableTypes`/`annotations`, `@ExceptionHandler(produces)`, and descriptors for exception classes carrying `@ResponseStatus`.

### Message conversion

`HttpMessageConverter` keeps Spring's interface: `canRead`, `canWrite`, `getSupportedMediaTypes`, `read`, `write`. `Class<?>` becomes the type's descriptor (R4). The default list matches Spring Boot's: `ByteArrayHttpMessageConverter`, `StringHttpMessageConverter` (UTF-8 for `text/plain`, as Boot configures it), `ResourceHttpMessageConverter`, and `JacksonJsonHttpMessageConverter`. The Jackson converter calls the third-party-apis session's `flint.jackson.databind.ObjectMapper` with the body's descriptor.

Content negotiation follows `AbstractMessageConverterMethodProcessor.writeWithMessageConverters`: the `Accept` header, the producible types, specificity and quality sorting, and the selected type's parameters (`application/json` without a charset, as Spring 7 writes it).

## Byte-identical output

The proof-harness suites (`benchmarks/spring/suites`) compare status, every header except `Date`, and bodies with Spring Boot v4.2.0 on Tomcat, from goldens recorded off the Java reference. What Flint must reproduce, and where it comes from:

| Output | Spring Boot v4.2.0 on Tomcat (from `golden/gs-rest-service.json`) | Owner in Flint |
| --- | --- | --- |
| Status line | `HTTP/1.1 200 ` (no reason phrase) | engine transport |
| `@ResponseBody` bodies | `Content-Length`: Spring 7's `ServletServerHttpResponse` makes `getBody().flush()` a no-op, so the container sees the whole body before committing | servlet bridge |
| `ResponseEntity`, `ProblemDetail` and Boot error bodies | `Transfer-Encoding: chunked`: `HttpEntityMethodProcessor` ends with `outputMessage.flush()`, which commits once a body was written | servlet bridge |
| Empty bodies (406 from the error controller, OPTIONS) | `Content-Length: 0`: no body was written, so `flush()` does not commit | servlet bridge |
| Header order | application headers in insertion order, then `Content-Type`, `Content-Language`, `Content-Length` or `Transfer-Encoding` (Tomcat's `prepareResponse`) | servlet bridge |
| `Content-Type` for JSON | `application/json`, no charset | Jackson converter |
| JSON property order | a record's (D struct's) properties in declaration order; a class's alphabetically (Jackson 3); `ProblemDetail`: `detail`, `instance`, `status`, `title`, `type`, then its extension properties | Jackson (third-party-apis) |
| Query parameters | the servlet container decodes `+` as a space (`Jane+Q%20Public` → `Jane Q Public`); MockMvc does not, as in Spring | servlet bridge / MockMvc |
| Repeated `@RequestParam String` | joined with `,` (`ArrayToStringConverter`) | webmvc |
| Empty `@RequestParam` with a default | the default | webmvc |
| 406 (`Accept: application/xml`) | the handler runs first; then `Accept: application/json, application/*+json`, `Content-Length: 0` | webmvc, Boot error controller |
| HEAD | the GET handler runs; `Content-Length` of the body that is not sent | webmvc, servlet bridge |
| OPTIONS | `Allow: GET,HEAD,OPTIONS`, empty `Accept-Patch` and `Accept-Query` (`HttpOptionsHandler`), `Content-Length: 0` | webmvc |
| 404 for an unmapped path or a trailing slash | `NoResourceFoundException` → `sendError(404)` → error dispatch → `{"timestamp":"…Z","status":404,"error":"Not Found","path":"/nope"}`, chunked | webmvc, Boot error controller |
| 405 | `Allow: GET`, then the error body with status 405, chunked | webmvc, Boot error controller |
| Browser 404 (`Accept: text/html`) | the Whitelabel page: `text/html;charset=UTF-8`, `Content-Language: en-US`, `Content-Length: 275` | Boot error view, servlet bridge |
| Error `timestamp` | an ISO-8601 UTC instant ending in `Z` | Boot error controller, Jackson |

Tomcat's error-page forward (`StandardHostValve`) is reproduced by the servlet bridge: `sendError` records the status and message, and when the handler returns the bridge dispatches once to the error controller with the `jakarta.servlet.error.*` request attributes set, as Tomcat does. The error controller itself (`BasicErrorController`, `DefaultErrorAttributes`, the Whitelabel view) is spring-boot-webmvc, owned by the boot session.

## Real HTTP serving

### `FiberRoute` (flint.engine.web)

A fiber route is the engine's third route kind, beside owner-loop handlers and stream routes:

```d
alias FiberHandler = void delegate(ref scope Request, ref scope RequestContext, scope FiberResponse) @safe;
Error Server.routeFiber(FiberRoute(handler));   // at most one; serves every request no other route serves
```

- **Execution.** The handler runs on the request's reactor task fiber, a druntime `Fiber` whose stack the GC scans, so it may allocate, throw and suspend through `TaskWaker`. The engine's own code stays `nothrow @nogc`; a single `@trusted` boundary (`flint.engine.web.sys.fiber`) calls the handler. An escaping `Exception` gives 500 when nothing has been sent and otherwise closes the connection. `Error` is not caught.
- **Request.** `Request.fieldCount`/`visitField` enumerate the fields (lowercase names, arrival order), `query()` gives the raw query and `protocolMinor()` the HTTP/1 version. Every view is arena memory valid for the visit only; the servlet bridge copies it into GC memory before user code sees it.
- **Response.** `FiberResponse.respond(status, fields, body, chunked)` writes a whole response, head and body in one write when they fit. `begin(status, fields, contentLength)`, `send` and `finish` stream it, where `unknownLength` means chunked on HTTP/1.1 and close-delimited on HTTP/1.0. The engine owns `Content-Length`, `Transfer-Encoding`, `Connection` and `Keep-Alive`, and writes them as Tomcat's `Http11Processor.prepareResponse` does: status line without a reason phrase, application fields in order, the framing field, `Date` unless given, then `Connection: close` or, only when the request named keep-alive, `Keep-Alive: timeout=<idle seconds>` and `Connection: keep-alive`. 204 and 304 have no framing field, 205 has `Content-Length: 0`, and HEAD keeps its framing fields without body bytes. A body shorter than its `Content-Length` closes the connection.
- **Connections.** After a finished response the connection serves the next request, pipelined or not. Fiber routes are HTTP/1.1 only for now: HTTP/2 answers 404 for a target only a fiber route serves.

### Sanitizer and fuzz evidence for the `FiberRoute` boundary

`flint.engine.web.sys.fiber.invokeFiber` is the boundary's one `@trusted` function. AGENTS.md asks for positive, negative and sanitizer/fuzz coverage:
- **Positive:** `tests/fiber_behavior.d`, `tests/fiber_fuzz.d`, and `GC.collect()` inside a running handler.
- **Negative:** a handler that throws before responding (500, then close), and a body short of its `Content-Length` (close).
- **Fuzz:** `tests/fiber_fuzz.d` is seeded and deterministic, and runs in every `dub test :engine-web`. Each case sends 1–5 pipelined requests on one connection, split into random fragments:
  - all seven methods, targets with percent escapes and queries, and random fields;
  - bodies framed by `Content-Length` or chunked, with random chunk sizes and leading zeros;
  - `HEAD`, `Connection: close`/`keep-alive`, and replies with `Content-Length` or chunked output;
  - one case in four ends in a malformed request: a bad field line, a bare LF, a NUL, an invalid chunk size, duplicate or conflicting lengths, a bad version, a missing `Host`, an unknown method, a head over 16 KiB, or a truncated body. The client then half-closes.

  Every valid response must carry the right status, framing and echo (method, target, body length and FNV-1a). Every malformed request must end in a 4xx/5xx or a close, and a clean request must succeed afterwards. `FLINT_FUZZ_SEED` and `FLINT_FUZZ_CASES` widen the run.
- **What it found:** a client that half-closed after its requests lost the running fiber response and the pipelined requests behind it. Now, as in Tomcat, EOF ends only the request side (`halfClosed` in `runtime.d`), and the regression test is in `tests/fiber_behavior.d`.

Recorded on venus, 2026-11-23, Linux x86-64 glibc:

| Command | Exit |
| --- | --- |
| `dub test :engine-web --compiler=dmd` and `--compiler=ldc2` (fuzz with the default seed, 120 cases) | 0, 0 (12/12 modules) |
| `FLINT_FUZZ_SEED=1..5 FLINT_FUZZ_CASES=600 ./packages/engine-web/flint-engine-web-test-unittest` (LDC, 3,000 cases) | 0 each |
| `python3 tools/native_build.py --profile rest --target linux-x86_64-glibc --phase build --sanitize address,undefined --cc clang --cxx clang++ --work-dir .native-sanitized --prefix .native-sanitized/install/linux-x86_64-glibc` (Clang 22.1.8 from `.tools/LLVM-22.1.8-Linux-X64`) | 0 |
| `dub test :engine-web --compiler=ldc2 --build=plain --force` and `:engine-servlet`, under `tools/ci.py run_tests`' sanitizer environment (`DFLAGS` from `policy/profiles.toml` `[sanitize]`, the LDC sanitizer runtime on `LIBRARY_PATH`, `ASAN_OPTIONS=detect_leaks=1:abort_on_error=1:detect_stack_use_after_return=1`, `UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1`), linked against the instrumented llhttp, nghttp2, OpenSSL and `libflint_ffi_framework.a` | 0, 0 (19/19 modules each; no ASan, UBSan or LSan report) |
| the sanitized binary with `FLINT_FUZZ_SEED=11..13 FLINT_FUZZ_CASES=500` | 0 each |

The full `tools/ci.py` sanitizer gate (every package, every native provider) is still the CI lane's job. The run above covers the two packages behind this boundary.

### The servlet engine (flint.engine.servlet)

`framework/engine-servlet` is Flint's servlet container, the part embedded Tomcat plays under Spring Boot. It is Flint's own engine, not a Spring type, so it lives under `flint.engine.*`. It depends on `flint:jakarta-servlet` and the engines, never on Boot.

```d
auto engine = new ServletEngine(ServletEngineOptions(port: 8080));  // address, contextPath, errorPages, globalErrorPage "/error", shutdown, cores
engine.addServlet("dispatcherServlet", dispatcherServlet);           // mapped at "/"
engine.addFilter("characterEncodingFilter", filter);                 // REQUEST dispatches, in order
engine.start();                // init servlets and filters, bind, admit; throws ServletEngineException (port in use)
engine.getPort();              // the bound port; -1 before start
engine.shutDownGracefully(30.seconds); // true = idle (GracefulShutdownResult.IDLE)
engine.stop();
```

Boot's web server support owns `WebServer` and `ServletWebServerFactory` and wraps this API, as spring-boot-tomcat wraps Tomcat (proposed to the boot session).

**What it reproduces from Tomcat 11 under Spring Boot 4.2.0:**
- **Request.** Copied out of the arena in two allocations before any servlet code runs. Parameters come from the query string (UTF-8, `+` as a space, repeated values kept in order) and from a form body. The servlet at `/` has the whole path as its servlet path and no path info. Server name and port come from `Host`.
- **Response.** An 8 KiB buffer. A response never committed goes out whole with `Content-Length`, so an empty one sends `Content-Length: 0`. `flushBuffer`, or a full buffer, commits with chunked framing unless the application set a length. `setContentType` moves a `charset` parameter to the encoding and writes it back as `;charset=X`. `setHeader` keeps the first field's position. Fields go out in insertion order, then `Content-Type` and `Content-Language`.
- **Errors.** `sendError` keeps the fields set before it, clears the body and suspends output. From the application's side the response then reports itself committed, as `ResponseFacade` does. When the servlet returns, one forward goes to the status's error page or the global page, with `DispatcherType.ERROR` and the `jakarta.servlet.error.*` attributes (`status_code`, `message`, `request_uri`, `query_string`, `method`, `servlet_name`). An uncaught exception becomes a 500 forwarded with `exception` and `exception_type`, after a `ServletException` is unwrapped to its root cause.

**Not yet covered:**
- the peer address (`getRemoteAddr`);
- sessions;
- async;
- Tomcat's HTML error report when no error page is configured (the engine sends the status with an empty body);
- HTTP/2.

## Proof

- **Upstream tests.** Each ported class ports its JUnit tests (`HttpStatusTests`, `HttpHeadersTests`, `MediaTypeTests`, `ResponseEntityTests`, `ProblemDetailTests`, `UriComponentsBuilderTests`, `RequestMappingHandlerMappingTests`, `RequestResponseBodyMethodProcessorTests`, `ExceptionHandlerExceptionResolverTests`, `DefaultHandlerExceptionResolverTests`, `ResponseEntityExceptionHandlerTests`, MockMvc's own tests). Counts of ported, passing and excluded tests, with reasons, are kept in "Upstream test counts" below.
- **gs-rest-service.** Its `GreetingController` and `GreetingControllerTests` run unchanged except for the rulebook's syntax: through MockMvc, and over real HTTP through the servlet bridge.
- **p99.** The 200, 404 and validation-error paths are measured separately under `load_bench`.
- **API coverage.** `api/mapping.json` classifies every element of the ported packages; whole subpackages outside Phase 1 are `deferred` with their phase.

## Rulebook proposals

- **D-15: single-element array attributes.** Java accepts `@GetMapping(path = "/x")` for a `String[]` attribute. D's named arguments cannot accept both a string and an array, so the positional `value` keeps the shorthand (`@GetMapping("/greeting")`) and named array attributes take array literals (`@GetMapping(path: ["/greeting"], produces: [MediaType.APPLICATION_JSON_VALUE])`). Annotation structs provide `static opCall` overloads, because a struct constructor cannot have only default parameters.

- **R15: Java enums.** An enum with only constants becomes a D `enum` with the same member names. An enum with fields, methods or interfaces becomes a struct with `static immutable` constants and Java's `name()`, `ordinal()`, `values()`, `valueOf(String)` and `toString()`. If it implements a Java interface that other types also implement (`HttpStatus implements HttpStatusCode`), the interface becomes a struct too and the enum struct converts to it through `alias this`.

## Open questions

1. **spring-test's DUB name.** Spring's artifact name gives `flint:test`, which is the base library's name, and `org.springframework.test` → `flint.test` shares a namespace with the base library `flint.test`. The modules don't collide (`flint.test.web.servlet` is new), but the DUB name does. Proposal: `flint:framework-test`.
2. **JsonPath.** MockMvc's `jsonPath(...)` needs the Jayway JsonPath engine (Apache-2.0). Coordinated with the third-party-apis session: who ports it, and over which JSON tree.
3. **Engine route kind.** Settled: `FiberRoute` in `flint.engine.web.fiber`, approved by the engine owner (m7-flint-cli). See "Real HTTP serving" below.

## Upstream test counts

| Upstream test class | Ported | Passing | Excluded or deferred (reason) |
| --- | --- | --- | --- |
| `HttpStatusTests` | 3 | 3 | none |
| `HttpMethodTests` | 5 | 5 | none (`isNotSameAs` on a value struct is checked as equality, R11) |
| `MediaTypeTests` | 24 | 24 | `withConversionService` (spring-core `DefaultConversionService`, framework-core), `serialize` (Java serialization, `jvm-platform`) |
| `HttpHeadersTests` | 45 | 45 | 29 deferred on unported types: Charset lists, `InetSocketAddress`, `ETag`, `CacheControl`, `ContentDisposition`, `Locale`, `java.time`, Java collection views |
| `ResponseEntityTests` | 22 | 22 | 3 deferred on `CacheControl` |
| `ProblemDetailTests` | 1 | 1 | the Jackson round trip waits for flint.jackson.databind |
| `UriComponentsBuilderTests` | 7 | 7 | the remaining 60 (opaque URIs, `fromHttpRequest`, forwarded headers, `cloneBuilder` variants, regex variables) are deferred to web slice 3 |
| `UriUtilsTests` | 2 | 2 | none for encode/decode; `extractFileExtension` deferred |
| gs-rest-service `GreetingControllerTests` | 2 | 2 | none (standalone MockMvc until Boot's `@AutoConfigureMockMvc`) |

Flint's own tests cover the R15/D-15 adaptations, the exceptions' messages and backtrace-free throwing, and every gs-rest-service golden case MockMvc can observe.

## Status

| Piece | State |
| --- | --- |
| `flint.http`, `flint.web`, `flint.web.bind(.annotation)`, `flint.web.server`, `flint.web.util.pattern`, converters, `flint.web.method.*`, `flint.web.accept` | in `framework/web` |
| `flint.jakarta.servlet(.http)` | in `framework/jakarta-servlet` (EPL-2.0) |
| `DispatcherServlet`, `RequestMappingHandlerMapping`/`Adapter`, processors, exception resolvers, `WebMvcConfigurer`, `WebMvcConfigurationSupport` | in `framework/webmvc` |
| MockMvc (`flint.test.web.servlet.*`, `flint.mock.web`) | in `framework/framework-test` |
| `api/framework/mapping.json` | 1,391 elements classified for the ported types: spring-web 14.1%, spring-webmvc 22.7%, jakarta-servlet 33.5%; a member is classified only when the D type declares it |
| `flint.web.util` | `UriComponentsBuilder`, `UriComponents`, `UriUtils` (R14: UTF-8 bytes, identical encoded output) |
| CORS | `flint.web.cors` (`CorsConfiguration`, `DefaultCorsProcessor`, `UrlBasedCorsConfigurationSource`), `@CrossOrigin` class and method combination, `CorsRegistry`, preflight handling; petclinic's three CORS goldens reproduce through MockMvc. `CorsConfiguration` is a full port of Spring 7.1's: origin patterns (`OriginPattern`, `:[*]` and port lists), comma-delimited origins, permit-default lists that later adds and combines replace, nullable credentials, private-network and max-age settings, and `validateAllowPrivateNetwork`. `DefaultCorsProcessor` answers private-network preflights. All 20 ported `CorsConfigurationTests` run |
| `FiberRoute` | in `packages/engine-web` (`flint.engine.web.fiber`): full-D handlers on the request fiber, Tomcat framing, keep-alive; 3 socket tests and 3 unit tests on DMD and LDC |
| Servlet engine | `framework/engine-servlet` (`flint.engine.servlet`): `ServletEngine` with Tomcat's framing, field order, error-page forward and exception handling; 7 socket tests on DMD and LDC. Registered |
| gs-rest-service over real HTTP | `framework/engine-servlet/proof/gs-rest-service`: the guide's controller through Spring MVC's default `DispatcherServlet` on the servlet engine. `spring_bench.py accept gs-rest-service --start …/gs-rest-service-proof --url http://127.0.0.1:18081`: **12/18 byte-identical**: all eight 200 cases, `Accept: application/json`, HEAD, OPTIONS and the final counter. The six others (406, 405 ×2, the JSON 404 ×2 and the Whitelabel page) go through `/error`, which Boot's `BasicErrorController` serves (boot session, `boot/module/flint-boot-webmvc`) |
| `p1-interim` retired | the web stack builds on `flint:java`, `flint:core`, `flint:context`, `flint:engine-aot` and `flint:jackson-databind`. MimeType moved to `flint.util` (`ca39294`); request-value conversion throws `flint.core.convert.ConversionFailedException` with Java type names; the JSON converter writes through the real `JsonMapper`, with `ProblemDetailJacksonMixin`'s layout in the converter until databind has `@JsonAnyGetter`. gs-rest-service still passes 12/18 over real HTTP and every MockMvc test |
| Registered | `jakarta-servlet` (EPL-2.0), `webmvc`, `web` (roots `flint.web` and `flint.http`), `framework-test` (`flint.test.web`, `flint.test.util`, `flint.mock`) and `engine-servlet` are in `policy/framework.json` and the root `dub.sdl`, with bench probes and budgets (linked bytes and template instances from `measure_builds --framework-sizes` with 25% headroom; timings provisional). Test them with `dub test :web` etc. from the root. The layer checks (`tools/gates.py` and `flint check`) give a module to the longest root that prefixes it, so `webmvc`'s `flint.web.servlet` sits inside `web`'s `flint.web` |
| Locale | `ServletRequest.getLocale`/`getLocales` (Tomcat's `Accept-Language` parsing in the servlet engine; Spring's in MockMvc) and `ServletResponse.setLocale`/`getLocale` (`Content-Language`); `LocaleResolver`, `flint.web.servlet.i18n` (`AbstractLocaleResolver`, `AcceptHeaderLocaleResolver`, Spring MVC's default), and `DispatcherServlet.render` applying the resolved locale. 8 `AcceptHeaderLocaleResolverTests` |
| AOT contract 2 | `requestMappingsOf`/`exceptionHandlersOf` fill `beanType`, `typeAnnotations`, the advice selectors (`assignableTypes`, `annotations`, `basePackageClasses`) and `@ExceptionHandler(produces)`. `initCorsConfiguration` reads class-level `@CrossOrigin` from `typeAnnotations`, which replaces the distance+100 workaround. `HandlerMethod`s take their bean type from the row. `ControllerAdviceBean` applies Spring's `HandlerTypePredicate` (base-package prefix, assignable type, class annotation). `HttpEntity!T` arguments read their `elementType`. `produces` is recorded and not yet used to choose a handler |
| `@RequestBody` | `JacksonJsonHttpMessageConverter.readInternal` reads through the real `JsonMapper` (`readValue(bytes, typeName)`). An `InvalidDefinitionException` is a 500 `HttpMessageConversionException`; any other `JacksonException` is a 400 `HttpMessageNotReadableException` ("JSON parse error: …") |
| gs-rest-service | **18/18 exact** through Boot's port (`benchmarks/spring/flint/gs-rest-service`, `spring_bench.py accept gs-rest-service --impl flint`, main `3d49760`) |
| Error responses | `MissingRequestValueException` bodies carry their final status; `HttpHeaders.get`/`setAcceptPatch`; `MethodArgumentNotValidException` (a `BindException` over `flint.validation.BindingResult`), `MissingMatrixVariableException`, `UnsatisfiedServletRequestParameterException`, `MissingServletRequestPartException` (`flint.web.multipart.support`) and `AsyncRequestTimeoutException` (`flint.web.context.request.async`) |
| Next | `@Valid` on `@RequestBody` (Validator to `MethodArgumentNotValidException`) for petclinic-rest; the `MessageSource` cases of `ErrorResponseExceptionTests`; `ResponseEntityExceptionHandler`; choosing exception handlers by `produces`; converter charsets; PathPattern and UriComponents gaps; the 404 and validation-error p99 runs: queued by proof-harness (`1119738`, `policy/spring-error-paths-benchmark.json`; queue entries `error-404-p99`, blocked on Boot's `BasicErrorController` and the gs-rest-service port, and `error-validation-p99`, blocked on the petclinic port). The spring gate requires each path's p99 to be at most 0.99 of Go's |

The packages are not yet in `policy/framework.json` or the root `dub.sdl`: their DUB names (`web`, `webmvc`) and module roots (`flint.web`, `flint.http`) are held by the engines until the rename, and `framework_layers` gives each module one root while spring-web needs two (`flint.http`, `flint.web`). Until then they build with path dependencies and `dub test` from each package directory.
