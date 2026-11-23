// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/context/config/ConfigDataEnvironment.java
// with Profiles.java, ConfigDataLocation.java, ConfigDataProperties.java, StandardConfigDataLocationResolver.java and
// InvalidConfigDataPropertyException.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: contributors are flattened into one ordered list per location group; the class path
// is the application's `resources/` directory; `flint.*` keys are canonical and `spring.*` keys are aliases.

/// `org.springframework.boot.context.config`: loading config data into the environment at startup.
///
/// The search follows Boot exactly:
/// - **Locations.** `optional:classpath:/;optional:classpath:/config/` is the first location group, and
///   `optional:file:./;optional:file:./config/;optional:file:./config/*/` the second.
///   `flint.config.location` replaces the defaults, and `flint.config.additional-location` adds groups after them.
///   `,` separates groups and `;` separates locations within a group. A later group overrides an earlier one, and
///   inside a group a later location overrides an earlier one.
/// - **Files.** `flint.config.name` (default `application`) with `.properties`, `.yml` and `.yaml`. At one location,
///   `.properties` wins over YAML. Inside a file, a later `---` (or `#---`) document overrides an earlier one.
/// - **Profiles.** The profiles are `flint.profiles.active`, with programmatic additional profiles and
///   `flint.profiles.include` first, expanded through `flint.profiles.group.*`. When none is active, they are
///   `flint.profiles.default` (default `default`). `FLINT_PROFILES_ACTIVE` in the environment sets them at deploy
///   time.
/// - **Profile files and documents.** Profile files (`application-{profile}.yaml`) are read for every accepted
///   profile: in a group they override its plain files, and a later profile overrides an earlier one. A document
///   with `flint.config.activate.on-profile` (a profile expression, or a list of them) is active only when that
///   expression matches.
///
/// Every key may use the `spring.*` spelling instead of `flint.*`.
module flint.boot.context.config;

import flint.boot.context.properties.bind : PlaceholdersResolver, PropertySourcesPlaceholdersResolver;
import flint.boot.context.properties.source : ConfigurationPropertyName, ConfigurationPropertySource,
    ConfigurationPropertySources, MapConfigurationPropertySource, SystemEnvironmentPropertySource;
import flint.boot.env : OriginTrackedMapPropertySource, PropertiesPropertySourceLoader,
    PropertySourceLoader, YamlPropertySourceLoader;
import flint.boot.internal.core_env : CommandLineArgs;
import flint.java.lang : IllegalStateException, RuntimeException;

@safe:

/// Reads resources for config data: the class path root and the file system. Tests supply an in-memory one.
interface ConfigDataResourceReader
{
    /// The bytes of `path`, or `null` when it does not exist.
    const(ubyte)[] read(string path);

    /// The immediate subdirectories of `directory`, sorted, for `config/*/` locations.
    string[] subdirectories(string directory);

    /// Whether the directory `directory` exists.
    bool directoryExists(string directory);
}

/// The file system, with the class path at `classpathRoot`.
final class FileConfigDataResourceReader : ConfigDataResourceReader
{
    /// The bytes of the file `path`, or `null` when it is missing or a directory.
    const(ubyte)[] read(string path)
    {
        import std.file : exists, isFile, readFile = read;

        if (!exists(path) || !isFile(path))
            return null;
        return cast(const(ubyte)[]) readFile(path);
    }

    /// The subdirectories of `directory`, sorted by name.
    string[] subdirectories(string directory)
    {
        import std.algorithm.sorting : sort;
        import std.file : SpanMode, dirEntries;

        if (!directoryExists(directory))
            return null;
        string[] result;
        foreach (entry; dirEntries(directory, SpanMode.shallow))
        {
            if (entry.isDir)
                result ~= entry.name;
        }
        result.sort();
        return result;
    }

    /// Whether `directory` is an existing directory.
    bool directoryExists(string directory)
    {
        import std.file : exists, isDir;

        return exists(directory) && isDir(directory);
    }
}

/// A config data location such as `optional:classpath:/config/`.
struct ConfigDataLocation
{
    /// The `optional:` prefix.
    static immutable string OPTIONAL_PREFIX = "optional:";

