/++
The per-endpoint fast path's startup proof and request rules (docs/spring/phase1/fast-path.md), against the
strategies `WebMvcConfigurationSupport` really builds. Each test offers a `FastExchange` to the `DispatcherServlet`
as the container does, and checks what the fast path answers and when it declines.
+/
module fast_path_tests;

import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : DescriptorTable;
import flint.engine.aot.fast : FastArguments, FastExchange, FastOutcome, FastValueVisitor;
import flint.engine.aot.mapping : AotHandlerMapping = HandlerMapping;
import flint.http.converter.json : JacksonJsonHttpMessageConverter;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.test.web.servlet.setup : StaticBeanFactory;
import flint.web.bind.annotation : CrossOrigin, GetMapping, RequestParam, RestController;
import flint.web.servlet : DispatcherServlet, HandlerInterceptor;
import flint.web.servlet.config.annotation : InterceptorRegistry, WebMvcConfigurationSupport, WebMvcConfigurer;
import flint.web.servlet.mvc.method.aot : handlerDescriptorsOf, requestMappingsOf;

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

// What Flint AOT emits for these handlers (apps/flint/src/flint_tool/engine/aot/fast.d).
private bool fastHello(Object bean, ref scope FastArguments arguments, ref Any result)
{
    string a0;
    if (!arguments.requestParamString("name", "World", false, a0))
        return false;
    result = Any.of((cast(HelloController) bean).hello(a0));
    return true;
}

private bool fastCors(Object bean, ref scope FastArguments arguments, ref Any result)
{
    string a0;
    if (!arguments.requestParamString("name", "World", false, a0))
        return false;
    result = Any.of((cast(CorsController) bean).cors(a0));
    return true;
}

private final class CountingInterceptor : HandlerInterceptor
{
}

/// A dispatcher over `controller`'s rows, the fast invoker set on every row when `fast` is given.
private DispatcherServlet dispatcher(C)(C controller, string beanName, typeof(&fastHello) fast,
        WebMvcConfigurer[] configurers = null)
{
    auto beans = new StaticBeanFactory;
    beans.addBean(beanName, controller);
    auto rows = requestMappingsOf!C(beanName);
    foreach (ref row; rows)
        row.fast = fast;
    auto table = DescriptorTable.withBuiltins();
    auto descriptors = handlerDescriptorsOf!C();
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
}

/// Offers a request as the container does: `query` undecoded pairs (the container's decoding is engine-servlet's).
private Offer offer(DispatcherServlet servlet, string method, string path, string query = null,
        string[] accept = null)
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

    void materialize(out Object request, out Object response)
    {
        assert(false, "no exception was expected");
    }

    scope FastExchange exchange;
    exchange.method = method;
    exchange.path = path;
    exchange.acceptCount = accept.length;
    if (accept.length)
        exchange.accept = accept[0];
    exchange.parameter = &parameter;
    exchange.respond = &respond;
    exchange.materialize = &materialize;
    result.outcome = servlet.dispatchFast(exchange);
    return result;
}

@("fast path: a proved endpoint answers with the generic path's status, Content-Type and body")
unittest
{
    auto controller = new HelloController;
    auto servlet = dispatcher(controller, "helloController", &fastHello);
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
}

@("fast path: requests outside the proof are declined before the handler runs")
unittest
{
    auto controller = new HelloController;
    auto servlet = dispatcher(controller, "helloController", &fastHello);
    assert(offer(servlet, "POST", "/hello").outcome == FastOutcome.declined);
    assert(offer(servlet, "OPTIONS", "/hello").outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/hello/").outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/hell%6F").outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/nope").outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/hello", null, ["application/xml"]).outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/hello", null, ["text/html"]).outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/hello", null, ["application/json;q=0.9"]).outcome == FastOutcome.declined);
    assert(offer(servlet, "GET", "/hello", null, ["*/*", "*/*"]).outcome == FastOutcome.declined);
    assert(controller.calls == 0, "a declined request must not have run the handler");
}

@("fast path: no table without a generated invoker, with an interceptor, or for a @CrossOrigin handler")
unittest
{
    auto controller = new HelloController;
    assert(offer(dispatcher(controller, "helloController", null), "GET", "/hello").outcome
            == FastOutcome.declined);
    auto interceptors = cast(WebMvcConfigurer) new class WebMvcConfigurer
    {
        override void addInterceptors(InterceptorRegistry registry)
        {
            registry.addInterceptor(new CountingInterceptor);
        }
    };
    assert(offer(dispatcher(controller, "helloController", &fastHello, [interceptors]), "GET", "/hello").outcome
            == FastOutcome.declined);
    assert(offer(dispatcher(new CorsController, "corsController", &fastCors), "GET", "/cors").outcome
            == FastOutcome.declined);
    assert(controller.calls == 0);
}
