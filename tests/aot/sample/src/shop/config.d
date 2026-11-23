/// A configuration class with conditional bean methods.
module shop.config;

import flint.boot.autoconfigure.condition : ConditionalOnClass, ConditionalOnMissingBean, ConditionalOnProperty;
import flint.context.annotation : Bean, Configuration, Profile;
import shop.owners : OwnerService;

@safe:

/// Greets owners.
interface Greeter
{
    /// A greeting for `name`.
    string greet(string name);
}

/// The greeter outside production.
final class FriendlyGreeter : Greeter
{
    /// Informal.
    string greet(string name)
    {
        return "Hello, " ~ name ~ "!";
    }
}

/// The production greeter.
final class FormalGreeter : Greeter
{
    /// Formal.
    string greet(string name)
    {
        return "Good day, " ~ name ~ ".";
    }
}

/// Exists only when `shop.audit.enabled=true`.
final class AuditLog
{
    /// The greeter it was built with.
    Greeter greeter;

    /// Constructed by a bean method.
    this(Greeter greeter)
    {
        this.greeter = greeter;
    }
}

/// A clock the application may override.
class Clock
{
    /// Seconds since the epoch, fixed for the sample.
    long now()
    {
        return 42;
    }
}

/// Reports whether the configuration proxy returned the singleton clock.
final class ClockReport
{
    /// Whether two direct calls to `clock()` returned the same instance.
    bool singleton;

    /// Constructed by a bean method.
    this(bool singleton)
    {
        this.singleton = singleton;
    }
}

/// Never created: its condition names a class missing from the closure.
final class Missing
{
}

/// Bean methods; proxied so that inter-bean calls return the container's instances.
@Configuration class GreetingConfig
{
    /// Outside production.
    @Bean @Profile("!prod") Greeter friendlyGreeter()
    {
        return new FriendlyGreeter;
    }

    /// In production.
    @Bean("formalGreeter") @Profile("prod") Greeter formal()
    {
        return new FormalGreeter;
    }

    /// Only with shop.audit.enabled=true.
    @Bean @ConditionalOnProperty(prefix: "shop.audit", name: ["enabled"], havingValue: "true")
    AuditLog auditLog(Greeter greeter)
    {
        return new AuditLog(greeter);
    }

    /// Unless the application defines its own clock.
    @Bean @ConditionalOnMissingBean Clock clock()
    {
        return new Clock;
    }

    /// Calls `clock()` directly: the configuration proxy returns the singleton.
    @Bean ClockReport clockReport(OwnerService owners)
    {
        return new ClockReport(clock() is clock());
    }

    /// Dropped at build time.
    @Bean @ConditionalOnClass(name: ["flint.does.not.Exist"]) Missing missing()
    {
        return new Missing;
    }
}
