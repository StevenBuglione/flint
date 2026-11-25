# The per-endpoint fast path

Owner: the fast-path spike (started by the coordinator, 2026-11-23). Status: **Flint's default execution model** (owner decision `7206d97d`), with the generic Spring path as the fallback. Every build emits it for qualifying endpoints; `FLINT_AOT_FAST_PATH=0` opts out, for diagnosis. It was prototyped on gs-rest-service's `/greeting` and recommended go, staged (section 9). **Certified A/B (section 8.5): on ÷ off throughput 1.394, p99 0.507, CPU 0.659; on ÷ Go throughput 1.293, p99 0.729, CPU 0.843, p50 1.016, RSS 1.45.** Read with ADR-030, `docs/spring/api-mapping.md`, `gc.md`, `coordination.md` and `performance-playbook.md` (rule R-13 is the reason for this note).

## 1. The idea

The certified gap against Go is the Spring layer, not the engine. gs-rest-multicore-3 at `1141a9bc` measured throughput 0.80, p50 1.83, p99 2.27, RSS 1.66 and CPU per request 1.46 of Go, while Flint's own HTTP engine (`bench-rest`) serves 1.68× Go's throughput. The Spring layer is a faithful port of Java's request pipeline: the servlet request and response object graph, `HandlerMapping` and `PathContainer` matching, content negotiation, argument resolvers, return-value handlers and message converters. Site-by-site cuts took `/greeting` from about 50 GC allocations to 20 (`f11b7e01`, the allocation gate's count). Every remaining allocation is an object some Spring extension point receives, and the playbook's R-13 forbids changing those signatures.

The fast path stops building the objects for requests that provably never reach an extension point. Flint AOT already knows every endpoint at build time: its mapping, `produces` and `consumes`, argument kinds and types, and return type with its Jackson descriptor. For an endpoint of a simple shape it generates a function that binds the handler's arguments straight from the engine's parsed request and calls the handler. At startup the dispatcher proves, against the strategies it actually runs, that generic dispatch of that endpoint would do the same thing. At run time the container offers each request to the dispatcher before it builds any servlet object. The dispatcher either answers from its precomputed tables or declines, and a declined request takes today's path untouched.

Nothing public changes. The servlet and Spring objects are built only when something asks for them (section 5), which is ADR-030's AOT model taken one step further.

## 2. What is decided when

| Decided | By | What |
|---|---|---|
| **Build time** | Flint AOT (`apps/flint/src/flint_tool/engine/aot/fast.d`), when the build asks for it | Whether any endpoint has a shape the runtime can prove (section 3.1): if so, the two pay-for-use beans (section 9). **No endpoint gets code of its own** (table-driven, playbook B-3, since the S1 slice): the runtime binds each argument from the row's `ArgumentSpec` into stack `Any` storage and calls the row's existing array invoker (contract 4, `handleArray_<id>`). Earlier builds generated a `fast_<id>` function per endpoint; petclinic-rest's size headroom (385 KB to the Oz gate, coordinator 15:53Z) rules that out for its 37 mappings. |
| **Startup** | `FastPathTable.build` (`flint.web.servlet.mvc.method.fast`), called by `WebMvcConfigurationSupport.build` | The mapping proof against the configured strategies (section 3.2), and the content-negotiation table: for each `Accept` key, the `Content-Type` that generic negotiation selects, computed by the generic code itself. The table is fixed after startup. The container enables the offer only when no filter is mapped. |
| **Run time** | The container (`flint.engine.servlet.fast`) and the table | Method and literal path match; the one `Accept` value looked up in the table; parameters decoded with the servlet request's own decoder into stack storage; the handler called; the value written by the converter's own `ObjectMapper` into a recycled buffer; one `FiberResponse.respond`. Anything unexpected declines before the handler runs (section 3.3). |

