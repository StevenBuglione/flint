module scanned.app;

import flint.boot : CommandLineRunner, Exclude, FlintApplication;
import flint.config : ConfigurationProperties;
import flint.engine.di : AutoConfiguration, Service;

@safe:

@ConfigurationProperties("jobs")
struct JobProperties
{
    uint batch = 10;
}

@Service
final class Jobs
{
    JobProperties properties;
    this(JobProperties properties)
    {
        this.properties = properties;
    }
}

@Service
final class StartupReport : CommandLineRunner
{
    static string[] seen;
    private Jobs jobs;

    this(Jobs jobs)
    {
        this.jobs = jobs;
    }

    int run(string[] args)
    {
        import std.conv : to;

        seen ~= "batch " ~ jobs.properties.batch.to!string;
        return args.length > 1 && args[1] == "--fail" ? 9 : 0;
    }
}

struct NotABean
{
}

/// Not scanned (no stereotype), and unbuildable here: if @Exclude failed, the context would not compile.
final class Unwanted
{
    this(NotABean missing)
    {
    }
}

alias UnwantedAutoConfiguration = AutoConfiguration!(Unwanted);

@FlintApplication
@Exclude!(UnwantedAutoConfiguration)
final class ScannedApplication
{
    static int main(string[] args)
    {
        return FlintApplication.run!ScannedApplication(args);
    }
}
