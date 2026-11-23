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
3. **Engine route kind.** The fiber route kind that may allocate and throw (above), coordinated with the owner of `flint.engine.web`.

## Upstream test counts

| Upstream test class | Ported | Passing | Excluded or deferred (reason) |
| --- | --- | --- | --- |
| `HttpStatusTests` | 3 | 3 | none |
| `HttpMethodTests` | 5 | 5 | none (`isNotSameAs` on a value struct is checked as equality, R11) |
| `MediaTypeTests` | 24 | 24 | `withConversionService` (spring-core `DefaultConversionService`, framework-core), `serialize` (Java serialization, `jvm-platform`) |
| `HttpHeadersTests` | 45 | 45 | 29 deferred on unported types: Charset lists, `InetSocketAddress`, `ETag`, `CacheControl`, `ContentDisposition`, `Locale`, `java.time`, Java collection views |
| `ResponseEntityTests` | 22 | 22 | 3 deferred on `CacheControl` |
| `ProblemDetailTests` | 1 | 1 | the Jackson round trip waits for flint.jackson.databind |
| gs-rest-service `GreetingControllerTests` | 2 | 2 | none (standalone MockMvc until Boot's `@AutoConfigureMockMvc`) |

Flint's own tests cover the R15/D-15 adaptations, the exceptions' messages and backtrace-free throwing, and every gs-rest-service golden case MockMvc can observe.

## Status

| Piece | State |
| --- | --- |
| `flint.http`, `flint.web`, `flint.web.bind(.annotation)`, `flint.web.server`, `flint.web.util.pattern`, converters, `flint.web.method.*`, `flint.web.accept` | in `packages/framework-web` |
| `flint.jakarta.servlet(.http)` | in `packages/jakarta-servlet` (EPL-2.0) |
| `DispatcherServlet`, `RequestMappingHandlerMapping`/`Adapter`, processors, exception resolvers, `WebMvcConfigurer`, `WebMvcConfigurationSupport` | in `packages/framework-webmvc` |
| MockMvc (`flint.test.web.servlet.*`, `flint.mock.web`) | in `packages/framework-test` |
| `api/framework/mapping.json` | 1,391 elements classified for the ported types: spring-web 14.1%, spring-webmvc 22.7%, jakarta-servlet 33.5%; a member is classified only when the D type declares it |
| Next | the servlet bridge over `flint.engine.web` (after the rename), CORS (`flint.web.cors`), `UriComponentsBuilder`, `ResponseEntityExceptionHandler`, `@RequestBody` with Jackson reading |

The packages are not yet in `policy/framework.json` or the root `dub.sdl`: their DUB names (`web`, `webmvc`) and module roots (`flint.web`, `flint.http`) are held by the engines until the rename, and `framework_layers` gives each module one root while spring-web needs two (`flint.http`, `flint.web`). Until then they build with path dependencies and `dub test` from each package directory.
