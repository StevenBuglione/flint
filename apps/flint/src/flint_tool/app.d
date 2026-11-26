/// flint: the single entry point for building, testing and checking Flint code (ADR-018, ADR-021).
module flint_tool.app;

import flint.arena : Status;
import flint.cli : ParseAction, ParseResult, parse, writeCompletion, writeHelp;
import flint_tool.engine.session : Session, openSession;
import flint_tool.commands.args;
import flint_tool.commands.output : finishBare;
import flint_tool.diagnostics.report : Report;

@safe:

int main(string[] args)
{
    import flint_tool.support.process : closeTrace, installInterruptHandling, installTrace;

    version (Windows)
    {
        import flint_tool.sys.posix : prepareConsole;

        prepareConsole();
    }
    installInterruptHandling();
    installTrace();
    scope (exit)
        closeTrace();
    return dispatch(args.length ? args[1 .. $] : null);
}

/// Split argv at the first `--`: flint's own arguments, then the pass-through.
void splitPassthrough(scope const(string)[] arguments, out string[] own, out string[] passthrough)
{
    foreach (index, argument; arguments)
    {
        if (argument == "--")
        {
            own = arguments[0 .. index].dup;
            passthrough = arguments[index + 1 .. $].dup;
            return;
        }
    }
    own = arguments.dup;
}

/// `flint api extract --version TAG`: flint.cli reserves `--version`, so it becomes `--tag` for this subcommand.
string[] tagAlias(string[] own)
{
    import std.algorithm.searching : startsWith;

    if (own.length < 2 || own[0] != "api" || own[1] != "extract")
        return own;
    auto rewritten = own.dup;
    foreach (ref argument; rewritten)
    {
        if (argument == "--version")
            argument = "--tag";
        else if (argument.startsWith("--version="))
            argument = "--tag=" ~ argument["--version=".length .. $];
    }
    return rewritten;
}

/// Whether --json appears among flint's own arguments, so usage errors can also be reported as JSON.
bool wantsJson(scope const(string)[] arguments)
{
    foreach (argument; arguments)
    {
        if (argument == "--json")
            return true;
    }
    return false;
}

/// Run one flint command line and return the exit code.
int dispatch(scope const(string)[] arguments)
{
    import flint_tool.commands.tooling : commandVersion;
    import flint_tool.sys.posix : writeOutput;

    string[] own;
    string[] passthrough;
    splitPassthrough(arguments, own, passthrough);
    own = tagAlias(own);
    auto parsed = parse!FlintArgs(own);
    auto options = parsed.options;
    Report report;
    auto session = openSession(wantsJson(own), verbose(parsed.commandName, options), report);
    const early = earlyExit(session, report, parsed, own);
    if (early >= 0)
        return early;
    if (parsed.commandName == "flint")
    {
        printHelp("flint");
        return 0;
    }
    const explainOnly = parsed.commandName == "flint explain";
    if (!session.homeLoaded && !explainOnly)
        return finishBare(session, report, "flint.error/1");
    if (passthrough.length && parsed.commandName != "flint run"
            && parsed.commandName != "flint build" && parsed.commandName != "flint watch")
    {
        report.error("FLINT-E0001", "`--` passes arguments to the program of flint run, or flags to flint build",
                "remove the arguments after --");
        return finishBare(session, report, "flint.usage/1");
    }
    const status = projectCommand(session, parsed.commandName, options, passthrough);
    if (status >= 0)
        return status;
    const tooling = toolingCommand(session, parsed.commandName, options);
    if (tooling >= 0)
        return tooling;
    report.error("FLINT-E0002", "`" ~ parsed.commandName ~ "` needs a subcommand",
            "flint " ~ helpPath(parsed.commandName) ~ "--help");
    return finishBare(session, report, "flint.usage/1");
}

