module core_io_localized_resource_test;

import flint.core.io : ByteArrayResource, ClassPathResource, DescriptiveResource, Resource, ResourceLoader;
import flint.core.io.support : LocalizedResourceHelper;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : Locale;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private final class RecordingLoader : ResourceLoader
{
    string[] lookups;
    string found;

    Resource getResource(string location)
    {
        lookups ~= location;
        if (location == found)
            return new ByteArrayResource(cast(immutable(ubyte)[]) "found", location);
        return new DescriptiveResource(location);
    }
}

@("locale fallback checks variant, country and language in order")
unittest
{
    auto loader = new RecordingLoader;
    loader.found = "messages_en.txt";
    auto helper = new LocalizedResourceHelper(loader);
    const locale = Nullable!Locale(Locale("en", "US", "POSIX"));

    assert(helper.findLocalizedResource("messages", ".txt", locale).getContentAsString() == "found");
    assert(loader.lookups == ["messages_en_US_POSIX.txt", "messages_en_US.txt", "messages_en.txt"]);
}

@("existing variant stops lookup even when the country is empty")
unittest
{
    auto loader = new RecordingLoader;
    loader.found = "messages_en__POSIX.txt";
    auto helper = new LocalizedResourceHelper(loader);
    const locale = Nullable!Locale(Locale("en", "", "POSIX"));

    assert(helper.findLocalizedResource("messages", ".txt", locale).getContentAsString() == "found");
    assert(loader.lookups == ["messages_en__POSIX.txt"]);
}

@("empty separator joins components and absent separator restores the default")
unittest
{
    auto loader = new RecordingLoader;
    auto helper = new LocalizedResourceHelper(loader);
    const locale = Nullable!Locale(Locale.US);

    helper.setSeparator(Nullable!string(""));
    assert(helper.findLocalizedResource("messages", ".txt", locale).getDescription() == "messages.txt");
    assert(loader.lookups == ["messagesenUS.txt", "messagesen.txt", "messages.txt"]);

    loader.lookups = null;
    helper.setSeparator(Nullable!string.init);
    assert(helper.findLocalizedResource("messages", ".txt", locale).getDescription() == "messages.txt");
    assert(loader.lookups == ["messages_en_US.txt", "messages_en.txt", "messages.txt"]);
}

@("absent locale returns the default handle without checking if it exists")
unittest
{
    auto loader = new RecordingLoader;
    auto helper = new LocalizedResourceHelper(loader);

    auto resource = helper.findLocalizedResource("messages", ".txt", Nullable!Locale.init);
    assert(loader.lookups == ["messages.txt"]);
    assert(resource.getDescription() == "messages.txt" && !resource.exists());

    auto defaultHelper = new LocalizedResourceHelper;
    const defaultResource = defaultHelper.findLocalizedResource("messages", ".txt", Nullable!Locale.init);
    assert(cast(const(ClassPathResource)) defaultResource !is null);
}

@("null loader or location parts are rejected")
unittest
{
    assertThrown!IllegalArgumentException(new LocalizedResourceHelper(cast(ResourceLoader) null));
    auto helper = new LocalizedResourceHelper;
    assertThrown!IllegalArgumentException(helper.findLocalizedResource(null, ".txt", Nullable!Locale.init));
    assertThrown!IllegalArgumentException(helper.findLocalizedResource("messages", null, Nullable!Locale.init));
}
