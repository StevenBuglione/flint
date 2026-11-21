module flint.config.internal.layers;

import flint.arena : Error, Result, Status;
import flint.config.internal.sources : InputValue, Inputs, Origin, SourceFile, joinKey,
    keyComponent, maxConfigDepth, putInput, readDotEnv, readJson, sourceFile;
import flint.config.types : ConfigOptions;
import flint.serde : DecodeOptions;
import flint.serde.owned : readTomlEntries;
import std.algorithm.searching : startsWith;
import std.process : environment;

@safe:

package(flint.config) struct Layers
{
    Inputs files;
    Inputs dotenv;
    Inputs arguments;
    string[string] process;
}

private Error readArguments(scope const(string)[] arguments, ref string profile, ref Inputs overrides)
{
    const origin = Origin("command line");
    bool choseProfile;
    foreach (argument; arguments)
    {
        if (argument.startsWith("--flint.profile="))
        {
            if (choseProfile)
                return origin.report(Status.conflict, "flint.profile", "was specified more than once");
            profile = argument["--flint.profile=".length .. $].idup;
            choseProfile = true;
        }
        else if (argument.startsWith("--set="))
        {
            const valueAndKey = argument["--set=".length .. $];
            size_t equals;
            while (equals < valueAndKey.length && valueAndKey[equals] != '=')
                ++equals;
            if (equals == 0 || equals == valueAndKey.length)
                return origin.report(Status.invalidArgument, "", "requires --set=key=value");
            const key = valueAndKey[0 .. equals].idup;
            const value = valueAndKey[equals + 1 .. $].idup;
            const failure = putInput(overrides, key, InputValue(value, origin));
            if (failure.code != Status.ok)
                return failure;
        }
        else if (argument == "--set" || argument == "--flint.profile")
            return origin.report(Status.invalidArgument, "", "requires an equals-delimited option");
    }
    return Error.init;
}

private Error readToml(string name, string text, ref Inputs values)
{
    auto options = DecodeOptions.init;
    options.maxDepth = maxConfigDepth;
    const entries = readTomlEntries(text, options);
    if (!entries.ok)
    {
        const at = Origin(name, text, entries.error.offset);
        return at.report(entries.error.code, "", "contains invalid TOML or exceeds the document limits");
    }
    foreach (entry; entries.value)
    {
        const origin = Origin(name, text, entry.offset);
        string key;
        foreach (part; entry.path)
        {
            if (!keyComponent(part))
                return origin.report(Status.invalidArgument, key, "has an invalid key component");
            key = joinKey(key, part);
        }
        const failure = putInput(values, key, InputValue(entry.json, origin, true));
        if (failure.code != Status.ok)
            return failure;
    }
    return Error.init;
}

private Error overlay(SourceFile file, string name, bool toml, ref Inputs values)
{
    if (!file.present)
        return Error.init;
    Inputs source;
    const failure = toml ? readToml(name, file.text, source) : readJson(name, file.text, source);
    if (failure.code != Status.ok)
        return failure;
    foreach (key, value; source)
        values[key] = value;
    return Error.init;
}

private enum FileFormat
{
    unspecified,
    json,
    toml
}

private struct ApplicationFile
{
    SourceFile file;
    FileFormat kind;
}

private Result!ApplicationFile selectFile(string directory, string stem, FileFormat preferred)
{
    alias Selected = Result!ApplicationFile;
    const toml = preferred == FileFormat.json ? Result!SourceFile.init : sourceFile(directory, stem ~ ".toml");
    if (!toml.ok)
        return Selected(ApplicationFile.init, toml.error);
    const json = preferred == FileFormat.toml ? Result!SourceFile.init : sourceFile(directory, stem ~ ".json");
    if (!json.ok)
        return Selected(ApplicationFile.init, json.error);
    if (toml.value.present && json.value.present)
        return Selected(ApplicationFile.init, Origin(stem).report(Status.conflict, "",
                "specifies both JSON and TOML"));
    if (toml.value.present)
        return Selected(ApplicationFile(toml.value, FileFormat.toml));
    if (json.value.present)
        return Selected(ApplicationFile(json.value, FileFormat.json));
    return Selected(ApplicationFile.init);
}

private Error loadFile(ApplicationFile selected, string stem, ref Inputs values)
{
    const toml = selected.kind == FileFormat.toml;
    const extension = toml ? ".toml" : ".json";
    return overlay(selected.file, stem ~ extension, toml, values);
}

private Error applicationFiles(string directory, string profile, ref Inputs values)
{
    const baseFile = selectFile(directory, "application", FileFormat.unspecified);
    if (!baseFile.ok)
        return baseFile.error;
    const stem = "application-" ~ profile;
    const profileFile = selectFile(directory, stem, baseFile.value.kind);
    if (!profileFile.ok)
        return profileFile.error;
    const base = loadFile(baseFile.value, "application", values);
    if (base.code != Status.ok)
        return base;
    return loadFile(profileFile.value, stem, values);
}

package(flint.config) Error loadLayers(scope const ref ConfigOptions options, ref Layers layers)
{
    layers.process = environment.toAA();
    string profile = options.profile.idup;
    if (const fromEnvironment = "FLINT_PROFILE" in layers.process)
        profile = *fromEnvironment;
    auto failure = readArguments(options.arguments, profile, layers.arguments);
    if (failure.code != Status.ok)
        return failure;
    if (profile.length > 32 || !keyComponent(profile))
        return Origin("profile selection").report(Status.invalidArgument, "flint.profile",
                "has an invalid profile name");
    layers.process.remove("FLINT_PROFILE");

    const directory = options.directory.idup;
    failure = applicationFiles(directory, profile, layers.files);
    if (failure.code != Status.ok)
        return failure;
    const dotenv = sourceFile(directory, ".env");
    if (!dotenv.ok)
        return dotenv.error;
    if (dotenv.value.present)
        failure = readDotEnv(dotenv.value.text, layers.dotenv);
    return failure;
}