/// Usage errors, help, completion and --version, which end the command early; -1 otherwise.
private int earlyExit(ref Session session, ref Report report, const ref ParseResult!FlintArgs parsed,
        scope const(string)[] own)
{
    import flint_tool.commands.tooling : commandVersion;
    import flint_tool.sys.posix : writeOutput;

    if (parsed.error.code != Status.ok)
    {
        report.items = null;
        report.error("FLINT-E0001", parsed.error.message ~ (parsed.error.offset < own.length
                ? " (at `" ~ own[parsed.error.offset] ~ "`)" : ""), "flint " ~ helpPath(parsed.commandName) ~ "--help");
        return finishBare(session, report, "flint.usage/1");
    }
    final switch (parsed.action)
    {
    case ParseAction.help:
        printHelp(parsed.commandName);
        return 0;
    case ParseAction.completion:
        writeCompletion!FlintArgs(parsed.completionShell, (scope const(char)[] text) @safe {
            writeOutput(text);
        });
        return 0;
    case ParseAction.version_:
        if (!session.homeLoaded)
            return finishBare(session, report, "flint.version/1");
        return commandVersion(session, VersionArgs.init);
    case ParseAction.run:
        return -1;
    }
}

/// Run a project command; -1 when `name` is not one.
private int projectCommand(ref Session session, string name, ref FlintArgs options, string[] passthrough)
{
    import flint_tool.commands.project : commandBuild, commandCheck, commandFmt, commandLock,
        commandNew, commandRun, commandTest;

    switch (name)
    {
    case "flint new":
        return commandNew(session, options.create);
    case "flint build":
        return commandBuild(session, options.build, passthrough);
    case "flint run":
        return commandRun(session, options.run, passthrough);
    case "flint test":
        return commandTest(session, options.test);
    case "flint check":
        return commandCheck(session, options.check);
    case "flint fmt":
        return commandFmt(session, options.fmt);
    case "flint lock":
        return commandLock(session, options.lock);
    case "flint package":
        return packageCommand(session, options.package_);
    case "flint watch":
        return watchCommand(session, options.watch, passthrough);
    default:
        return -1;
    }
}

private int packageCommand(ref Session session, const ref PackageArgs args)
{
    import flint_tool.commands.packaging : PackageRequest, commandPackage;

    return commandPackage(session, PackageRequest(args.project, args.target, args.container,
            args.sbom, args.verify, args.locked, args.profile));
}

private int watchCommand(ref Session session, const ref WatchArgs args, string[] passthrough)
{
    import flint_tool.commands.watch : WatchMode, commandWatch;

    const mode = args.test ? WatchMode.test : args.build ? WatchMode.build : WatchMode.run;
    return commandWatch(session, args.project, mode, passthrough);
}

/// Run a knowledge command (docs, examples, generate); -1 when `name` is not one.
private int knowledgeCommand(ref Session session, string name, ref FlintArgs options)
{
    import std.array : join;
    import flint_tool.commands.generate : commandGenerate;
    import flint_tool.commands.knowledge : commandDocs, commandExamples;
    import flint_tool.commands.mcp : commandConfig, commandMcp;

    switch (name)
    {
    case "flint docs":
        return commandDocs(session, options.docs.query.join(" "), options.docs.exportDirectory, options.docs.limit);
    case "flint examples":
        return commandExamples(session, options.examples.topic.join(" "), options.examples.limit);
    case "flint generate":
        return commandGenerate(session, options.generate.kind, options.generate.name,
                options.generate.project, options.generate.plan);
    case "flint config":
        return commandConfig(session, options.config.project, options.config.profile);
    case "flint openapi":
        {
            import flint_tool.commands.openapi : commandOpenApi;

            return commandOpenApi(session, options.openapi.project, options.openapi.output,
                    options.openapi.typescript);
        }
    case "flint add":
        {
            import flint_tool.commands.add : commandAdd;

            return commandAdd(session, options.add.starters, options.add.project, options.add.plan);
        }
    case "flint mcp":
        return commandMcp(session, options.mcp.log);
    case "flint lsp":
        {
            import flint_tool.commands.lsp : commandLsp;

            return commandLsp(session);
        }
    default:
        return -1;
    }
}

