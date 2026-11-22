/// Toolchain and knowledge commands: toolchain, doctor, daemon, version, explain and receipt.
module flint_tool.commands.tooling;

import flint_tool.engine.session : Session;
import flint_tool.commands.args : DaemonCommon, DaemonStartArgs, DoctorArgs, ExplainArgs,
    ReceiptArgs, ToolchainCommon, ToolchainInstallArgs, VersionArgs;
import flint_tool.commands.output : finish;
import flint_tool.diagnostics.report : Diagnostic, Report, Severity, Tone, diagnostic, paint;
import flint_tool.toolchain.daemon : Server;
import flint_tool.toolchain.toolchain : Component, ForkState, Toolchain;

@safe:

// ---------------------------------------------------------------- toolchain

/// `flint.toolchain/1`.
struct ToolchainPayload
{
    /// Schema.
    string schema = "flint.toolchain/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// install, verify or info.
    string action;
    /// Toolchain directory.
    string directory;
    /// Components.
    Component[] components;
    /// Fork provenance.
    ForkState fork;
    /// Installer commands (install).
    string[][] commands;
    /// Commands were printed, not run.
    bool plan;
}

private void fill(ref ToolchainPayload payload, const ref Toolchain toolchain)
{
    payload.directory = toolchain.directory;
    payload.components = [
        toolchain.dmd, toolchain.dub, toolchain.ldc2, toolchain.dfmt, toolchain.dscanner
    ];
    payload.fork = toolchain.fork;
}

private void describeToolchain(ref Session session, const ref Toolchain toolchain)
{
    foreach (component; [
        toolchain.dmd, toolchain.dub, toolchain.ldc2, toolchain.dfmt, toolchain.dscanner
    ])
    {
        const state = !component.present ? paint("missing", session.outputPalette,
                Tone.error) : component.versionMatches ? paint(component.expected, session.outputPalette,
                Tone.success) : paint(component.reported, session.outputPalette, Tone.warning);
        session.say(component.name ~ padding(component.name, 9) ~ state ~ "  " ~ component.path);
        if (component.sha256.length)
            session.say("         sha256 " ~ component.sha256);
    }
    session.say("fork     " ~ (toolchain.fork.installed
            ? "installed" : "absent") ~ ", receipt " ~ (toolchain.fork.receiptPresent
            ? (toolchain.fork.verified ? paint("verified", session.outputPalette,
            Tone.success) : paint("mismatch", session.outputPalette, Tone.warning)) : paint("missing",
            session.outputPalette, Tone.warning)));
    session.say("         dmd patch " ~ toolchain.fork.dmdPatch);
    session.say("         dub patch " ~ toolchain.fork.dubPatch);
}

/// Spaces that align a column after `text`, always at least one.
private string padding(string text, size_t width)
{
    string spaces = " ";
    foreach (_; text.length + 1 .. width)
        spaces ~= " ";
    return spaces;
}

/// `flint toolchain info` and `verify`.
int commandToolchainInspect(ref Session session, ToolchainCommon args, bool verify)
{
    import flint_tool.toolchain.toolchain : inspect, verifyToolchain;

    Report report;
    ToolchainPayload payload;
    payload.action = verify ? "verify" : "info";
    const toolchain = inspect(session.home, null, true, args.directory);
    fill(payload, toolchain);
    if (verify)
        verifyToolchain(toolchain, ["dmd", "dub", "ldc2", "dfmt", "dscanner"], Severity.error, report);
    if (!session.json)
    {
        describeToolchain(session, toolchain);
        if (verify && report.ok)
            session.progress("Verified", "toolchain matches policy/toolchains.json and toolchain/*.patch");
    }
    return finish(session, report, payload);
}