    private string value;
    private bool optional;

    /// Parse one location.
    static ConfigDataLocation of(string location) pure
    {
        import std.algorithm.searching : startsWith;
        import std.string : strip;

        auto text = location.strip;
        if (text.startsWith(OPTIONAL_PREFIX))
            return ConfigDataLocation(text[OPTIONAL_PREFIX.length .. $], true);
        return ConfigDataLocation(text, false);
    }

    /// The location without `optional:`.
    string getValue() const pure nothrow @nogc
    {
        return value;
    }

    /// Whether a missing location is ignored.
    bool isOptional() const pure nothrow @nogc
    {
        return optional;
    }

    /// The location as written.
    string toString() const pure
    {
        return (optional ? OPTIONAL_PREFIX : "") ~ value;
    }

    /// The location groups of a property value: `,` separates groups, `;` locations within a group.
    static ConfigDataLocation[][] groups(string text) pure
    {
        import std.algorithm.iteration : filter, map, splitter;
        import std.array : array;
        import std.string : strip;

        ConfigDataLocation[][] result;
        foreach (group; text.splitter(','))
        {
            auto locations = group.splitter(';').map!(l => l.strip)
                .filter!(l => l.length > 0)
                .map!(l => ConfigDataLocation.of(l))
                .array;
            if (locations.length)
                result ~= locations;
        }
        return result;
    }
}

/// Thrown when a required config data location cannot be found.
class ConfigDataLocationNotFoundException : RuntimeException
{
    private ConfigDataLocation location;

    /// The missing `location`.
    this(ConfigDataLocation location) pure
    {
        super("Config data location '" ~ location.toString() ~ "' cannot be found");
        this.location = location;
    }

    /// The missing location.
    ConfigDataLocation getLocation() const pure nothrow @nogc
    {
        return location;
    }
}

/// Thrown when a profile-specific document sets a property only a plain document may set.
class InvalidConfigDataPropertyException : RuntimeException
{
    /// The rejected `property` and the `origin` that set it.
    this(string property, string location) pure
    {
        super("Property '" ~ property ~ "' imported from location '" ~ location
                ~ "' is invalid in a profile specific resource");
    }
}

/// The profiles of a run: active, default and accepted, as Boot computes them.
final class Profiles
{
    private string[] active;
    private string[] defaults;

    /// Profiles from their already-expanded lists.
    this(string[] active, string[] defaults) pure nothrow
    {
        this.active = active;
        this.defaults = defaults;
    }

    /// The active profiles, in order.
    const(string)[] getActive() const pure nothrow @nogc
    {
        return active;
    }

    /// The default profiles, in order.
    const(string)[] getDefault() const pure nothrow @nogc
    {
        return defaults;
    }

    /// The active profiles, or the default ones when none is active.
    const(string)[] getAccepted() const pure nothrow @nogc
    {
        return active.length ? active : defaults;
    }

    /// Whether `profile` is accepted.
    bool isAccepted(string profile) const pure nothrow @nogc
    {
        foreach (accepted; getAccepted())
        {
            if (accepted == profile)
                return true;
        }
        return false;
    }
}

/// What to load and from where.
struct ConfigDataEnvironmentOptions
{
    /// The command-line arguments (without the program name).
    string[] args;
    /// The process environment.
    string[string] environment;
    /// The class path root: the application's packaged resources.
    string classpathRoot = "resources";
    /// The directory `file:` locations are relative to.
    string workingDirectory = ".";
    /// Profiles added programmatically (`FlintApplication.setAdditionalProfiles`).
    string[] additionalProfiles;
    /// `FlintApplication.setDefaultProperties`, lowest precedence.
    string[string] defaultProperties;
    /// Inlined test properties (`@FlintBootTest(properties: ...)`), highest precedence.
    string[string] inlinedProperties;
    /// Where files are read from; the file system when `null`.
    ConfigDataResourceReader reader;
}

/// The environment config data produced: property sources in precedence order and the profiles.
final class ConfigDataResult
{
    private ConfigurationPropertySource[] sources;
    private Profiles profiles;

