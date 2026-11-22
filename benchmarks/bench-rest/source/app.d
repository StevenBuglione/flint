module app;

import flint.web : runApplication;
import flint_bench_rest.profile : Application, minimalRestOptions;
import std.conv : to;
import std.string : lastIndexOf;

@safe:

int main(string[] args)
{
    auto options = minimalRestOptions();
    if (args.length != 1)
    {
        if (args.length != 3 || args[1] != "--listen")
            return 2;
        auto split = args[2].lastIndexOf(':');
        if (split < 1)
            return 2;
        options.address = args[2][0 .. cast(size_t) split];
        try
        {
            options.port = to!ushort(args[2][cast(size_t) split + 1 .. $]);
        }
        catch (Exception)
        {
            return 2;
        }
    }
    Application application;
    return runApplication(application, options);
}