/// `flint toolchain install`.
int commandToolchainInstall(ref Session session, ToolchainInstallArgs args)
{
    import std.array : join;
    import flint_tool.toolchain.toolchain : installCommands, inspect, receiptName,
        toolchainDirectory, verifyToolchain;

    Report report;
    ToolchainPayload payload;
    payload.action = "install";
    payload.plan = args.plan;
    const directory = toolchainDirectory(session.home, args.directory);
    payload.directory = directory;
    payload.commands = installCommands(session.home, directory, !args.noPgo, args.linker, args.sanitizers, args.musl);
    if (args.plan)
    {
        foreach (command; payload.commands)
            session.say(command.join(" "));
        return finish(session, report, payload);
    }
    // The installer replaces dmd in place; compile servers running it would make the file busy.
    import std.conv : to;
    import flint_tool.check.structural : realPath;
    import flint_tool.toolchain.daemon : stopServers;

    const stopped = stopServers(3000, realPath(directory) ~ "/");
    if (stopped.length)
        session.progress("Stopped",
                stopped.length.to!string ~ " compile server(s) running the toolchain being replaced");
    string[] outputs;
    foreach (index, command; payload.commands)
    {
        string output;
        if (!runInstaller(session, directory, command, output, report))
            return finish(session, report, payload);
        outputs ~= output;
        // The receipt covers DMD, DUB and LDC; write it as soon as both are installed.
        if (index == 1 && !writeToolchainReceipt(session, directory, outputs, report))
            return finish(session, report, payload);
    }
    const toolchain = inspect(session.home, null, true, directory);
    fill(payload, toolchain);
    verifyToolchain(toolchain, ["dmd", "dub", "ldc2"], Severity.error, report);
    if (report.ok)
        session.progress("Installed", directory ~ " (receipt " ~ receiptName ~ ")");
    return finish(session, report, payload);
}

/// Run one installer command with the toolchain being installed first on PATH.
private bool runInstaller(ref Session session, string directory, string[] command, out string output, ref Report report)
{
    import std.array : join;
    import std.path : buildPath;
    import std.process : environment;
    import flint.os : EnvVar;
    import flint_tool.support.process : Launch, streamed;
    import flint_tool.sys.posix : writeError;

    session.progress("Installing", command.join(" "));
    Launch launch;
    launch.directory = session.home.root;
    import flint_tool.toolchain.host : dmdBin, ldcBin;

    const ldc = session.home.versions["ldc"];
    const bins = buildPath(directory, dmdBin(ldc)) ~ ":" ~ buildPath(directory,
            "bin") ~ ":" ~ buildPath(directory, ldcBin(ldc));
    launch.environment = [EnvVar("PATH", bins ~ ":" ~ environment.get("PATH", "/usr/bin:/bin"))];
    const json = session.json;
    string collected;
    const outcome = streamed(command, launch, (scope const(char)[] text) @safe {
        collected ~= text;
        if (!json)
            writeError(text);
    }, (scope const(char)[] text) @safe {
        if (!json)
            writeError(text);
    });
    output = collected;
    if (outcome.ok)
        return true;
    report.error("FLINT-E0814", command.join(" ") ~ " failed" ~ (outcome.failure.length
            ? ": " ~ outcome.failure : ""), "fix the installer error above and rerun the install");
    return false;
}

private bool writeToolchainReceipt(ref Session session, string directory, scope const(string)[] outputs,
        ref Report report)
{
    import std.path : buildPath;
    import flint.serde.owned : serialize;
    import flint_tool.support.files : writeIfChanged;
    import flint_tool.toolchain.toolchain : ToolchainReceipt, composeReceipt, receiptName;

    ToolchainReceipt receipt;
    if (!composeReceipt(session.home, directory, outputs[0], outputs[1], receipt, report))
        return false;
    writeIfChanged(buildPath(directory, receiptName), serialize(receipt).value ~ "\n");
    return true;
}

// ---------------------------------------------------------------- doctor

/// One doctor finding.
struct DoctorCheck
{
    /// What was checked.
    string name;
    /// "ok", "warning" or "error".
    string status;
    /// Plain explanation.
    string detail;
}

/// `flint.doctor/1`.
struct DoctorPayload
{
    /// Schema.
    string schema = "flint.doctor/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// Findings, in order.
    DoctorCheck[] checks;
}

/// `flint doctor`.
int commandDoctor(ref Session session, DoctorArgs args)
{
    import std.conv : to;

    Doctor doctor;
    doctor.add("installation", "ok",
            session.home.root ~ " (platform " ~ session.home.platform.flint ~ ", release "
            ~ session.home.platform.release ~ ")");
    doctor.add("policy", "ok", "packages.json (" ~ session.home.packages.length.to!string
            ~ " packages), safety-policy.json, toolchains.json, profiles.toml, platform.toml");
    doctor.toolchain(session);
    doctor.environmentSwitches();
    doctor.compileServer();
    doctor.native(session);
    doctor.peers(session);
    doctor.project(session, args.project);
    if (!session.json)
    {
        foreach (check; doctor.payload.checks)
        {
            const tone = check.status == "ok" ? Tone.success : check.status == "warning" ? Tone.warning : Tone.error;
            const label = check.status == "ok" ? "ok  " : check.status == "warning" ? "warn" : "FAIL";
            session.say(paint(label, session.outputPalette,
                    tone) ~ "  " ~ check.name ~ padding(check.name, 20) ~ check.detail);
        }
    }
    return finish(session, doctor.report, doctor.payload);
}