    /// The sources, highest precedence first, and the profiles.
    this(ConfigurationPropertySource[] sources, Profiles profiles) pure nothrow
    {
        this.sources = sources;
        this.profiles = profiles;
    }

    /// The property sources, highest precedence first.
    ConfigurationPropertySource[] getSources() pure nothrow @nogc
    {
        return sources;
    }

    /// The profiles.
    Profiles getProfiles() pure nothrow @nogc
    {
        return profiles;
    }

    /// The value of `name` (canonical, `flint.*` also found as `spring.*`), or `null`.
    string getProperty(string name)
    {
        auto property = ConfigurationPropertySources.find(sources, ConfigurationPropertyName.of(name));
        return property is null ? null : property.getValue();
    }
}

/// Loads config data, as Boot's `ConfigDataEnvironment.processAndApply`.
final class ConfigDataEnvironment
{
    private enum activeProperty = "flint.profiles.active";
    private enum defaultProperty = "flint.profiles.default";
    private enum includeProperty = "flint.profiles.include";
    private enum groupProperty = "flint.profiles.group";
    private enum onProfileProperty = "flint.config.activate.on-profile";
    private enum onCloudPlatformProperty = "flint.config.activate.on-cloud-platform";
    private enum locationProperty = "flint.config.location";
    private enum additionalLocationProperty = "flint.config.additional-location";
    private enum nameProperty = "flint.config.name";
    private enum defaultLocations = "optional:classpath:/;optional:classpath:/config/,"
        ~ "optional:file:./;optional:file:./config/;optional:file:./config/*/";

    private ConfigDataEnvironmentOptions options;
    private ConfigDataResourceReader reader;

    /// An environment to load with `options`.
    this(ConfigDataEnvironmentOptions options)
    {
        this.options = options;
        this.reader = options.reader is null ? new FileConfigDataResourceReader : options.reader;
    }

    /// Load everything and decide the profiles.
    ConfigDataResult processAndApply()
    {
        import flint.boot.internal.core_env : parseCommandLine;

        ConfigurationPropertySource[] bootstrap;
        if (options.inlinedProperties.length)
        {
            auto inlined = new MapConfigurationPropertySource("Inlined Test Properties");
            inlined.putAll(options.inlinedProperties);
            bootstrap ~= inlined;
        }
        bootstrap ~= commandLineSource(parseCommandLine(options.args));
        bootstrap ~= new SystemEnvironmentPropertySource(options.environment);
        auto defaults = new MapConfigurationPropertySource("defaultProperties");
        defaults.putAll(options.defaultProperties);

        const names = listValue(bootstrap ~ cast(ConfigurationPropertySource) defaults, nameProperty, [
            "application"
        ]);
        auto groups = locationGroups(bootstrap ~ cast(ConfigurationPropertySource) defaults);

        // Phase 1: every document of the plain files, kept with its activation.
        Document[][] plain;
        foreach (group; groups)
            plain ~= loadGroup(group, names, null);

        // Phase 2: profiles, from the bootstrap sources and the documents active without profiles.
        auto withoutProfiles = activeSources(bootstrap, plain, defaults);
        auto profiles = deduceProfiles(withoutProfiles, collectIncludes(plain, withoutProfiles));

        // Phase 3: profile files and on-profile documents, later groups first.
        auto configData = orderGroups(groups, plain, profiles, names);
        validate(configData);
        return new ConfigDataResult(bootstrap ~ configData ~ cast(ConfigurationPropertySource) defaults, profiles);
    }

private:
    static final class Document
    {
        MapConfigurationPropertySource source;
        string location;
        bool profileSpecific;
        string[] onProfile;
        bool cloudPlatformOnly;

        bool isActive(Profiles profiles)
        {
            import flint.boot.internal.core_env : matchesProfiles;

            if (cloudPlatformOnly)
                return false;
            if (onProfile.length == 0)
                return true;
            if (profiles is null)
                return false;
            return matchesProfiles(onProfile, (string p) => profiles.isAccepted(p));
        }
    }

