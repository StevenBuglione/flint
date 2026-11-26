/// ResourceBundleMessageSource resolves from several threads at once: its bundle cache is shared (sol-security found
/// the unguarded cold publication); each file is read once and every thread sees the same bundle.
module flint.context.message_source_threads_test;

import flint.context.support : ResourceBundleMessageSource;
import flint.java.util : Locale, Properties;

private immutable(ubyte)[] threadBundles(string path) @safe nothrow
{
    switch (path)
    {
    case "threads/messages.properties":
        return cast(immutable(ubyte)[]) "greeting=hello\nfarewell=bye\n";
    case "threads/messages_de.properties":
        return cast(immutable(ubyte)[]) "greeting=hallo\n";
    default:
        return null;
    }
}

private final class ExposedSource : ResourceBundleMessageSource
{
    Properties bundleFor(string file) @safe
    {
        return loadBundle(file);
    }
}

@("ResourceBundleMessageSource loads each bundle once while threads resolve concurrently")
unittest
{
    import core.thread : Thread;
    import flint.core.io : installEmbeddedResources;

    installEmbeddedResources(&threadBundles);
    auto source = new ExposedSource;
    source.setBasenames("threads/messages");

    enum threads = 8, rounds = 500;
    shared bool failed;
    Thread[threads] workers;
    foreach (index, ref worker; workers)
    {
        const german = index % 2 == 1;
        worker = new Thread({
            foreach (_; 0 .. rounds)
            {
                const locale = german ? Locale.GERMAN : Locale.ENGLISH;
                const greeting = source.getMessage("greeting", null, null, locale);
                const farewell = source.getMessage("farewell", null, null, locale);
                if (greeting != (german ? "hallo" : "hello") || farewell != "bye")
                    failed = true;
            }
        });
    }
    foreach (worker; workers)
        worker.start();
    foreach (worker; workers)
        worker.join();
    assert(!failed);
    assert(source.bundleFor("threads/messages.properties") is source.bundleFor("threads/messages.properties"));
    assert(source.bundleFor("threads/missing.properties") is null);
}
