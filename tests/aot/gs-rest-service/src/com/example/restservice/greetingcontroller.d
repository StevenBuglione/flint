/// gs-rest-service's controller.
module com.example.restservice.greetingcontroller;

import com.example.restservice.greeting : Greeting;
import flint.web.bind.annotation : GetMapping, RequestParam, RestController;

@safe:

/// `@RestController public class GreetingController`.
@RestController class GreetingController
{
    private enum string template_ = "Hello, %s!";
    private long counter;

    /// `@GetMapping("/greeting")`.
    @GetMapping("/greeting") Greeting greeting(@RequestParam(value: "name", defaultValue: "World") string name)
    {
        import std.format : format;

        return Greeting(++counter, format(template_, name));
    }
}