    ConfigurationPropertySource[] orderGroups(ConfigDataLocation[][] groups, Document[][] plain,
            Profiles profiles, const string[] names)
    {
        ConfigurationPropertySource[] result;
        foreach (index, group; groups)
        {
            Document[] lowToHigh = plain[index];
            foreach (profile; profiles.getAccepted())
                lowToHigh ~= loadGroup(group, names, profile);
            ConfigurationPropertySource[] groupSources;
            foreach_reverse (document; lowToHigh)
            {
                if (document.isActive(profiles))
                    groupSources ~= document.source;
            }
            result = groupSources ~ result;
        }
        return result;
    }

    static MapConfigurationPropertySource commandLineSource(CommandLineArgs args) pure
    {
        auto source = new MapConfigurationPropertySource("commandLineArgs");
        foreach (name; args.getOptionNames())
        {
            import std.array : join;

            source.put(name, args.getOptionValues(name).join(","),
                    "\"" ~ name ~ "\" from property source \"commandLineArgs\"");
        }
        return source;
    }

    ConfigDataLocation[][] locationGroups(ConfigurationPropertySource[] sources)
    {
        auto replaced = rawValue(sources, locationProperty);
        auto groups = ConfigDataLocation.groups(replaced is null ? defaultLocations : replaced);
        auto additional = rawValue(sources, additionalLocationProperty);
        if (additional !is null)
            groups ~= ConfigDataLocation.groups(additional);
        return groups;
    }

    // The documents of one location group for `profile` (`null` for the plain files), lowest precedence first.
    Document[] loadGroup(ConfigDataLocation[] group, const string[] names, string profile)
    {
        Document[] result;
        foreach (location; group)
        {
            const before = result.length;
            foreach (directory; directoriesOf(location))
            {
                if (isFileLocation(location.getValue()))
                {
                    if (profile is null)
                        result ~= loadFile(location, directory, profile);
                    continue;
                }
                foreach (name; names)
                    result ~= loadName(location, directory, name, profile);
            }
            if (profile is null && result.length == before && !location.isOptional() && !locationExists(location))
                throw new ConfigDataLocationNotFoundException(location);
        }
        return result;
    }

    static bool isFileLocation(string value) pure nothrow @nogc
    {
        return value.length && value[$ - 1] != '/';
    }

    bool locationExists(ConfigDataLocation location)
    {
        import std.algorithm.searching : endsWith;

        const path = resolve(location.getValue());
        if (!isFileLocation(location.getValue()))
            return reader.directoryExists(path.endsWith("/*/") ? path[0 .. $ - 3] : path[0 .. $ - 1]);
        return reader.read(path) !is null;
    }

    // `classpath:/config/` → the class path directory; `file:./config/*/` → each subdirectory.
    string[] directoriesOf(ConfigDataLocation location)
    {
        import std.algorithm.searching : endsWith;

        const path = resolve(location.getValue());
        if (path.endsWith("/*/"))
            return reader.subdirectories(path[0 .. $ - 3]).map!(d => d ~ "/");
        return [path];
    }

    string resolve(string value) const pure
    {
        import std.algorithm.searching : startsWith;
        import std.path : buildNormalizedPath;

        string root, rest;
        if (value.startsWith("classpath:"))
        {
            root = options.classpathRoot;
            rest = value["classpath:".length .. $];
        }
        else if (value.startsWith("file:"))
        {
            root = options.workingDirectory;
            rest = value["file:".length .. $];
        }
        else
        {
            root = options.workingDirectory;
            rest = value;
        }
        while (rest.startsWith("/"))
            rest = rest[1 .. $];
        const trailing = value.length && value[$ - 1] == '/';
        auto path = rest.length ? buildNormalizedPath(root, rest) : buildNormalizedPath(root);
        return trailing ? path ~ "/" : path;
    }

    Document[] loadName(ConfigDataLocation location, string directory, string name, string profile)
    {
        // Lowest precedence first: YAML, then .properties.
        static immutable extensions = ["yaml", "yml", "properties"];
        Document[] result;
        foreach (extension; extensions)
        {
            const file = directory ~ name ~ (profile is null ? "" : "-" ~ profile) ~ "." ~ extension;
            result ~= loadPath(location, file, profile !is null);
        }
        return result;
    }