private struct Doctor
{
    DoctorPayload payload;
    Report report;

    void add(string name, string status, string detail)
    {
        payload.checks ~= DoctorCheck(name, status, detail);
    }

    void toolchain(ref Session session)
    {
        import std.path : dirName;
        import flint_tool.support.process : which;
        import flint_tool.toolchain.toolchain : inspect, verifyToolchain;

        const found = inspect(session.home, null, false);
        Report problems;
        verifyToolchain(found, ["dmd", "dub", "ldc2", "dfmt", "dscanner"], Severity.error, problems);
        foreach (component; [found.dmd, found.dub, found.ldc2, found.dfmt, found.dscanner])
            add(component.name, component.present && component.versionMatches ? "ok" : "error",
                    component.present ? component.reported ~ " at " ~ component.path : "missing: " ~ component.path);
        add("fork", found.fork.verified ? "ok" : found.fork.installed ? "warning" : "error", forkDetail(found.fork));
        foreach (item; problems.items)
        {
            // Missing or wrong components stop builds; an unverified fork only makes them non-canonical.
            if (item.code == "FLINT-E0804" || item.code == "FLINT-E0805" || item.code == "FLINT-E0806")
                item.severity = "warning";
            report.add(item);
        }
        foreach (name; ["dmd", "dub", "ldc2"])
        {
            const onPath = which(name);
            const pinned = found.component(name).path;
            if (onPath.length == 0 || onPath == pinned)
                continue;
            add("PATH " ~ name, "warning", "PATH selects " ~ onPath ~ "; flint uses " ~ pinned);
            const fix = "export PATH=\"" ~ dirName(pinned) ~ ":$PATH\"";
            report.add(diagnostic("FLINT-E0812", Severity.warning,
                    "PATH selects " ~ onPath ~ " instead of " ~ pinned, fix));
        }
    }

    void environmentSwitches()
    {
        import std.array : join;
        import std.process : environment;

        string[] overrides;
        foreach (name; ["DFLAGS", "FLINT_DMD_SERVER", "FLINT_DUB_PIPELINE", "FLINT_DMD_DIRECT_LINK"])
        {
            const value = environment.get(name, null);
            if (value !is null && (name == "DFLAGS" || value == "0"))
                overrides ~= name ~ "=" ~ value;
        }
        if (overrides.length == 0)
            return add("environment", "ok", "no DFLAGS or toolchain switches set");
        add("environment", "warning", overrides.join(" "));
        report.add(diagnostic("FLINT-E0811", Severity.warning,
                overrides.join(" ") ~ " changes builds outside flint", "unset " ~ overrides.join(" ")));
    }

    void compileServer()
    {
        import std.conv : to;
        import std.process : environment;
        import flint_tool.toolchain.daemon : maximumSocketPath, servers, socketDirectory;

        size_t alive;
        foreach (ref server; servers())
            alive += server.alive;
        const disabled = environment.get("FLINT_DMD_SERVER", "") == "0";
        const tooLong = socketDirectory().length + "/0123456789abcdef.sock".length >= maximumSocketPath;
        string detail = alive.to!string ~ " running in " ~ socketDirectory();
        if (disabled)
            detail ~= " (disabled by FLINT_DMD_SERVER=0)";
        if (tooLong)
        {
            detail ~= " (path too long for a Unix socket: DMD compiles without the server)";
            report.add(diagnostic("FLINT-E0810", Severity.warning,
                    "the compile server socket directory " ~ socketDirectory() ~ " is too long for a Unix socket path",
                    "use a shorter XDG_RUNTIME_DIR"));
        }
        add("compile server", disabled || tooLong ? "warning" : "ok", detail);
    }