/// Run a toolchain or knowledge command; -1 when `name` is not one.
private int toolingCommand(ref Session session, string name, ref FlintArgs options)
{
    import flint_tool.commands.tooling : commandDoctor, commandExplain, commandVersion;

    const knowledge = knowledgeCommand(session, name, options);
    if (knowledge >= 0)
        return knowledge;
    const api = apiCommand(session, name, options.api);
    if (api >= 0)
        return api;
    const evidence = evidenceCommand(session, name, options);
    if (evidence >= 0)
        return evidence;
    switch (name)
    {
    case "flint deps tree":
    case "flint deps why":
    case "flint deps update":
    case "flint deps vendor":
    case "flint deps audit":
        return depsCommand(session, name, options);
    case "flint doctor":
        return commandDoctor(session, options.doctor);
    case "flint version":
        return commandVersion(session, options.version_);
    case "flint explain":
        return commandExplain(session, options.explain);
    default:
        return toolchainCommand(session, name, options);
    }
}

/// Run a command that reports evidence about a build (`flint receipt`, `flint budget`); -1 when `name` is not one.
private int evidenceCommand(ref Session session, string name, ref FlintArgs options)
{
    import flint_tool.commands.budget : commandBudget;
    import flint_tool.commands.tooling : commandReceipt;

    switch (name)
    {
    case "flint receipt":
        return commandReceipt(session, options.receipt);
    case "flint budget":
        return commandBudget(session, options.budget);
    default:
        return -1;
    }
}

private int depsCommand(ref Session session, string name, ref FlintArgs options)
{
    import flint_tool.commands.deps : commandDepsAudit, commandDepsTree, commandDepsUpdate,
        commandDepsVendor, commandDepsWhy;

    switch (name)
    {
    case "flint deps tree":
        return commandDepsTree(session, options.deps.tree.project);
    case "flint deps why":
        return commandDepsWhy(session, options.deps.why.project, options.deps.why.name);
    case "flint deps update":
        return commandDepsUpdate(session, options.deps.update.project, options.deps.update.names);
    default:
        return commandDepsVendor(session, options.deps.vendor.project);
    case "flint deps audit":
        return commandDepsAudit(session, options.deps.audit.project, options.deps.audit.target);
    }
}

/// Run a `flint api` command; -1 when `name` is not one.
private int apiCommand(ref Session session, string name, ref ApiArgs args)
{
    import flint_tool.commands.api : CoverageCommand, ExtractCommand, commandApiChecklist,
        commandApiCoverage, commandApiDiff, commandApiExtract, commandApiFetch, commandApiHeaders;

    switch (name)
    {
    case "flint api fetch":
        return commandApiFetch(session, args.fetch.projects, args.fetch.cache, args.fetch.tests);
    case "flint api extract":
        const command = ExtractCommand(args.extract.source, args.extract.project, args.extract.tag,
                args.extract.output, args.extract.excludes);
        return commandApiExtract(session, command);
    case "flint api coverage":
        const coverage = CoverageCommand(args.coverage.manifests, args.coverage.mapping,
                args.coverage.repo, args.coverage.show, args.coverage.release,
                args.coverage.updateBaseline, args.coverage.baseline, args.coverage.slices);
        return commandApiCoverage(session, coverage);
    case "flint api diff":
        return commandApiDiff(session, args.diff.older, args.diff.newer);
    case "flint api checklist":
        return commandApiChecklist(session, args.checklist.slice, args.checklist.output);
    case "flint api headers":
        return commandApiHeaders(session, args.headers.paths);
    default:
        return -1;
    }
}

/// Run a toolchain or compile-server command; -1 when `name` is not one.
private int toolchainCommand(ref Session session, string name, ref FlintArgs options)
{
    import flint_tool.commands.tooling : commandDaemon, commandToolchainInspect, commandToolchainInstall;

    switch (name)
    {
    case "flint toolchain install":
        return commandToolchainInstall(session, options.toolchain.install);
    case "flint toolchain verify":
        return commandToolchainInspect(session, options.toolchain.verify, true);
    case "flint toolchain info":
        return commandToolchainInspect(session, options.toolchain.info, false);
    case "flint daemon start":
        return commandDaemon(session, "start", options.daemon.start.profile);
    case "flint daemon stop":
        return commandDaemon(session, "stop", null);
    case "flint daemon status":
        return commandDaemon(session, "status", null);
    default:
        return -1;
    }
}

private bool verbose(string commandName, const ref FlintArgs options)
{
    switch (commandName)
    {
    case "flint build":
        return options.build.verbose;
    case "flint run":
        return options.run.verbose;
    case "flint test":
        return options.test.verbose;
    case "flint check":
        return options.check.verbose;
    case "flint package":
        return options.package_.verbose;
    default:
        return false;
    }
}

