/++
spring-guides/gs-rest-service `complete/` (commit e15fec6, the reference pinned in benchmarks/spring/apps.json):
`RestServiceApplication.java`, `Greeting.java` and `GreetingController.java`, ported to Flint Boot.
Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: Java → D syntax only (one module per Java package, R1; record → struct, R11;
annotations, R2; `main` through `mixin FlintMain`, D-1), and one annotation written as a constant for the linters.
`String.format` is flint:java's, over Java's `Formatter` syntax.
+/
module com.example.restservice;

import flint.boot : FlintMain;
import flint.boot.autoconfigure : FlintBootApplication;
import flint.java.lang : String;
import flint.java.util.concurrent.atomic : AtomicLong;
import flint.web.bind.annotation : GetMapping, RequestParam, RestController;

@safe:

/// `@SpringBootApplication public class RestServiceApplication`; its `main`, which runs
/// `SpringApplication.run(RestServiceApplication.class, args)`, is the mixin's.
@FlintBootApplication
final class RestServiceApplication
{
}

mixin FlintMain!RestServiceApplication;

/// `public record Greeting(long id, String content) { }`
struct Greeting
{
    long id; ///
    string content; ///
}

/// The guide's controller.
@RestController
class GreetingController
{
    private enum string template_ = "Hello, %s!";
    private AtomicLong counter;

    ///
    this()
    {
        counter = new AtomicLong();
    }

    ///
    @GetMapping("/greeting")
    Greeting greeting(@RequestParam(value : "name", defaultValue:
            "World") string name)
    {
        return Greeting(counter.incrementAndGet(), String.format(template_, name));
    }
}