    void native(ref Session session)
    {
        import flint_tool.engine.receipt : nativeIdentity;
        import flint_tool.support.process : which;

        const found = nativeIdentity(session.home.root);
        if (found.present)
            add("native providers", "ok", "install receipt for " ~ found.target);
        else
        {
            add("native providers", "warning", "no install receipt under .native/install/" ~ found.target
                    ~ ": packages linking C providers (http, web, sql, style, ...) cannot link; pure-D packages build");
            report.add(diagnostic("FLINT-E0808", Severity.warning,
                    "native providers are not installed for " ~ found.target,
                    "python3 tools/native_build.py --profile ci --phase build --emit-dub --target " ~ found.target));
        }
        const git = which("git");
        add("git", git.length ? "ok" : "warning", git.length ? git : "missing: receipts cannot name the source commit");
        if (!git.length)
            report.add(diagnostic("FLINT-E0813", Severity.warning, "git is not on PATH", "install git"));
    }

    void peers(ref Session session)
    {
        import std.algorithm.sorting : sort;
        import flint_tool.engine.peers : PeerTable, binaryPath, loadPeers;
        import flint_tool.toolchain.toolchain : toolchainDirectory;

        PeerTable table;
        if (!loadPeers(session.home, table, report))
            return add("fixture peers", "error", "policy/test-peers.toml is invalid");
        auto names = table.binaries.keys;
        sort(names);
        foreach (name; names)
        {
            string why;
            const path = binaryPath(session.home, toolchainDirectory(session.home), table.binaries[name], why);
            add("peer binary " ~ name, path.length ? "ok" : "warning", path.length ? path : why);
        }
    }

    void project(ref Session session, string option)
    {
        import flint_tool.commands.project : Target, locate;

        Target target;
        Report projectReport;
        if (locate(session, option, target, projectReport))
            add("project", "ok", target.root ~ (target.manifest.name.length
                    ? " (" ~ target.manifest.name ~ ")" : " (workspace)"));
        else if (option.length)
        {
            add("project", "error", projectReport.items.length ? projectReport.items[0].message : option);
            report.merge(projectReport);
        }
        else
            add("project", "ok", "not inside a project");
    }
}

private string forkDetail(const ref ForkState fork)
{
    if (fork.verified)
        return "receipt verified against toolchain/*.patch";
    if (!fork.installed)
        return "not installed";
    return "installed, but " ~ (fork.receiptPresent ? "its receipt does not match" : "without a receipt")
        ~ ": builds are non-canonical until `flint toolchain install` writes one";
}

// ---------------------------------------------------------------- daemon

/// `flint.daemon/1`.
struct DaemonPayload
{
    /// Schema.
    string schema = "flint.daemon/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// start, stop or status.
    string action;
    /// Socket directory.
    string directory;
    /// Servers after the action (stop: the servers stopped).
    Server[] servers;
}

/// `flint daemon status|start|stop`.
int commandDaemon(ref Session session, string action, string profile)
{
    import std.array : join;
    import std.conv : to;
    import flint_tool.home.policy : ProfileSpec;
    import flint_tool.toolchain.daemon : servers, socketDirectory, startServer, stopServers;
    import flint_tool.toolchain.toolchain : inspect;

    Report report;
    DaemonPayload payload;
    payload.action = action;
    payload.directory = socketDirectory();
    switch (action)
    {
    case "start":
        ProfileSpec spec;
        if (!session.home.profile(profile, spec))
        {
            report.error("FLINT-E0003", "unknown profile `" ~ profile ~ "`", "flint daemon start --profile dev");
            break;
        }
        if (!spec.compile_server || spec.compiler != "dmd")
        {
            report.error("FLINT-E0003", "the " ~ profile ~ " profile does not use the DMD compile server",
                    "flint daemon start --profile dev");
            break;
        }
        import flint_tool.toolchain.host : dmdForkHost;

        static if (!dmdForkHost)
        {
            report.error("FLINT-E0810", "the compile server belongs to the Linux DMD fork; this host fills the "
                    ~ "DMD role with LDC's ldmd2, which has none (ADR-024)", "build without flint daemon");
            break;
        }
        const toolchain = inspect(session.home, ["dmd"], false);
        if (!toolchain.dmd.present)
        {
            report.error("FLINT-E0802", "dmd is not installed at " ~ toolchain.dmd.path, "flint toolchain install");
            break;
        }
        Server started;
        string failure;
        if (!startServer(toolchain.dmd.path, spec.dflags, started, failure))
            report.error("FLINT-E0810", failure, "check " ~ payload.directory ~ "/*.sock.log; unset FLINT_DMD_SERVER");
        else
            session.progress("Started", "compile server " ~ started.pid.to!string ~ " for " ~ spec.dflags.join(" "));
        payload.servers = servers();
        break;
    case "stop":
        payload.servers = stopServers();
        session.progress("Stopped",
                payload.servers.length.to!string ~ " compile server" ~ (payload.servers.length == 1 ? "" : "s"));
        break;
    default:
        payload.servers = servers();
        if (!session.json)
        {
            if (payload.servers.length == 0)
                session.say("no compile servers in " ~ payload.directory);
            foreach (server; payload.servers)
                session.say((server.alive ? paint("running", session.outputPalette,
                        Tone.success) : paint("stale  ", session.outputPalette, Tone.warning)) ~ "  pid "
                        ~ server.pid.to!string ~ "  " ~ server.flags.join(" ") ~ "  " ~ server.socket);
        }
    }
    return finish(session, report, payload);
}

