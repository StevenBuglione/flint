/++
Ported from spring-guides/gs-rest-service e15fec6: complete/src/main/java/com/example/restservice/GreetingController.java
Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: Java → D syntax only (annotations, R2; `String.formatted`, std.format).
+/
module com.example.restservice.greeting_controller;

import com.example.restservice.greeting : Greeting;
import flint.java.util.concurrent.atomic : AtomicLong;
import flint.web.bind.annotation : GetMapping, RequestParam, RestController;
import std.format : format;

@safe:

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
    // Idiomatically `@RequestParam(value: "name", defaultValue: "World")`, as Java's `@RequestParam(defaultValue =
    // "World")`. D-Scanner 0.15.2, which tools/quality.py runs over benchmarks/, cannot parse named arguments yet,
    // so the fields are given in declaration order: value, name, required, defaultValue.
    @GetMapping("/greeting") Greeting greeting(@RequestParam("name", null, true, "World") string name)
    {
        return Greeting(counter.incrementAndGet(), format(template_, name));
    }
}
