/// shop: the application root.
module shop.app;

import flint.starter_web : ConfigurationProperties, Get, PathVariable, Provided, Required,
    RestController, Result, Service, runApplication;
import shop.greeting : greet;

@safe:

/// Typed configuration bound from config/application*.toml.
@ConfigurationProperties("app")
struct AppSettings
{
    /// Greeting prefix.
    @Required string greeting;
}

/// A greeting.
struct Message
{
    /// The text.
    string text;
}

/// Greets people.
@Service final class Greeter
{
    private AppSettings settings;

    /// Receive the bound settings.
    this(AppSettings settings)
    {
        this.settings = settings;
    }

    /// Greet `name`.
    Message greeting(string name)
    {
        return Message(greet(settings.greeting, name));
    }
}

/// GET /api/greetings/{name}.
@RestController("/api/greetings")
struct GreetingController
{
    private Greeter greeter;

    /// Receive the service.
    this(Greeter greeter)
    {
        this.greeter = greeter;
    }

    /// Greet someone.
    @Get("/:name")
    Result!Message get(@PathVariable("name") string name)
    {
        return Result!Message(greeter.greeting(name));
    }
}

int main(string[] args)
{
    return runApplication!(Provided!AppSettings, Greeter, GreetingController)(args);
}