    Document[] loadFile(ConfigDataLocation location, string path, string)
    {
        return loadPath(location, path, false);
    }

    Document[] loadPath(ConfigDataLocation location, string path, bool profileSpecific)
    {
        import std.algorithm.searching : endsWith, startsWith;

        import std.path : buildNormalizedPath;

        path = buildNormalizedPath(path);
        auto bytes = reader.read(path);
        if (bytes is null)
            return null;
        const description = describe(location, path);
        PropertySourceLoader loader;
        if (path.endsWith(".properties"))
            loader = new PropertiesPropertySourceLoader;
        else if (path.endsWith(".yml") || path.endsWith(".yaml"))
            loader = new YamlPropertySourceLoader;
        else
            throw new IllegalStateException("File extension of config file location '" ~ location.toString()
                    ~ "' is not known to any PropertySourceLoader");
        Document[] result;
        foreach (loaded; loader.load("Config resource '" ~ description ~ "' via location '" ~ location.toString() ~ "'",
                description, bytes))
            result ~= document(loaded, location, profileSpecific);
        return result;
    }

    string describe(ConfigDataLocation location, string path) const pure
    {
        import std.algorithm.searching : startsWith;

        if (location.getValue().startsWith("classpath:"))
        {
            auto relative = path.length > options.classpathRoot.length ? path[options.classpathRoot.length .. $] : path;
            while (relative.startsWith("/"))
                relative = relative[1 .. $];
            return "class path resource [" ~ relative ~ "]";
        }
        return "file [" ~ path ~ "]";
    }

    Document document(OriginTrackedMapPropertySource loaded, ConfigDataLocation location, bool profileSpecific)
    {
        auto source = new MapConfigurationPropertySource(loaded.getName());
        foreach (key; loaded.getPropertyNames())
        {
            auto origin = loaded.getOrigin(key);
            source.put(key, loaded.getProperty(key), origin is null ? null : origin.toString());
        }
        auto result = new Document;
        result.source = source;
        result.location = location.toString();
        result.profileSpecific = profileSpecific;
        ConfigurationPropertySource[] own = [source];
        result.onProfile = listValue(own, onProfileProperty, null);
        result.cloudPlatformOnly = rawValue(own, onCloudPlatformProperty) !is null;
        if (result.onProfile.length || profileSpecific)
            rejectProfileProperties(source, result.location);
        return result;
    }

    // Boot's InvalidConfigDataPropertyException: profile documents may not set the profiles themselves.
    static void rejectProfileProperties(MapConfigurationPropertySource source, string location)
    {
        ConfigurationPropertySource[] own = [source];
        foreach (property; [activeProperty, defaultProperty, includeProperty])
        {
            if (rawValue(own, property) !is null || ConfigurationPropertySources.containsDescendantOf(own,
                    ConfigurationPropertyName.of(property)))
                throw new InvalidConfigDataPropertyException(property, location);
        }
    }

    static ConfigurationPropertySource[] activeSources(ConfigurationPropertySource[] bootstrap,
            Document[][] plain, ConfigurationPropertySource defaults)
    {
        ConfigurationPropertySource[] configData;
        foreach (group; plain)
        {
            ConfigurationPropertySource[] groupSources;
            foreach_reverse (document; group)
            {
                if (document.onProfile.length == 0 && !document.cloudPlatformOnly)
                    groupSources ~= document.source;
            }
            configData = groupSources ~ configData;
        }
        return bootstrap ~ configData ~ defaults;
    }

    // Boot binds each document's `include` with placeholders resolved against every active contributor
    // (ConfigDataEnvironmentContributorPlaceholdersResolver).
    static string[] collectIncludes(Document[][] plain, ConfigurationPropertySource[] active)
    {
        auto resolver = new PropertySourcesPlaceholdersResolver(active);
        string[] result;
        foreach (group; plain)
        {
            foreach (document; group)
            {
                if (document.onProfile.length || document.cloudPlatformOnly)
                    continue;
                ConfigurationPropertySource[] own = [document.source];
                foreach (profile; listValue(own, includeProperty, null, resolver))
                    result = appendUnique(result, profile);
            }
        }
        return result;
    }