// ---------------------------------------------------------------- version

/// Tool identity in `flint.version/1`.
struct ToolInfo
{
    /// "flint".
    string name = "flint";
    /// Flint release.
    string release;
    /// Platform version.
    string platform;
    /// Executable path.
    string executable;
    /// Its SHA-256.
    string sha256;
    /// Installation root.
    string home;
}

/// Self-verification in `flint.version/1`.
struct SelfReceipt
{
    /// Receipt path.
    string path;
    /// A receipt exists next to the executable.
    bool present;
    /// The executable matches its receipt.
    bool verified;
    /// The receipt is canonical.
    bool canonical;
}

/// `flint.version/1`.
struct VersionPayload
{
    /// Schema.
    string schema = "flint.version/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// This executable.
    ToolInfo tool;
    /// Pinned toolchain.
    Component[] toolchain;
    /// The installation's source identity.
    string commit;
    /// Uncommitted changes in the installation.
    bool dirty;
    /// The executable's own receipt.
    SelfReceipt receipt;
}

/// `flint version` and `flint --version`.
int commandVersion(ref Session session, VersionArgs args)
{
    import std.file : exists;
    import flint_tool.engine.receipt : ComponentRecord, Receipt, readReceipt, receiptPath,
        sourceIdentity, verifyArtifact;
    import flint_tool.toolchain.toolchain : inspect;

    Report report;
    VersionPayload payload;
    payload.tool.release = session.home.platform.release;
    payload.tool.platform = session.home.platform.flint;
    payload.tool.executable = session.executable;
    payload.tool.sha256 = session.toolSha();
    payload.tool.home = session.home.root;
    const toolchain = inspect(session.home, ["dmd", "dub", "ldc2"], args.verify);
    payload.toolchain = [toolchain.dmd, toolchain.dub, toolchain.ldc2];
    const source = sourceIdentity(session.home.root);
    payload.commit = source.commit;
    payload.dirty = source.dirty;
    payload.receipt.path = receiptPath(session.executable);
    payload.receipt.present = exists(payload.receipt.path);
    if (args.verify || payload.receipt.present)
    {
        Receipt receipt;
        Report receiptReport;
        if (readReceipt(payload.receipt.path, receipt, receiptReport))
        {
            ComponentRecord[] current;
            if (args.verify)
            {
                foreach (component; payload.toolchain)
                    current ~= ComponentRecord(component.name, component.expected,
                            component.reported, component.sha256);
            }
            payload.receipt.verified = verifyArtifact(session.executable, receipt, current, false, receiptReport);
            payload.receipt.canonical = receipt.canonical;
        }
        if (args.verify)
            report.merge(receiptReport);
    }
    if (!session.json)
    {
        session.say("flint " ~ payload.tool.release ~ " (platform " ~ payload.tool.platform ~ ")");
        session.say("  executable " ~ payload.tool.executable);
        session.say("  sha256     " ~ payload.tool.sha256);
        session.say("  home       " ~ payload.tool.home ~ (payload.commit.length
                ? " @ " ~ payload.commit ~ (payload.dirty ? " (dirty)" : "") : ""));
        foreach (component; payload.toolchain)
            session.say("  " ~ component.name ~ padding(component.name, 11) ~ (component.present
                    ? component.reported : "missing"));
        session.say("  receipt    " ~ (payload.receipt.present ? (payload.receipt.verified
                ? "verified" : "present") ~ (payload.receipt.canonical ? ", canonical" : ", non-canonical") : "none")
                ~ "  " ~ payload.receipt.path);
    }
    return finish(session, report, payload);
}