private string helpPath(string commandName)
{
    return commandName.length > "flint".length ? commandName["flint ".length .. $] ~ " " : "";
}

private void printHelp(string commandName)
{
    import flint_tool.sys.posix : writeOutput;

    void delegate(scope const(char)[]) @safe sink = (scope const(char)[] text) @safe {
        writeOutput(text);
    };
    if (!printProjectHelp(commandName, sink) && !printApiHelp(commandName, sink))
        printToolingHelp(commandName, sink);
}

private bool printProjectHelp(string commandName, scope void delegate(scope const(char)[]) @safe sink)
{
    switch (commandName)
    {
    case "flint new":
        writeHelp!NewArgs(sink);
        return true;
    case "flint build":
        writeHelp!BuildArgs(sink);
        return true;
    case "flint run":
        writeHelp!RunArgs(sink);
        return true;
    case "flint test":
        writeHelp!TestArgs(sink);
        return true;
    case "flint check":
        writeHelp!CheckArgs(sink);
        return true;
    case "flint fmt":
        writeHelp!FmtArgs(sink);
        return true;
    case "flint lock":
        writeHelp!LockArgs(sink);
        return true;
    case "flint package":
        writeHelp!PackageArgs(sink);
        return true;
    default:
        return false;
    }
}

private bool printKnowledgeHelp(string commandName, scope void delegate(scope const(char)[]) @safe sink)
{
    switch (commandName)
    {
    case "flint docs":
        writeHelp!DocsArgs(sink);
        return true;
    case "flint generate":
        writeHelp!GenerateArgs(sink);
        return true;
    case "flint examples":
        writeHelp!ExamplesArgs(sink);
        return true;
    case "flint config":
        writeHelp!ConfigArgs(sink);
        return true;
    case "flint watch":
        writeHelp!WatchArgs(sink);
        return true;
    case "flint mcp":
        writeHelp!McpArgs(sink);
        return true;
    case "flint lsp":
        writeHelp!LspArgs(sink);
        return true;
    default:
        return false;
    }
}

private bool printApiHelp(string commandName, scope void delegate(scope const(char)[]) @safe sink)
{
    switch (commandName)
    {
    case "flint api":
        writeHelp!ApiArgs(sink);
        return true;
    case "flint api fetch":
        writeHelp!ApiFetchArgs(sink);
        return true;
    case "flint api extract":
        writeHelp!ApiExtractArgs(sink);
        return true;
    case "flint api coverage":
        writeHelp!ApiCoverageArgs(sink);
        return true;
    case "flint api diff":
        writeHelp!ApiDiffArgs(sink);
        return true;
    case "flint api checklist":
        writeHelp!ApiChecklistArgs(sink);
        return true;
    case "flint api headers":
        writeHelp!ApiHeadersArgs(sink);
        return true;
    default:
        return false;
    }
}

private void printToolingHelp(string commandName, scope void delegate(scope const(char)[]) @safe sink)
{
    if (printKnowledgeHelp(commandName, sink) || printEvidenceHelp(commandName, sink))
        return;
    switch (commandName)
    {
    case "flint toolchain":
        return writeHelp!ToolchainArgs(sink);
    case "flint deps":
        return writeHelp!DepsArgs(sink);
    case "flint toolchain install":
        return writeHelp!ToolchainInstallArgs(sink);
    case "flint doctor":
        return writeHelp!DoctorArgs(sink);
    case "flint daemon":
        return writeHelp!DaemonArgs(sink);
    case "flint version":
        return writeHelp!VersionArgs(sink);
    case "flint explain":
        return writeHelp!ExplainArgs(sink);
    default:
        return writeHelp!FlintArgs(sink);
    }
}

private bool printEvidenceHelp(string commandName, scope void delegate(scope const(char)[]) @safe sink)
{
    switch (commandName)
    {
    case "flint receipt":
        writeHelp!ReceiptArgs(sink);
        return true;
    case "flint budget":
        writeHelp!BudgetArgs(sink);
        return true;
    default:
        return false;
    }
}