**The switch.** It is a Flint AOT generation option (`AotRequest.fastPath`). It is on by default since the owner's decision `7206d97d`, and `FLINT_AOT_FAST_PATH=0` opts out for diagnosis. During the prototype it was opt-in through `FLINT_AOT_FAST_PATH=1`. An application without a qualifying endpoint links none of it (pay-for-use, section 9 stage 1): the table and the container offer are reached only through two beans that Flint AOT generates for qualifying endpoints, and a null `HandlerMapping.fast` means today's path. The container asks the servlet once, when it starts (`FastDispatch.hasFastPath`). If there is no fast path it never offers a request, so such a build pays nothing per request. An AOT option avoids a `-version` flag that would have to reach the cached platform archives. The option is part of the AOT output key, so a build with it never restores output generated without it. The opt-out should become a `flint.toml` or profile setting, owned by m7-flint-cli, so that the receipt records it (flint-aot's note).

## 3. The fallback rule: when an endpoint, or a request, takes the generic path

The rule has three layers. Each is conservative, and each failure means "generic path", never an error.

### 3.1 The endpoint's shape (build time, `fastShape`)

Flint AOT emits `fast_<id>` only when all of these hold:
- exactly one path starting with `/`: literal segments with no `{`, `}`, `*`, `?`, `%`, `;` or `\`, and (S1) whole-segment `{name}` variables without a regular expression;
- `@RequestMapping(method = GET)` exactly, with no `params`, `headers` or `consumes`, and `produces` at most exactly `application/json` (S1);
- `@ResponseBody` (directly or through `@RestController`), with no `@ResponseStatus` and no reason;
- `@CrossOrigin` on the class or the method only as S3 proves it (section 4, `Vary`);
- a return type that Flint AOT describes, so the Jackson converter writes it by its descriptor, and that is a plain value: not `void`, `Object`, `Any`, `HttpEntity`, `HttpHeaders` or `ProblemDetail`. Or (S2) a `ResponseEntity` whose return value handler is exactly `HttpEntityMethodProcessor`, on a mapping with `produces = application/json`, which fixes the producible type whatever the body;
- every parameter is `@RequestParam string` or (S1) a `@PathVariable` `int`, `long` or `string` named by a template variable, neither `@Valid` nor an exception parameter. Constraint annotations such as `@Min` are fine: they run in the bean's `@Validated` proxy, which both paths call.

The prototype stops here on purpose. Path variables, `ResponseEntity`, `@RequestHeader`, `@CrossOrigin` and `@RequestBody` are the next shapes (section 9).

### 3.2 The mapping proof (startup, `FastPathTable.build`)

A row's fast route is registered only when the strategies make generic dispatch equal to it:
- **Nothing per request around the mappings.** The table needs no interceptors (`InterceptorRegistry` empty), no CORS configuration source, and no custom argument resolvers or return-value handlers. Content negotiation must use the header-only manager. Otherwise there is no table at all.
- **Filters only with a stated effect (S4).** The container offers requests while filters are mapped only when every mapped filter is mapped at `/*` for `REQUEST` and implements `FastFilter`, stating at startup what it does to a fast-path request (`FastFilterEffect`):
  - the response fields it writes on a fresh response;
  - per-request state around the servlet (`enter`/`exit`);
  - whether it answers an exception escaping the servlet itself (`handles`/`handle`).

  The effects are computed once and cached (`ServletEngine.fastFiltersStated`). Spring Security's `FilterChainProxy` states one only for a single `DefaultSecurityFilterChain` on `AnyRequestMatcher` whose filters are each exactly:
  - `SecurityContextHolderFilter` over the request-attribute repository (nothing to load for a fresh request);
  - `HeaderWriterFilter`, whose built-in writers state their fields with the names, values and presence rules their own `writeHeaders` uses;
  - `AnonymousAuthenticationFilter` (`enter` installs its token);
  - `ExceptionTranslationFilter` (`handles` security exceptions with its own `translate`);
  - `AuthorizationFilter` whose rules grant every request statically.

  The context is cleared on `exit`, as `doFilter` clears it. Boot's `DelegatingFilterProxy` forwards its delegate's effect. Per request, the container runs `enter` and `exit` around the dispatcher (on every path), puts the fields on `FastExchange.filterFields` (written before the route's `Vary`, as `HeaderWriterFilter` writes eagerly in the port), adds them first to a materialized response, and hands an escaping exception to the innermost filter that `handles` it. Any other filter (authentication, CSRF, a user filter) means no fast path for the application. Earlier the rule was simply no filters, because a filter receives the servlet objects of every request it maps. gs-rest-service registers none. Spring Boot's own `CharacterEncodingFilter`, `FormContentFilter` and `RequestContextFilter` are not ported yet. When they are, the proof has to show they leave a `GET` without a body unchanged, or name them as known no-ops for such a request; otherwise the fast path stays off (web-http's warning).
- **The lookup chooses this handler.** `RequestMappingHandlerMapping` is the first handler mapping. Its direct-path registrations for the literal path, the ones `lookupHandlerMethod` reads before it scans any pattern, hold exactly this handler and nothing else. The handler carries no `@CrossOrigin` on its type or method, and its effective `@ResponseStatus`, type level included, is none.
- **The same return handling.** No return-value handler of the adapter that `invokeAndHandle` consults before `@ResponseBody` (`HttpEntityMethodProcessor`, `HttpHeadersReturnValueHandler`) supports the return type. The handler has no response-status reason and is not void, and the declared type is not `Object`, `Any` or `ProblemDetail` (or a subtype, by the descriptor). A null value of a class return type is answered as `writeWithMessageConverters` answers it: 200, no `Content-Type`, an empty body (web-http's review).
- **The same arguments.** For every parameter, the adapter's resolver composite (`getArgumentResolver`, the very lookup the generic path uses) answers exactly `RequestParamMethodArgumentResolver` for a `string`, or exactly `PathVariableMethodArgumentResolver` for an `int`, `long` or `string` whose name is a template variable.
- **The lookup chooses this handler for every path the template accepts (S1).** A template route is registered only when exactly one registration has the pattern and this row's array invoker, and no other registration that a `GET` or `HEAD` reaches (its method condition admits either, or is empty) could match a path the route accepts. The check is segment by segment: a pattern segment with syntax overlaps anything; a literal overlaps a template literal only when equal, and a numeric variable only when it is canonical digits; `**` and `{*name}` overlap everything. Methods other than GET and HEAD on the same pattern (`DELETE /owners/{ownerId}`) don't overlap, because lookup filters by method. A literal that a canonical id also matches (`/items/7` beside `/items/{id}`) refuses the template route.
- **`produces = application/json` (S1).** `handleMatch` sets the producible types from the condition, so the table's negotiation uses `[application/json]` as the producible list; the condition itself matches every `Accept` key the table answers (none, `*/*`, `application/json`).
- **The same response.** For each `Accept` key, the table runs the generic negotiation: `HeaderContentNegotiationStrategy`'s parse and sort, then `producibleTypes` and `selectMediaType`. These two are pure functions extracted from `writeWithMessageConverters`, which the generic path now calls too. The first converter that can write the value with the selected type must be exactly `JacksonJsonHttpMessageConverter`. The selected type must be concrete, not octet-stream, and without parameters, so the `Content-Type` value is its own `toString()`, as `ServletServerHttpResponse.writeHeaders` passes it to the servlet response. A key that fails any of this, such as a 406, another converter or a charset, gets no table entry, and its requests are declined.

### 3.3 The request (run time, before the handler runs)

A request is declined, with nothing run and nothing sent, when:
- its method is not `GET` or `HEAD`;
- its raw path, after the context path, is not byte-equal to a route's literal path. So percent-encoded, dot-segment, double-slash, trailing-slash and matrix-parameter paths go generic, and the container's normalisation and Spring's lookup-path rules never need copying;
- it has more than one `Accept` field, or an `Accept` value other than the table's keys (none, `*/*`, `application/json`), or a key without an entry;
- its path, query and first `Accept` value do not fit the 2 KiB stack copy, or a parameter name or value exceeds 1 KiB;
- a required parameter is missing. The generic path then raises `MissingServletRequestParameterException` and resolves it, exactly as before;
- (S1) a path variable it cannot bind exactly. An `int` or `long` takes canonical decimal digits only, with no sign, no leading zero and at most 9 (`int`) or 18 (`long`) digits. So `abc` (the generic 500 `MethodArgumentTypeMismatchException`), `-1` (a `@Min` violation), `007`, `+5` and `0x1A` (which Spring's `NumberUtils.parseNumber` accepts) all go generic. A `string` declines on `%` (the generic path decodes it) and `;` (matrix variables, which it strips). An empty segment, a trailing slash or an extra segment doesn't match the template.

After the handler has run, the fast path never declines. Running the handler twice would be visible, since gs-rest-service's counter would skip.

## 4. Keeping Spring's behaviour byte-identical

The fast path writes only what the generic path writes for the requests it accepts. Everything else is declined, so it is answered by the unchanged generic code.

- **Status.** 200 for a plain value; `@ResponseStatus` stays outside the shape.
- **`ResponseEntity` (S2).** As `HttpEntityMethodProcessor.handleReturnValue`:
  - the entity's status;
  - without a body, no `Content-Type` and `Content-Length: 0`;
  - with a body, the negotiated `Content-Type` and the Jackson converter's bytes, sent chunked, because the processor flushes.

  The body's writer is checked per request, as `writeWithMessageConverters` picks it: the first converter that `canWrite` the body's type as the selected type must be exactly the Jackson converter. Anything the fast path doesn't write exactly goes to that very processor on the materialized request and response (`DispatcherServlet.completeFastReturn`), because the handler has already run. That covers entity headers, a zero status, and a body another converter (or none) would write.
- **`Content-Type`.** The table's value, computed at startup by the generic negotiation code. A type with a charset, or one written by another converter, is declined. Spring 7's Jackson converter writes `application/json` without a charset, which gs-rest-service's golden confirms.
- **`Vary` (S3).** Spring adds `Vary` only through CORS processing, which applies only to handlers with a CORS configuration (their `@CrossOrigin`). For such a handler `getHandler` adds the CORS interceptor, whose `DefaultCorsProcessor` adds `Vary: Origin`, `Access-Control-Request-Method` and `Access-Control-Request-Headers` and lets a request through that isn't a CORS request. The proof requires no global configuration source, a configuration that validates (`validateAllowCredentials`), and exactly `DefaultCorsProcessor` (the default when none is set). The fast path then writes those three fields first, by the processor's own `HttpHeaders` constants, and declines any request with an `Origin` field. Every path that materializes after the handler ran (an exception, an entity the fast path doesn't write) first runs the chain's `preHandle` (`DispatcherServlet.prepareFastCompletion`), so error responses carry the same `Vary` fields as the generic ones.
- **`Content-Length` and chunked.** The servlet response buffers 8,192 bytes. A body written without a flush is sent with `Content-Length` when it fits, and chunked when it overflows. The fast path's `respond` makes the same choice from the body length. Chunk boundaries can differ, which no client sees. `Date`, `Keep-Alive`, `Connection` and the status line come from the same `FiberResponse`.
- **`HEAD`.** It reaches the handler, as in Spring: the counter advances. The engine keeps the framing fields and drops the body, so `Content-Length` is the `GET` length, as the golden's 35 shows.
- **`OPTIONS`, `POST`, `DELETE` and other methods.** Declined: the generic path sends `Allow`, 405 with its error body, and so on.
- **404.** Unknown paths and `/greeting/` are declined by the byte comparison, so the JSON 404 and the Whitelabel page are the generic ones.
- **`Accept` edge cases.** `application/xml`, quality values, wildcards other than `*/*`, several `Accept` fields, and an unparsable `Accept` are all declined, so 406 and its `Accept` header come from the generic resolver.
- **Parameters.** Values are bound as `RequestParamMethodArgumentResolver` binds them, with `name[]` as the fallback, an absent or single empty value replaced by the default, and several values joined with `,` by the conversion service. Decoding goes through `decodeComponentInto`, the request's only decoder: `decodeComponent` now calls it too. So `+`, percent-encoded UTF-8 and malformed escapes, which Tomcat skips, behave identically by construction. A single empty value without a default binds the literal `""`, not null, as the generic slice of the frozen query does.
- **A client gone mid-body.** Once the response is on the wire (`respond` began), an I/O failure leaves the exchange as the generic path's `complete()` lets its `IOException` leave. No error page is attempted on a started transport.
- **Exceptions and error bodies, including `ProblemDetail`.** An exception from the handler, or from the write, goes through `exchange.materialize()`. The container then builds the same `ServletEngineRequest` (its `capture`) and `ServletEngineResponse`. `DispatcherServlet.completeFastDispatch` re-runs the handler mappings, which are pure and set the request attributes the generic lookup sets, and calls `processDispatchResult` with the exception. The exception reaches the resolvers, `@ControllerAdvice` and the error page with the objects the generic path would have had. A write failure first replays what the generic converter would already have streamed into the response, `Content-Type` and the partial body, and wraps the exception as `JacksonJsonHttpMessageConverter.writeInternal` does. An exception that escapes the dispatcher is finished by the container's own valves, as an uncaught exception of the generic path is.

**Proof.** proof-harness's black-box suite passes 18/18 exact with the fast path on and off (section 8).

## 5. Lazy materialisation

The servlet and Spring objects (`HttpServletRequest`, `HttpServletResponse`, `ServletWebRequest`, `HttpHeaders`, `ServerHttpRequest`, `ModelAndViewContainer`, `HandlerExecutionChain`, `ServletInvocableHandlerMethod`) are built when one of these happens:
- **The handler takes one as a parameter.** That is outside the shape, so the endpoint stays generic. Later shapes may pass a materialised object, since a `HttpServletRequest` parameter only needs `capture` to run before the call.
- **A filter, interceptor or advice would run.** That is excluded by the proof (section 3.2), so the whole application, or the endpoint, stays generic. A future refinement: interceptors and filters whose URL patterns provably exclude a route's literal path are evaluated once at startup, since the path is a constant.
- **An exception reaches `@ControllerAdvice` or the error controller.** `materialize()` then runs (section 4).

**MockMvc** drives `DispatcherServlet.service` directly, never the container, so it never sees the fast path. Tests written against MockMvc keep testing the generic path, which is also the fallback, so it stays covered. The fast path is covered by the black-box suite over real HTTP, by the allocation gate test (which runs the real server in process), and by unit tests of the decoder and parameter rules.

**Fiber-local state.** Flint's `FrameworkServlet` sets no `RequestContextHolder` or `LocaleContextHolder` per request today, so there is nothing to materialise there. When `RequestContextFilter` or `processRequest`'s holders are ported, the fast path must install a lazy `RequestAttributes` that materialises on first use, or decline. That decision goes in this note's checklist (section 10).

## 6. The arena rule (ADR-030 §4)

- **Engine memory stays off the GC heap.** The exchange is built on the fiber's stack: the path, query and `Accept` value are copied out of the arena into a 2 KiB stack buffer, because arena bytes are only readable inside the arena's visitor. Parameters decode into stack buffers. The table, its routes and its content types are startup objects.
- **The body** goes into a buffer recycled through a 16-slot compare-and-swap pool, as `JsonFactory` recycles its generators (playbook R-6). Framework packages keep no thread-local state. The buffer is engine memory that user code never sees, and a buffer that grew past 64 KiB is dropped.
- **Only user-visible values are GC memory.** A bound parameter string is copied to the GC heap in one allocation, because the handler may keep it. A default value is the generated literal and costs nothing. The handler's return value is boxed in an `Any` (one allocation for a struct today; none once framework-core's inline small structs land, playbook R-3).
- **Nothing borrowed escapes.** `FastExchange` and `FastArguments` are structs of borrowed slices and delegates passed `ref scope`, so DIP1000 rejects code that stores them. `@safe` throughout, with no `@trusted`.

## 7. The `scope` complement (DIP1000 stack allocation)

The task also asked whether `scope` on request-internal objects, which makes DMD and LDC put `new` classes on the stack, is a cheaper complement. Results are in section 8.3. The constraint is R-13: a `scope` object can be passed only to `scope` parameters. Nearly every per-request object of the generic path is handed to a Spring extension point: `Filter.doFilter`'s chain, `HandlerMethodArgumentResolver.resolveArgument`'s `ModelAndViewContainer` and `NativeWebRequest`, `HandlerExceptionResolver`'s request and response, and `HandlerInterceptor`'s handler. Those signatures cannot take `scope` without breaking implementers.

## 8. Evidence

All numbers are local and indicative unless they say otherwise. Certified numbers come only from proof-harness's queue.

Three builds of gs-rest-service at the same commit, with the LDC release profile:
- **main**: main itself, at `c0aafbbf`;
- **off**: this branch with the fast path off;
- **on**: this branch with `FLINT_AOT_FAST_PATH=1`.

### 8.1 Black-box suite and tests

- `spring_bench.py accept gs-rest-service --wire exact` passes **18/18** against main, off and on.
- **Package tests.** engine-aot (14 modules), engine-servlet (5) and webmvc pass on DMD and LDC, and so does framework-test (40). framework-test includes the new `fast_path_tests.d`, which runs `FastPathTable` against the strategies `WebMvcConfigurationSupport` really builds. It checks:
  - the bound values: single value, joined repeats, the default for an empty value, the `name[]` fallback;
  - that every declined request leaves the handler unrun;
  - that a missing generated invoker, an interceptor or `@CrossOrigin` turns the table off.
- **Decoder.** engine-servlet's tests check that `decodeComponentInto` and `decodeComponent` agree on a corpus of malformed, empty and encoded input, and that `visitParameter` returns `getParameterValues`' values.
- **Generated code.** With the option off, Flint AOT's generator emits nothing new: gs-relational-data-access's generated tree is byte-identical to main's. gs-rest-service and petclinic-rest differ in one line of Boot's generated bean definition. The `dispatcherServlet` bean's `types` list gains `flint.engine.aot.fast.FastDispatch`, because the class now implements that interface. With the option on, gs-rest-service's module gains the `FastArguments` import, `fast_com_example_restservice_GreetingController_greeting` (8 lines) and `mapping.fast = &…;`.
- **A bug the startup proof caught in development.** `typeid` of an interface reference names the interface, not the object's class. The exact-class checks must use `typeid(cast(Object) x)`. Before that fix, the proof silently declined every route. The framework-test suite now fails if it does.

### 8.2 Allocations per request (the allocation gate's method)

This is the allocation gate's test (`request_allocations_test.d`, `FLINT_REQUEST_ALLOCATIONS=record`). It runs the real servlet path in process, after warm-up, on druntime's collector behind flint.arena's counter. The counts are deterministic, and DMD and LDC give the same numbers for the fast path.

| request | main | off | on |
|---|---|---|---|
| `GET /greeting` | 17 / 4,672 B | 17 / 4,672 B | **2 / 64 B** |
| `?name=User` | 17 / 4,720 B | 17 / 4,720 B | **3 / 80 B** |
| `?name=%C3%A9t%C3%A9` | 19 / 4,752 B | 19 / 4,752 B | **3 / 80 B** |
| `?name=a&name=b` | 22 / 4,864 B | 22 / 4,864 B | **3 / 80 B** |
| JSON escaping | 20 / 4,832 B | 20 / 4,832 B | **4 / 144 B** |
| `Accept: application/json` | 17 / 4,704 B | 17 / 4,704 B | **2 / 64 B** |
| `HEAD /greeting` | 19 / 4,832 B | 19 / 4,832 B | **2 / 64 B** |
| `Accept: application/xml` (406) | 109 / 14,992 B | 109 / 14,992 B | 109 / 14,992 B |
| OPTIONS, POST, DELETE, 404s | unchanged | unchanged | unchanged |

**Re-verified on the current base, `eaa27d1d`.** This base has framework-core's inline `Any` for small structs (`46d21e28`) and web-http's `351683be`. `GET /greeting`: main **16 / 4,624 B**, off 16 / 4,624 B, on **1 / 16 B**. Error paths are again equal across all three: 406 104, JSON 404 74. 18/18 three ways. With the `Any` box gone, the only allocation left is the user's `String.format` result. The table above is from the previous base, `c0aafbbf`.

With the fast path on, what remains on `/greeting` is user code only:
- the `String.format` result, from `formatJava`;
- the `Any` box of the returned `Greeting`. Framework-core's inline `Any` for small structs removes it (playbook R-3).
- With `?name=`, the bound string, which the handler receives and may keep.

That is ADR-030 §4's target for `/greeting` exactly. Declined requests cost exactly what they cost on main. With the option off, the container never offers a request, so off equals main on every row.

**Two things the counter caught during the prototype.**
- **Closures.** The first version cost 4 allocations and 4 KB. Assigning a nested function's address to a field of a non-`scope` local struct makes DMD and LDC heap-allocate the whole frame, 2 KiB stack copy included. Declaring the struct `scope` makes it a stack frame again (`-vgc` confirms).
- **Wasted offers.** Before `hasFastPath`, a build without the option paid an offer, and a closure, on every request.

### 8.3 `scope` candidates

These are main's 17 allocations on `GET /greeting`, from the counter's call sites (`topAllocationSites`), and whether a `scope` (stack) allocation could take each one without changing a Spring signature:

| site | per request | what it is | `scope`? |
|---|---|---|---|
| `ServletEngine.capture` | 2 | the frozen head and the `ServletEngineRequest` | no: user code reads both |
| `ServletEngine.serve` | 2 | `ServletEngineResponse`, the filter `Chain` | no: passed to `Filter.doFilter` and `Servlet.service` |
| `RequestMappingHandlerAdapter.handle` | 2 | `ServletWebRequest`, `ModelAndViewContainer` | no: passed to every argument resolver and return-value handler |
| `getHandlerExecutionChain` | 1 | `HandlerExecutionChain` | no: `HandlerMapping.getHandler`'s public result |
| `parsedLookupPath` | 1 | the parsed `PathContainer` | no: stored as a request attribute |
| `HttpHeaders.create`, `createOutputMessage`, `getOutputStream` | 3 | the response message, its headers, the output stream | no: passed to `HttpMessageConverter.write` |
| `RequestParamMethodArgumentResolver.resolveName` | 1 | the values array | no: can reach the handler |
| `MEDIA_TYPE_ALL_LIST` | 1 | `[*/*]` when there is no `Accept` | no: a public strategy result. A shared immutable list fits better (R-2) |
| `determineCompatibleMediaTypes` | 1 | the compatible-types scratch array | **yes**: internal to `writeWithMessageConverters` |
| `formatJava`, `Any.of(Greeting)` | 2 | user code and the return box | no: user-visible |

`scope` can take **1 of the 17**. Every other object is handed to a Spring extension point or to user code, and rule R-13 keeps those signatures as Spring's. It's still worth doing, since it's one local stack array in `writeWithMessageConverters`, but it's not a strategy. The fast path avoids building these objects in the first place.

### 8.4 CPU and load (local, indicative)

**Instructions per request** (callgrind over real HTTP, one reactor thread, 2,000 warm-up and 5,000 measured `GET /greeting?name=Flint` with `Accept: */*`, LDC release). This is deterministic, so it isolates CPU from venus's background load:

| | main | on | on ÷ main |
|---|---|---|---|
| whole process | 71.1k | 43.2k | **0.61** |
| servlet and Spring layer (`ServletEngine.serve`, inclusive) | 46.1k | 20.7k | **0.45** |
| `gc_malloc` | 5.7k | 0.8k | 0.14 |
| full collections (`Gcx.fullcollect`) | 1.3k | ~0 | — |
| `ObjectMapper.writeValue` | 8.5k | 6.8k | 0.80 |
| `FiberResponse.respond` (engine write) | 6.6k | 6.7k | 1.0 |

What remains of the fast path's 20.7k:
- Jackson: 6.8k. About 4k of it is `writeBean`, `writeField`, `writeProperty` and `writeScalar` dispatching per property through `Any`; the generator's own escaping and writing is the rest. This is the part a generated straight-line writer would remove. third-party-apis prefers per-type property writers cached on `BeanDescription`, which keep escaping, inclusion and features in one place. Reported to them.
- The engine's response write: 6.7k.
- The handler: 4.8k, half of it `String.format`.
- Parameter binding: 2.0k, two passes over the query.

**Load** (`abbench.py` in the spike's scratchpad, built like `load_bench` with oha 1.16.0, the version `load_bench` pins):
- server pinned to CPUs 20–21, oha to 22–25, 64 connections;
- per trial: a 5 s warm-up, a 15 s capacity run (throughput, CPU per request), then 15 s at a fixed 20k req/s (p50, p99), and VmHWM;
- main, off, on and proof-harness's Go comparator interleaved, rotating the order every trial;
- two runs, 5 and 7 trials. Trials stretched by a measurement window's pause were dropped. Other sessions' builds were running on venus throughout, so variance is high: off against main, whose request code is identical, moves by ±7%.

| median, ratio to main | run 1 (5 trials) | run 2 (7 trials) |
|---|---|---|
| throughput | on 1.39, off 1.02 | on **1.47**, off 0.95 |
| CPU per request | on 0.73, off 0.99 | on **0.73**, off 1.07 |
| p99 in the capacity run | on 0.56 | on **0.54** |
| p50 at 20k req/s | on 0.64 | on 0.67 |
| p99 at 20k req/s | on 0.53 | on 0.87 |
| peak RSS | on 1.00 | on 0.99 |

The Go comparator measured only about 170–175k req/s here, against 247k in the certified runs, so the local Flint÷Go ratios are not trustworthy. **Projection** (an estimate, not evidence): gs-rest-multicore-4's certified ratios at `27e8d10b`, times the local on÷main factors above:

| metric | certified Flint ÷ Go (multicore-4) | × local on ÷ main | projected Flint ÷ Go with the fast path |
|---|---|---|---|
| throughput | 0.885 | 1.39–1.47 | **1.23–1.30** |
| CPU per request | 1.17 | 0.73 | **~0.86** |
| p50 | 1.48 | 0.64–0.67 | **~0.95–0.99** |
| p99 | 1.93 | 0.53–0.87 | 1.0–1.7, uncertain |
| peak RSS | 1.62 | 1.0 | **1.62, unchanged** |

**RSS does not move.** Idle, both builds hold 11.1–11.2 MB. Under load, both reach about 21.5 MB, although the fast path allocates 64 bytes per request. Peak RSS is therefore not per-request garbage. It is what the server and the collector reserve under load: GC pools, the 36 threads including druntime's mark threads, fiber stacks touched by 64 connections, and the connection slots. These are `gc.md` §1.3's items, and the fast path does not touch them.

**Size, pay-for-use (playbook S-1, the coordinator's merge condition).** Stripped gs-rest-service, with the two generated beans (section 9, stage 1):

| build | at `eaa27d1d` | against main | at `e77bc654` (merged) | against main |
|---|---|---|---|---|
| main | 4,746,624 | — | 4,697,792 | — |
| off: no qualifying endpoint, or opted out | 4,739,176 | −7,448 | 4,698,536 | **+744** |
| on: gs-rest-service's `/greeting` specialised | 4,769,288 | +22,664 | 4,720,456 | +22,664 |

- **On**, gs-rest-service carries the table, the offer and one `fast_<id>`: a constant +22,664 B (+0.48%).
- **Off**, the table, `serveFast` and the binding code are not linked. What remains is about 1.1 KB of interface residue:
  - the `FastDispatch` and `FastPathFactory` type info and their dynamic-cast helpers;
  - `DispatcherServlet`'s interface table;
  - the fast module's `ModuleInfo`.

  Against main's inlining that nets **+744 B on the merged base**. On the earlier base the same residue was hidden by a 7 KB shrink elsewhere. Removing the residue too would mean moving both casts behind the generated beans.
- **Apps without a qualifying endpoint.** Setting the option on gs-relational-data-access or petclinic-rest changes their generated output by 0 lines.

Earlier, before pay-for-use, stripped at `c0aafbbf`: main 4,746,584 B; off 4,764,576 B (+17,992 B, +0.38%, the always-linked table and hook); on 4,760,480 B; Go's comparator 6,634,456 B. At `eaa27d1d`: main 4,750,720 B; off 4,768,712 B (+17,992 B); on 4,764,616 B.

### 8.5 Certified A/B (proof-harness, `fast-path-ab`)

proof-harness measured gs-rest-service at `139e4fc4`, in a claimed window with no foreign build in 144 samples (`benchmarks/spring/evidence/fast-path-ab/`, decisions.md `6b7125e2`):
- workload: `policy/spring-http-benchmark.json`, 4 trials per arm;
- arms: off and `FLINT_AOT_FAST_PATH=1`, with Go interleaved;
- both arms 18/18 exact, and the on arm checked for its generated `fast_` function.

| ratio of medians (99% interval) | throughput | p99 | p50 | CPU per request | peak RSS |
|---|---|---|---|---|---|
| on ÷ off | **1.394** (1.379–1.401) | **0.507** (0.366–0.672) | 0.639 | **0.659** (0.603–0.868) | 0.999 (0.986–1.014) |
| on ÷ Go | **1.293** (1.285–1.299) | **0.729** (0.548–0.934) | 1.016 | **0.843** (0.783–1.061) | 1.450 |

Medians: on 319k req/s and p99 0.198 ms; off 229k and 0.390 ms; Go 247k and 0.272 ms.

**With the fast path, gs-rest-service beats Go on throughput, p99 and CPU per request, and p50 is at parity.** The local projection (section 8.4) was right on throughput, CPU and p50. p99 came out better than projected. **RSS still misses** (1.45× Go), as section 8.4 predicted, and needs gc.md §1.3's work. The commits after `139e4fc4` change startup proof and linkage, not the per-request path: pay-for-use, the return-value-handler check, the null-value branch, and the started-transport guard.

## 9. Recommendation

**Go, staged, for endpoints of the proven shapes. gs-rest-service gets there; petclinic-rest does not.**

**Why go.**
- On `/greeting` the fast path reaches ADR-030 §4's target exactly: only user code allocates. On the current base that is 1 allocation of 16 B, the `String.format` result, against main's 16 and 4.6 KB.
- It cuts the servlet and Spring layer's instructions by 55% and the whole request's by 39%.
- Locally it moves throughput about 1.4× and CPU per request about 0.73× against main.
- Projected on the certified baseline, that is the first configuration that beats Go on throughput and CPU per request, with p50 at parity.
- It keeps 18/18 exact.
- It changes no public API, and costs nothing per request when off.
- It is the mechanism R-13 calls for. `scope`, the cheaper complement, can take 1 of the 17 allocations (§8.3), and the site-by-site cuts are now down to objects Spring's extension points require.

**What it does not do.**
- **RSS** stays 1.62× Go. That needs gc.md §1.3's work: GC pool sizing and release, mark threads under an affinity mask, and fiber-pool sizing. The collector track (D1b page release, D3) remains necessary.
- **p99** is uncertain locally. With about 16 MB/s of garbage at 250k req/s instead of about 1 GB/s, collections should become rare. Only a certified run can say whether p99 then beats Go.

**Stages.**
1. **Land the mechanism, opt-in (R-14).** That means the framework hook, the table and the generator option, default off, after the owners' review (section 11). The coordinator's condition comes first: the always-linked 18 KB becomes pay-for-use (playbook S-1), with **zero added bytes when no endpoint qualifies**. From `nm`, the 18 KB is webmvc's `FastPathTable` (prove, serve, binding, buffer pool: about 11 KB) and engine-servlet's `serveFast` with its parameter visitor and decoder (about 6 KB).
   **Done on the branch** (size table in §8.4: an off build is 7,448 B smaller than main). The design follows the generated `JavaUtilDateModule` customizer (`20493652`). When the option generates at least one `fast` row, Flint AOT also adds two beans to the application's own generated module:
   - **`flintAotFastPathConfigurer`**, a `FastPathConfigurer`: a `WebMvcConfigurer` that implements a small `FastPathFactory` interface in `flint.web.servlet`. `WebMvcConfigurationSupport.build` asks any configurer that implements it for the table. Nothing else references `FastPathTable`.
   - **`flintAotFastPathOffer`**, a `WebServerFactoryCustomizer`. It hands `FlintServletWebServerFactory` the address of `flint.engine.servlet.fast.serveFast` (a new `setFastOffer`, which reaches `ServletEngineOptions`). `ServletEngine.serve` calls the offer through that pointer only when it is set, so nothing else references `serveFast`.
   Without the beans, `--gc-sections` drops both, and the only residue is the null check and the `FastDispatch` interface on `DispatcherServlet`, which the size table must show. Owners: boot (the factory setter), flint-aot (the planner's two beans, probed like the date customizer), web-http (the hooks).
2. **Certify.** Done: `fast-path-ab` (section 8.5) meets the decision rule. on beats off on throughput, CPU and p99 beyond the intervals, with no metric worse and 18/18 in both arms.
3. **Default on.** Done: the owner decided it on the certified result (`7206d97d`). `FLINT_AOT_FAST_PATH=0` opts out.
4. **Grow the shapes, one at a time, each with black-box cases and gate entries.** In order:
   - `@PathVariable` of `int`, `long` and `string` (the pattern matched by the generic `PathPattern` at startup into a literal prefix plus one segment);
   - `ResponseEntity` (status and headers written by the generic `HttpEntityMethodProcessor` rules);
   - `@CrossOrigin` without an `Origin` header (DefaultCorsProcessor's fixed `Vary` fields, computed at startup);
   - `@RequestBody` through Jackson's recycled parser;
   - filters and interceptors whose patterns provably exclude a route, proved at startup.

**petclinic-rest: worth it now (section 9.1).** When the spike measured it, the benchmarked request (`GET /petclinic/api/owners/1`, "owner with pets and visits") cost 1,655 GC allocations, almost all in the data path, so the fast path would have saved about 4%. data-access's cuts have since brought it to **360 allocations and 34 KB** (`policy/request-allocations.json` at `0017b3f3`, the `beanDescriptorOf` memo). The layers a fast path skips (dispatch, the security chain and CORS: a CORS preflight costs 69) are now about 19% of the request. **Estimate after shapes S1–S4: capacity +8–15%, CPU per request −10–15%, p99 better, RSS unchanged.** This scales gs-rest-service's certified 1.39× by the share of the request that is framework rather than database.

### 9.1 Extending to petclinic-rest: plan, and which endpoints must fall back

From the generated mapping rows: petclinic-rest has 37 mappings, all `ResponseEntity`, all under `@CrossOrigin`, and served at the `/petclinic` context path. The golden shows that every response also passes Spring Security's filter chain with security disabled: six security headers, the three CORS `Vary` fields, and chunked framing for a 200 JSON body (`HttpEntityMethodProcessor` flushes).

**Today all 37 fall back.** A filter is mapped (the security chain), so the container never offers a request (section 3.2).

| endpoints | count | shape needed | after the shapes |
|---|---|---|---|
| `GET` by id: `/api/owners/{ownerId}` (the measured one), `/api/owners/{ownerId}/pets/{petId}`, `/api/pets/{petId}`, `/api/pettypes/{id}`, `/api/specialties/{id}`, `/api/vets/{id}`, `/api/visits/{id}` | 7 | S1 `@PathVariable int`; S2 `ResponseEntity` (dynamic status, 404 with an empty body, 200 chunked); S3 `@CrossOrigin` without `Origin` (fixed `Vary`); S4 the security chain's permitted-request effect, proved static at startup (headers, anonymous `SecurityContext` materialised lazily) | fast |
| `GET` lists: `/api/pets`, `/api/pettypes`, `/api/specialties`, `/api/vets`, `/api/visits` | 5 | S2–S4 | fast |
| `GET` with query parameters: `/api/owners?lastName`, `/api/v2/owners?lastName&page&size`, `/api/v2/pets?page&size` | 3 | S2–S4, plus `@RequestParam int` | fast |
| `DELETE` by id | 6 | S1–S4 and `DELETE` | fast; a 404 or a 409 is the handler's own `ResponseEntity` |
| `POST`/`PUT` with `@RequestBody` (with `@Valid`) | 15 | S1–S4 and S5: the body through Jackson's recycled parser, validation before the handler | fast for a valid body; **a validation failure declines** (it happens before the handler, so the generic path repeats it and answers 400 with Spring's error body) |
| `/` (`RootController`, `HttpServletRequest` and `HttpServletResponse` parameters) | 1 | — | **always generic**: it needs the servlet objects |
| CORS preflights, `OPTIONS`, 404, 405, 406, malformed ids (`/owners/abc`), malformed JSON | — | — | **always generic**: declined by the request rules |

**A rule the later shapes need: materialise with the return value.** `ResponseEntity` can carry headers or bodies the fast writer doesn't produce. The handler has already run by then, so the fast path can't decline. It must materialise the servlet objects and hand the return value to the generic `HandlerMethodReturnValueHandler`, the same escape `completeFastDispatch` gives exceptions today.

**Estimate.** The fast path removes the dispatch, security-chain and CORS objects. The allocation gate measures that layer at about 69 allocations: a CORS preflight, which runs the chain and no handler.
- **When measured (`f11b7e01`):** that was against 1,655 for `GET /owners/1`, about 4%. One zero-row JDBC lookup cost about 1,170.
- **At `0017b3f3`:** data-access's cuts brought the request to 360 and the zero-row lookup (`unknown owner`, 148, chain included) to about 80. The skippable layer is now **about 19%**.

**Plan (owner decision `7206d97d`: extend the shapes so petclinic-rest uses the fast path).**
- **S1–S3**, path variables, `ResponseEntity` (including materialising with the return value) and `@CrossOrigin` `Vary`, with web-http and framework-core.
- **S4**, the security chain's static headers for permitted requests, with boot and framework-core (the Spring Security port).
- **S5**, `@RequestBody` with validation, last.

Each shape lands with its own black-box cases on the default, gate entries, and a petclinic A/B (on against `FLINT_AOT_FAST_PATH=0`).

### 9.1.1 S5: the validated POST

A `POST` mapping that consumes exactly `application/json`, takes one `@RequestBody` (validated with `@Valid` or not)
besides S1's path variables, and writes as S1 or S2. The design and the review notes are in the coordination note
`s5-validated-post.md`.

**Proof (`FastPathTable.build`):**
- The route's method selects the registration: `directHandler` finds the only registration at the path that a `POST`
  reaches, and its `consumes` is exactly `application/json`. Templates use S1's overlap check, restricted to
  registrations a `POST` reaches. (The same rule now lets GET routes share a path with other methods' mappings, as
  the lookup's method condition does.)
- The body parameter resolves with exactly `RequestResponseBodyMethodProcessor`; it is required and not `Optional`.
- The first converter that reads the declared type as `application/json` is exactly the Jackson converter.
- Returns, `Accept` keys, CORS and filters are proved as S1–S4.

**Per request:**
- **Decline** unless the container offers the whole body with exactly one `Content-Type` field whose value is
  `application/json`.
- **Read:** the body is copied (as `readAllBytes` copies it) and read with the converter's own mapper; any read
  failure declines.
- **Validate:** the processor's own `validationFailure` (made `package(flint)`).
- **Failure:** the same `MethodArgumentNotValidException` goes to `complete`, then the generic
  `processDispatchResult`, so advice and resolvers run exactly as they do generically.
- **Success:** the handler runs and writes as S1 or S2.

**Engine:** the container must offer `POST` with `FastExchange.requestBody`, `contentTypeCount` and `contentType`
set, and `materialize` must replay the body. Until engine-servlet does (web-http), POST routes are proved but never
offered.

**Tests:** framework-test `fast_path_tests.d`, against MockMvc's generic dispatch with the same validator and advice:
- a valid body for each `Accept` key: the same status, `Content-Type` and body, one handler run;
- an invalid body: the advice's 400, byte for byte, and no handler run;
- declines: another `Content-Type` value, two fields, none, an empty body, malformed JSON, a GET.

### 9.1.2 S6: the unmatched GET

A `GET` that no route takes is materialized and enters the generic dispatch at `doDispatch`
(`DispatcherServlet.dispatchUnmatched`). `doGet`, `processRequest` and `doService` only lead there.

**The skip:** when no registration of the first handler mapping has a pattern that matches the path, that mapping's
lookup would find nothing and leave only its lookup-path attribute. The test is the lookup's own
`PathPattern.matches` on the request's own `parsedLookupPath`. The dispatch then sets that attribute and asks the
remaining mappings, as `getHandler` would.

**Otherwise:** it is `doDispatch` itself.

The resource handler, interceptors, resolvers, `sendError` and the engine's status forward all stay generic. Only an
exact `DispatcherServlet` with an exact `RequestMappingHandlerMapping` first is served this way; a subclass of either
could look up differently. A route that matches the path but declines its request still declines, and the container
takes the generic path.

**Tests:** framework-test `unmatchedLikeGeneric` compares the materialized response with the same request through
the servlet's own `service`: status, error message, Content-Type, body, and the whole set of request attributes left
(by name and value type; web-http's review). The cases are:
- trailing-slash, deep, dot, `..` and `;` paths;
- template mismatches and a shadowed template;
- the S5 POST path's GET (405);
- `Accept: text/html`.

gs-rest's `spring_error_identity.py` with the fast path on and off: 31 responses byte for byte, 0 problems.

### 9.1.3 Full S6: the unmatched GET written from the exchange

When the rest of an unmatched `GET`'s dispatch and its error page are both proved stock, the 404 is written from the
`FastExchange` with no servlet request or response, resource handler, exception resolver or error forward (the
coordinator's 15:10Z item, Astra's GC-tail rank 3). It is the same response: lean S6, the dispatch and the error page
(9.2) are the reference.

**Hand-off.** engine-aot's `FastExchange.unmatched` and `FastErrorPage` (`flint.engine.aot.fast`). The engine
(`serveFast`) sets `unmatched` only when its installed error-page shortcut is also a `FastErrorPage` and the status
404 has a page. The dispatcher calls it for a request its first mapping cannot match. The page writes, or returns
`false` having written nothing, and the dispatcher continues with lean S6.

**The dispatcher's per-request proof** (webmvc `FastPathTable.dispatch`), for an exact `DispatcherServlet` and
`RequestMappingHandlerMapping`, on top of lean S6's conditions:
- the method is `GET`;
- the path is its own lookup path (`plainPath`): it starts with `/`, and has no `%`, `;`, `\`, empty segment, or `.`
  or `..` segment, so nothing is decoded, stripped or normalized;
- it starts with no registration pattern's literal prefix (the text before its first `{`, `*`, `?` or `%`),
  compared ignoring ASCII case. The literal part of a pattern matches only itself, so no pattern can match the
  path, and the lookup and `handleNoMatch` find nothing.

A path that fails any of these takes lean S6.

**The page's startup proof** (Boot's `StockErrorPageShortcut.prove`, through webmvc's
`ErrorShortcutRoute.provesUnmatched`), in addition to 9.2's:
- the handler mappings are exactly the request mappings and the stock resource mapping: `SimpleUrlHandlerMapping` of
  `/**` only, to an exact `ResourceHttpRequestHandler`, with no interceptors and no CORS configuration;
- the adapters are the request mapping adapter, then an exact `HttpRequestHandlerAdapter`;
- the exception resolvers are exactly four:
  - Boot's `DefaultErrorAttributes` bean, which only records the exception;
  - `ExceptionHandlerExceptionResolver` with no `@ControllerAdvice`, so it leaves a resource handler's exceptions alone;
  - `ResponseStatusExceptionResolver`, with no descriptor putting `@ResponseStatus` on `NoResourceFoundException` or a
    base class;
  - `DefaultHandlerExceptionResolver`, which copies the exception's headers (it has none) and calls
    `sendError(404, detail)`;
- none of the three Spring resolvers adds `Cache-Control`.

The dispatch then ends in `sendError(404)` with nothing else on the response. The detail is unread, since `include-message` is
`NEVER`, and so are the attributes the dispatch leaves, since the ERROR chain runs no filter and only the stock
attributes read the request.

**Per request, the page** (`writeUnmatched`) admits the `Accept` keys of 9.2, then writes:
- the body: the controller's own body, from the stock `DefaultErrorAttributes` over a `WebRequest` holding only the
  status and `getRequestURI()`, with the controller's options. The exception and message, which the dispatch records,
  are never included, so the map is the same: timestamp, status, error, path;
- the fields: the mapped filters' fields (S4), then the negotiated `Content-Type`, flushed (chunked), as the forward
  leaves the response.

**Not eligible.** petclinic: it has a global CORS configuration and `@ControllerAdvice` for `Exception`. Any
application with interceptors, custom resolvers, a context-path-only request, or another error page.

**Tests:**
- framework-test: which paths reach the page and which take lean S6. That covers the encoded, `;`, `..`, `//`, `.`
  and backslash paths, prefix collisions in any case, a declining page, HEAD and POST.
- boot-webmvc: `writeUnmatched` against the dispatch and ERROR forward for every `Accept` key and escaped, non-ASCII
  and trailing-slash paths, field by field; and the declines.
- gs-rest: `spring_error_identity.py` with the fast path on and off, and acceptance 18/18.

### 9.2 The error-page shortcut (default JSON 404)

A 404 that reaches Boot's error page costs a second full pass: the engine forwards to `/error`, which runs the ERROR filter chain, the `DispatcherServlet` lookup, `BasicErrorController.error`, `HttpEntityMethodProcessor`'s negotiation and the Jackson converter (coordination note web-http-404-specialization.md). The shortcut writes that response in place of the forward when startup has proved the whole ERROR dispatch stock. The first dispatch, which raises and resolves the 404, is unchanged.

**Where.** The engine asks a startup-installed `ErrorPageShortcut` (engine-servlet, `ServletEngineOptions.errorPageShortcut`) at each forward, after the `jakarta.servlet.error.*` attributes are set and the buffer reset. Boot's `StockErrorPageShortcut` (boot-webmvc, `autoconfigure/error.d`) answers. The only way in is `flintAotErrorPageShortcut`, a `WebServerFactoryCustomizer` Flint AOT generates under the fast path's switch (`FLINT_AOT_FAST_PATH=0` turns both off) when the closure has Boot's error handling, Jackson and Flint's server. It passes Boot's `stockJsonMapper` as a function, since boot-webmvc does not depend on boot-jackson.

**The startup proof (`install`)**, all or nothing:
- Boot: `stockJsonError` (exactly `BasicErrorController` and `DefaultErrorAttributes`, `ErrorPageCustomizer`, includes that do not depend on the request), and the Jackson converter's mapper is exactly `stockJsonMapper`'s.
- Engine: `filtersFor(ERROR, errorPath)` is empty, and `defaultServletInstance()` is the `DispatcherServlet`.
- Dispatcher (`ErrorShortcutRoute.prove`, webmvc `mvc/method/fast.d`):
  - The first handler mapping has no interceptors. Every registration at the error path has only the path and at most one `produces` type. For each `Accept` key (none, `*/*`, `application/json`), the registrations whose `produces` matches compare with `BasicErrorController.error` strictly first. `RequestMappingInfo.producesMatch` and `compareProducesFor` are the request-free halves of the lookup's own code.
  - No CORS processing applies.
  - The only parameter is the `HttpServletRequest`, resolved by exactly `ServletRequestMethodArgumentResolver`.
  - The `ResponseEntity` goes to exactly `HttpEntityMethodProcessor`. Its header-only negotiation (`acceptEntry`, the same code the fast path's table uses) selects a parameterless type, and the Jackson converter is the first to write the error map for it.
  - Flint has no `ResponseBodyAdvice`, `@ModelAttribute` or `@InitBinder` advice.

**Per request (`writeErrorPage`).** The shortcut writes only when all of these hold:
- the status is 404 and the page is the proved error path;
- the method is `GET`, `POST`, `PUT`, `DELETE` or `PATCH` (HEAD, OPTIONS and TRACE stay generic);
- the request has at most one `Accept` field, whose value is one of the keys and was proved for it;
- the response has no `Content-Type` of its own.

The body is `BasicErrorController.error(request)` itself, from the same attributes, written by the converter's own mapper into a pooled buffer. Then, as the processor does: `setStatus`, `setContentType`, the body, `flushBuffer` (so the engine frames it chunked). An entity with headers, a body of another type, or a mapper failure writes nothing and the engine forwards. Headers a handler set before its 404 stay on the response, as they do through the forward.

**Evidence.** boot-webmvc `error_page_shortcut_test.d` runs each case twice through the auto-configured `DispatcherServlet` with the engine's forward sequence, once through the shortcut and once through the ERROR dispatch. The two responses must be identical: status, every header, the body byte for byte apart from the timestamp's value, and the commit. The cases are:
- five methods by three `Accept` keys;
- escaping, encoded, non-ASCII and control-character paths, and a query string;
- a handler that sets a header and then sends 404;
- the declines: `text/html`, a q-value, another type, two `Accept` fields, HEAD, and a handler's own `Content-Type`;
- proof failures: a mapper that is not Boot's, request-dependent attributes.

web-http's engine-level byte-identity suite covers the wire.

## 10. Checklist for a new fast-path shape or a new Spring hook

- Every Spring feature that runs per request (filter, interceptor, advice, `ResponseBodyAdvice`, `@InitBinder`, `@ModelAttribute`, `@SessionAttributes`, a `WebDataBinder` customisation, a `ConversionService` converter for a bound type) declares how the proof sees it: either the proof excludes the endpoint, or a startup evaluation shows it is a no-op for the route.
- A new shape adds black-box cases that exercise its edges on both paths, and an allocation-gate entry.
- A new `Accept` key, header or status comes from the generic code at startup, never from a hand-written copy.

## 11. Before this lands: owners and files

| owner | files on this branch |
|---|---|
| framework-core (engine-aot) | `engine-aot/.../fast.d` (new), `mapping.d` (`HandlerMapping.fast` after `invokeArguments`); `aot-contract.md` §4.12 to be written on landing, with the exact signature and "null means today's path" |
| web-http | engine-servlet: `fast.d` (new); `package.d` (`serve` offer, `finishExchange` split, three package helpers); `request.d` (`decodeComponentInto`, the one decoder). webmvc: `servlet/package.d` (`FastPath` slot, `DispatcherServlet : FastDispatch`, `hasFastPath`, `completeFastDispatch`); `mvc/method/fast.d` (new); `mvc/method/package.d` (`visitDirectPath`); `annotation.d` (`selectMediaType` and `producibleTypes` extracted, called by the generic path too); `config/annotation.d` (one block in `build`). web: `method/package.d` (`getFastInvoker`), `method/support.d` (`getArgumentResolver` private → `package(flint)`). framework-test: `fast_path_tests.d` (new) |
| flint-aot | `apps/flint/src/flint_tool/engine/aot/fast.d` (new), `emit.d` (one line beside `handlerInvoker`, one in `mappingRegistration`, the import), `driver.d` (`AotRequest.fastPath`, the option in the output key), `step.d` (`FLINT_AOT_FAST_PATH`) |
| third-party-apis | none: the body goes through `ObjectMapper.writeValue(OutputSink, Any)` |