// ---------------------------------------------------------------- explain

/// One code in `flint.explain/1`.
struct CodeEntry
{
    /// Code.
    string code;
    /// Exit code the error maps to.
    int exit_code_class;
    /// Title.
    string title;
    /// Explanation.
    string explanation;
    /// Example or fix.
    string example;
}

/// `flint.explain/1`.
struct ExplainPayload
{
    /// Schema.
    string schema = "flint.explain/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// The explained codes.
    CodeEntry[] codes;
}

/// `flint explain <code>` and `flint explain --list`.
int commandExplain(ref Session session, ExplainArgs args)
{
    import std.conv : to;
    import flint_tool.diagnostics.catalog : catalog, lookup;

    Report report;
    ExplainPayload payload;
    if (args.list)
    {
        foreach (ref entry; catalog)
        {
            payload.codes ~= CodeEntry(entry.code, cast(int) entry.exit, entry.title,
                    entry.explanation, entry.example);
            session.say(entry.code ~ "  " ~ entry.title);
        }
        return finish(session, report, payload);
    }
    if (args.code.length == 0)
    {
        report.error("FLINT-E0002", "flint explain needs a code",
                "flint explain FLINT-E0401, or flint explain --list");
        return finish(session, report, payload);
    }
    const entry = lookup(args.code);
    if (entry is null)
    {
        report.error("FLINT-E0005", "`" ~ args.code ~ "` is not a Flint diagnostic code", "flint explain --list");
        return finish(session, report, payload);
    }
    payload.codes = [
        CodeEntry(entry.code, cast(int) entry.exit, entry.title, entry.explanation, entry.example)
    ];
    session.say(paint(entry.code, session.outputPalette, Tone.code) ~ ": " ~ paint(entry.title,
            session.outputPalette, Tone.strong) ~ "\n\n" ~ entry.explanation ~ "\n\nExample:\n" ~ indent(
            entry.example) ~ "\nExit code " ~ (cast(int) entry.exit).to!string ~ " when raised as an error.");
    return finish(session, report, payload);
}

private string indent(string text)
{
    import std.string : lineSplitter;

    string result;
    foreach (line; text.lineSplitter)
        result ~= "    " ~ line ~ "\n";
    return result;
}

// ---------------------------------------------------------------- receipt

/// `flint.receipt/1` verification report.
struct ReceiptPayload
{
    /// Schema.
    string schema = "flint.receipt/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// Artifact.
    string artifact;
    /// Receipt path.
    string receipt;
    /// The receipt's canonical verdict.
    bool canonical;
    /// Why not canonical.
    string[] non_canonical_reasons;
    /// Profile.
    string profile;
    /// Source commit.
    string commit;
}

/// `flint receipt <artifact>`.
int commandReceipt(ref Session session, ReceiptArgs args)
{
    import flint_tool.engine.receipt : ComponentRecord, Receipt, readReceipt, receiptPath, verifyArtifact;
    import flint_tool.toolchain.toolchain : inspect;

    Report report;
    ReceiptPayload payload;
    if (args.artifact.length == 0)
    {
        report.error("FLINT-E0002", "flint receipt needs an artifact path", "flint receipt .flint/build/dev/shop");
        return finish(session, report, payload);
    }
    payload.artifact = args.artifact;
    payload.receipt = receiptPath(args.artifact);
    Receipt receipt;
    if (!readReceipt(payload.receipt, receipt, report))
        return finish(session, report, payload);
    payload.canonical = receipt.canonical;
    payload.non_canonical_reasons = receipt.non_canonical_reasons;
    payload.profile = receipt.profile.name;
    payload.commit = receipt.source.commit;
    string[] names;
    foreach (ref component; receipt.toolchain.components)
        names ~= component.name;
    const toolchain = inspect(session.home, names, true);
    ComponentRecord[] current;
    foreach (name; names)
    {
        const component = toolchain.component(name);
        current ~= ComponentRecord(name, component.expected, component.reported, component.sha256);
    }
    if (verifyArtifact(args.artifact, receipt, current, args.canonical, report))
        session.progress("Verified", args.artifact ~ " (" ~ receipt.profile.name ~ (receipt.canonical
                ? ", canonical)" : ", non-canonical)"));
    return finish(session, report, payload);
}
