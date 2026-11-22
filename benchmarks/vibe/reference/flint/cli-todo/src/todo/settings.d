/// The configuration file: `$TODO_CONFIG`, or `$HOME/.config/todo/config.toml`.
module todo.settings;

import flint.config : ConfigurationProperties;

@safe:

/// The `[todo]` table. Keys bind relaxed: `data_file` sets `dataFile`.
@ConfigurationProperties("todo")
struct Settings
{
    /// Where the list lives; empty means `$HOME/.local/share/todo/todos.json`.
    string dataFile;
    /// The priority of items added without `--priority`.
    string defaultPriority = "normal";
}

/// Load the settings; false with a message naming the key on a configuration error.
bool loadSettings(out Settings settings, out string failure)
{
    import std.path : baseName, buildPath, dirName, stripExtension;
    import std.process : environment;
    import flint.config : ConfigOptions, load;
    import todo.store : validPriority;

    const home = environment.get("HOME", ".");
    const path = environment.get("TODO_CONFIG", buildPath(home, ".config", "todo", "config.toml"));
    ConfigOptions options;
    options.directory = dirName(path);
    options.baseName = stripExtension(baseName(path));
    options.readEnvironment = false;
    const loaded = load!Settings(options);
    if (!loaded.ok)
    {
        failure = loaded.error.message;
        return false;
    }
    settings = loaded.value;
    if (!validPriority(settings.defaultPriority))
    {
        failure = "todo.default_priority: must be low, normal or high";
        return false;
    }
    if (settings.dataFile.length == 0)
        settings.dataFile = buildPath(home, ".local", "share", "todo", "todos.json");
    return true;
}
