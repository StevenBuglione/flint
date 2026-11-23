/// Single-page application serving for Flint Boot's web auto-configuration (ADR-028 section 5).
///
/// With a `[spa]` section, the application serves the built front end from `directory`: a file by its path, and
/// `index` for any other GET, so the client-side router owns those URLs. Paths under `/api/` that match no
/// controller stay 404, and `..` never leaves the directory.
module flint.boot_autoconfigure_web.spa;

import flint.arena : Result, Status;
import flint.config : ConfigurationProperties;
import flint.engine.di : ConditionalOnConfig;
import flint.engine.web : Get, PathVariable, RequestContext, Response, RestController;

@safe:

/// The `[spa]` section.
@ConditionalOnConfig("spa") @ConfigurationProperties("spa")
struct SpaProperties
{
    /// Directory of the built front end, relative to the working directory.
    string directory = "resources/static";
    /// The page served for client-side routes.
    string index = "index.html";
}

/// Serves the front end. Registered only with a `[spa]` section.
@ConditionalOnConfig("spa") @RestController("")
struct SpaController
{
    private SpaProperties properties;

    /// Receive the settings.
    this(SpaProperties properties)
    {
        this.properties = properties;
    }

    /// The index page.
    @Get("/")
    Result!Response root(ref scope RequestContext context)
    {
        return serve("", context);
    }

    /// A file, or the index page for a client-side route.
    @Get("/*path")
    Result!Response asset(@PathVariable("path") string path, ref scope RequestContext context)
    {
        return serve(path, context);
    }

    private Result!Response serve(string path, ref scope RequestContext context)
    {
        import std.algorithm.searching : canFind, startsWith;
        import std.file : exists, isFile, read;
        import std.path : buildPath, extension, pathSplitter;

        if (path.startsWith("api/") || path == "api")
            return Result!Response(Response(404, "application/json", textBody(context, `{"error":"not found"}`)));
        bool contained = true;
        foreach (segment; pathSplitter(path))
            contained = contained && segment != ".." && segment != ".";
        string file = buildPath(properties.directory, path);
        if (!contained || path.length == 0 || !exists(file) || !isFile(file))
            file = buildPath(properties.directory, properties.index);
        if (!exists(file) || !isFile(file))
            return Result!Response(Response(404, "application/json", textBody(context, `{"error":"not found"}`)));
        const bytes = cast(const(ubyte)[]) read(file);
        auto copied = context.arena.copyIn(bytes);
        if (!copied.ok())
            return Result!Response(Response(413, "application/json", textBody(context, `{"error":"asset too large"}`)));
        return Result!Response(Response(200, mediaType(extension(file)), copied.value));
    }
}

private imported!"flint.arena".Buffer textBody(ref scope RequestContext context, string text)
{
    auto copied = context.arena.copyIn(cast(const(ubyte)[]) text);
    return copied.ok() ? copied.value : imported!"flint.arena".Buffer.init;
}

/// The media type for a file extension.
string mediaType(string extension) pure
{
    foreach (entry; mediaTypes)
    {
        if (entry[0] == extension)
            return entry[1];
    }
    return "application/octet-stream";
}

private static immutable string[2][] mediaTypes = [
    [".html", "text/html; charset=utf-8"], [".js", "text/javascript; charset=utf-8"],
    [".mjs", "text/javascript; charset=utf-8"], [".css", "text/css; charset=utf-8"],
    [".json", "application/json"], [".map", "application/json"], [".svg", "image/svg+xml"],
    [".png", "image/png"], [".jpg", "image/jpeg"], [".jpeg", "image/jpeg"], [".ico",
        "image/x-icon"], [".woff2", "font/woff2"], [".txt", "text/plain; charset=utf-8"],
    [".wasm", "application/wasm"]
];
