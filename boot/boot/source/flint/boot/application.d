/// `@FlintApplication`, `FlintApplication.run!App` and `mixin FlintMain!App`: Spring Boot's entry point, with
/// compile-time component scanning (ADR-029 section 2, ADR-028 section 9).
///
/// `flint build` writes `.flint/generated/scan/flint_scan.d`. It imports every module under `src/<project>/` and
/// the auto-configuration of every declared starter, and registers the scanned runner for the application class
/// from its module constructor. No module imports it, so scanning adds no import cycle.
module flint.boot.application;

import flint.arena : Status;

@safe:

/// Marks the application class, and starts it: `FlintApplication.run!App(args)`, as `SpringApplication.run`.
struct FlintApplication
{
    /// Run the application `App`: the beans `flint build` scanned under `src/<project>/`, and the
    /// auto-configuration of the declared starters.
    static int run(App)(string[] args)
    {
        import flint.boot : report;

        if (scannedRunner is null || scannedFor != App.mangleof)
            return report(70, "flint: " ~ App.stringof
                    ~ " was not scanned; build it with `flint build`, which writes "
                    ~ ".flint/generated/scan/flint_scan.d");
        return scannedRunner(args);
    }

    /// Called by the generated scan module: the runner of `App` over `Modules` and `AutoConfigurations`.
    static void register(App, AutoConfigurations, Modules...)()
    {
        scannedFor = App.mangleof;
        scannedRunner = &runScanned!(App, AutoConfigurations, Modules);
    }
}

/// Generates the process entry point, which D requires as a free function, calling `App.main(args)`.
mixin template FlintMain(App)
{
    int main(string[] args)
    {
        return App.main(args);
    }
}

/// Turns off the listed auto-configurations: `@Exclude!(DataSourceAutoConfiguration)` on the application class, as
/// `@SpringBootApplication(exclude = ...)`.
struct Exclude(AutoConfigurations...)
{
}

/// A bean run after the context starts, before the server, with the command-line arguments.
interface CommandLineRunner
{
    /// Run; a nonzero result stops the application with that exit code.
    int run(string[] args);
}

/// The list of auto-configurations the scan found for the declared starters.
struct AutoConfigurationList(Lists...)
{
}

// Set by the scan module's constructor and read by `main`, both on the main thread, so thread-local storage holds
// them.
private int function(string[]) @safe scannedRunner;
private string scannedFor;

private int runScanned(App, AutoConfigurations, Modules...)(string[] args)
{
    import flint.boot : runApplication;

    static if (is(AutoConfigurations == AutoConfigurationList!Lists, Lists...))
        alias Applied = Excluded!(App, Lists);
    import flint.boot : printBanner;

    printBanner(App.stringof, args);
    return runApplication!(Applied, ScannedBeans!Modules)(args);
}

// The auto-configurations that the application class does not exclude.
private template Excluded(App, Lists...)
{
    import std.meta : AliasSeq, Filter, staticIndexOf, staticMap;

    template excludedBy(alias Attribute)
    {
        static if (is(Attribute == Exclude!Types, Types...))
            alias excludedBy = Types;
        else
            alias excludedBy = AliasSeq!();
    }

    alias Excludes = staticMap!(excludedBy, __traits(getAttributes, App));
    template kept(alias List)
    {
        enum kept = staticIndexOf!(List, Excludes) < 0;
    }

    alias Excluded = Filter!(kept, Lists);
}

/// The beans of the scanned modules: every class or struct annotated `@Component`, `@Service`, `@Repository`,
/// `@RestController` or `@ControllerAdvice`, and every `@ConfigurationProperties` struct as `Provided!T`.
template ScannedBeans(Modules...)
{
    import std.meta : AliasSeq, staticMap;

    alias ScannedBeans = staticMap!(beansOf, Modules);
}

private template beansOf(alias Module)
{
    import std.meta : AliasSeq, staticMap;

    template member(string name)
    {
        static if (__traits(compiles, __traits(getMember, Module, name)) && is(__traits(getMember,
                Module, name) Type) && (is(Type == class) || is(Type == struct)) && __traits(compiles,
                __traits(getAttributes, Type)))
            alias member = beanEntry!Type;
        else
            alias member = AliasSeq!();
    }

    alias beansOf = staticMap!(member, __traits(allMembers, Module));
}

private template beanEntry(T)
{
    import flint.config : ConfigurationProperties;
    import flint.di : Component, Provided, Repository, Service;
    import std.meta : AliasSeq;

    // flint:boot sits below flint:web, so the web stereotypes are matched by name.
    enum kind = () {
        int found;
        static foreach (attribute; __traits(getAttributes, T))
        {
            static if (is(typeof(attribute) == ConfigurationProperties))
                found = 2;
            else static if (is(attribute == Service) || is(attribute == Component) || is(attribute == Repository))
                found = found ? found : 1;
            else static if (is(typeof(attribute)) && (is(typeof(attribute) == Service)
                    || is(typeof(attribute) == Component) || is(typeof(attribute) == Repository) || __traits(identifier,
                    typeof(attribute)) == "RestController" || __traits(identifier,
                    typeof(attribute)) == "ControllerAdvice"))
                found = found ? found : 1;
        }
        return found;
    }();
    static if (kind == 2)
        alias beanEntry = Provided!T;
    else static if (kind == 1)
        alias beanEntry = T;
    else
        alias beanEntry = AliasSeq!();
}
