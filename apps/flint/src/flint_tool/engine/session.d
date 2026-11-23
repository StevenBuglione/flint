/// State shared by every command: the Flint installation, output mode and terminal capabilities.
module flint_tool.engine.session;

import flint_tool.diagnostics.report : Palette, Report, Tone, paint;
import flint_tool.home.policy : Home;

@safe:

/// One flint invocation.
struct Session
{
    /// The Flint installation.
    Home home;
    /// Whether the home loaded.
    bool homeLoaded;
    /// When the session opened, near the process start: build receipts measure their phases from it.
    imported!"core.time".MonoTime started;
    /// Emit JSON on stdout instead of human text.
    bool json;
    /// Stream tool output and show more detail.
    bool verbose;
    /// Colors for stderr.
    Palette errorPalette;
    /// Colors for stdout.
    Palette outputPalette;
    /// Absolute path of this flint executable.
    string executable;
    /// SHA-256 of this flint executable, computed on first use.
    string executableSha;
    /// Terminal width of stderr, or zero.
    uint width;

    /// Print a progress line on stderr in human mode.
    void progress(string verb, string detail)
    {
        import std.string : rightJustify;
        import flint_tool.sys.posix : writeError;

        if (json)
            return;
        writeError(paint(rightJustify(verb, 12), errorPalette, Tone.fix) ~ " " ~ detail ~ "\n");
    }

    /// Print a line on stdout in human mode.
    void say(string text)
    {
        import flint_tool.sys.posix : writeOutput;

        if (!json)
            writeOutput(text ~ "\n");
    }

    /// SHA-256 of the running executable.
    string toolSha()
    {
        import flint_tool.support.files : cachedSha256File;

        if (executableSha.length == 0)
            executableSha = cachedSha256File(executable);
        return executableSha;
    }
}

/// Create a session: detect terminals through flint.term and find the Flint home.
Session openSession(bool json, bool verbose, ref Report report)
{
    import flint.term : ColorProfile, Stream, describe;
    import std.file : thisExePath;
    import std.process : environment;
    import flint_tool.home.policy : findHome, loadHome;

    import core.time : MonoTime;

    Session session;
    session.started = MonoTime.currTime;
    session.json = json;
    session.verbose = verbose;
    session.executable = thisExePath();
    const forced = environment.get("FLINT_COLOR", "auto");
    const errorInfo = describe(Stream.error);
    const outputInfo = describe(Stream.output);
    session.width = errorInfo.size.columns;
    session.errorPalette = Palette(forced == "always" || (forced == "auto" && errorInfo.colors != ColorProfile.none));
    session.outputPalette = Palette(forced == "always" || (forced == "auto" && outputInfo.colors != ColorProfile.none));
    const root = findHome();
    if (root is null)
    {
        const homeState = environment.get("FLINT_HOME", "").length ? "not a Flint installation" : "unset";
        const message = "no Flint installation above " ~ session.executable ~ " and FLINT_HOME is " ~ homeState;
        report.error("FLINT-E0801", message, "export FLINT_HOME=/path/to/flint");
        return session;
    }
    session.homeLoaded = loadHome(root, session.home, report);
    {
        import std.path : absolutePath, buildNormalizedPath, buildPath;
        import flint_tool.support.files : useDigestCache;

        const relocated = environment.get("FLINT_CACHE", "");
        useDigestCache(relocated.length
                ? buildNormalizedPath(absolutePath(relocated)) : buildPath(root, ".flint", "cache"));
    }
    return session;
}