    Profiles deduceProfiles(ConfigurationPropertySource[] sources, string[] included)
    {
        auto resolver = new PropertySourcesPlaceholdersResolver(sources);
        auto groups = profileGroups(sources, resolver);
        string[] additional;
        foreach (profile; options.additionalProfiles ~ included)
            additional = appendUnique(additional, profile);
        string[] active = additional;
        foreach (profile; listValue(sources, activeProperty, null, resolver))
            active = appendUnique(active, profile);
        auto defaults = listValue(sources, defaultProperty, ["default"], resolver);
        return new Profiles(expand(active, groups), expand(defaults, groups));
    }

    static string[][string] profileGroups(ConfigurationPropertySource[] sources, PlaceholdersResolver resolver)
    {
        auto prefix = ConfigurationPropertyName.of(groupProperty);
        string[][string] groups;
        foreach (name; ConfigurationPropertySources.names(sources))
        {
            if (!prefix.isAncestorOf(name))
                continue;
            const group = name.getElement(prefix.getNumberOfElements(), ConfigurationPropertyName.Form.ORIGINAL);
            if ((group in groups) !is null)
                continue;
            groups[group] = listValue(sources, groupProperty ~ "." ~ group, null, resolver);
        }
        return groups;
    }

    static string[] expand(string[] profiles, string[][string] groups)
    {
        string[] stack;
        foreach_reverse (profile; profiles)
            stack ~= profile;
        string[] expanded;
        while (stack.length)
        {
            const current = stack[$ - 1];
            stack = stack[0 .. $ - 1];
            bool seen;
            foreach (existing; expanded)
                seen = seen || existing == current;
            if (seen)
                continue;
            expanded ~= current;
            if (auto members = current in groups)
            {
                foreach_reverse (member; *members)
                    stack ~= member;
            }
        }
        return expanded;
    }

    void validate(ConfigurationPropertySource[] configData)
    {
        // Reserved for Boot's checks of invalid legacy properties (`spring.profiles`) in config data.
        ConfigurationPropertySource[] own = configData;
        if (rawValue(own, "flint.profiles") !is null)
            throw new InvalidConfigDataPropertyException("spring.profiles", "config data");
    }

    static string rawValue(ConfigurationPropertySource[] sources, string name)
    {
        auto property = ConfigurationPropertySources.find(sources, ConfigurationPropertyName.of(name));
        return property is null ? null : property.getValue();
    }
}

/// A list property as Boot binds `Set<String>`: a comma-separated value, or indexed items `name[0]`, `name[1]`,
/// from the highest-precedence source that has either; `fallback` when none does. With a `resolver`, each value's
/// `${...}` placeholders are resolved before it is split, as Boot's binder does.
string[] listValue(ConfigurationPropertySource[] sources, string name, string[] fallback,
        PlaceholdersResolver resolver = null)
{
    import std.algorithm.iteration : filter, map, splitter;
    import std.array : array;
    import std.conv : to;
    import std.string : strip;

    string resolved(string value)
    {
        return resolver is null ? value : resolver.resolvePlaceholders(value);
    }

    auto canonical = ConfigurationPropertyName.of(name);
    foreach (source; sources)
    {
        ConfigurationPropertySource[] one = [source];
        if (auto property = ConfigurationPropertySources.find(one, canonical))
            return resolved(property.getValue()).splitter(',').map!(s => s.strip)
                .filter!(s => s.length > 0)
                .array;
        string[] items;
        for (size_t index;; index++)
        {
            auto item = ConfigurationPropertySources.find(one, canonical.append("[" ~ index.to!string ~ "]"));
            if (item is null)
                break;
            items ~= resolved(item.getValue()).strip;
        }
        if (items.length)
            return items;
    }
    return fallback;
}

private string[] appendUnique(string[] list, string value) pure
{
    foreach (existing; list)
    {
        if (existing == value)
            return list;
    }
    return list ~ value;
}

private string[] map(alias f)(string[] values)
{
    string[] result;
    foreach (value; values)
        result ~= f(value);
    return result;
}
