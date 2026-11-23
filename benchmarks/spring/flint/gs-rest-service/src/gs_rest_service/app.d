/++
spring-guides/gs-rest-service `complete/` (commit e15fec6, the reference pinned in benchmarks/spring/apps.json):
`RestServiceApplication.java`, `Greeting.java` and `GreetingController.java`, ported to Flint Boot.
Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: Java → D syntax (the package `com.example.restservice` is the project's module, R1
with FLINT-E0403's module root; record → struct, R11; annotations, R2; `main` through `mixin FlintMain`, D-1), and
one annotation written as a constant for the linters.
+/
module gs_rest_service.app;

import flint.boot : FlintMain;
import flint.boot.autoconfigure : FlintBootApplication;
import flint.java.util.concurrent.atomic : AtomicLong;
import flint.web.bind.annotation : GetMapping, RequestParam, RestController;
import std.format : format;

@safe:

/// `@SpringBootApplication public class RestServiceApplication`; its `main`, which runs
/// `SpringApplication.run(RestServiceApplication.class, args)`, is the mixin's.
@FlintBootApplication final class RestServiceApplication
{
}

mixin FlintMain!RestServiceApplication;

/// `public record Greeting(long id, String content) { }`
struct Greeting
{
    long id; ///
    string content; ///
}

/// `@RequestParam(value = "name", defaultValue = "World")`. A constant until the pinned dfmt and D-Scanner parse D's
/// named arguments (docs/spring/phase1/boot.md, "Tooling gap: named arguments").
private enum RequestParam nameParameter = () {
    RequestParam parameter;
    parameter.value = "name";
    parameter.defaultValue = "World";
    return parameter;
}();

/// The guide's controller.
@RestController class GreetingController
{
    private enum string template_ = "Hello, %s!";
    private AtomicLong counter;

    ///
    this()
    {
        counter = new AtomicLong();
    }

    ///
    @GetMapping("/greeting") Greeting greeting(@nameParameter string name)
    {
        return Greeting(counter.incrementAndGet(), format(template_, name));
    }
}
