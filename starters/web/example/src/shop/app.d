/// shop: the application root, as a Spring Boot application.
module shop.app;

import flint.arena : Result;
import flint.boot : FlintApplication, FlintMain;
import flint.config : ConfigurationProperties, Required;
import flint.di : Service;
import flint.web : Get, PathVariable, RestController;
import shop.greeting : greet;

@safe:

/// The application: its package, src/shop/, is scanned for beans at compile time.
@FlintApplication final class ShopApplication
{
    /// Start the application.
    static int main(string[] args)
    {
        return FlintApplication.run!ShopApplication(args);
    }
}

mixin FlintMain!ShopApplication;

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
