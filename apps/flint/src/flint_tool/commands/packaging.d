/// `flint package`: a release build for a target, verified static, staged with its config and resources, archived,
/// and optionally wrapped in a `FROM scratch` OCI image and described by SPDX and CycloneDX SBOMs (ADR-023).
module flint_tool.commands.packaging;

import flint_tool.commands.output : finish;
import flint_tool.commands.project : ProjectInfo, Target;
import flint_tool.diagnostics.report : Diagnostic, Report;
import flint_tool.engine.builder : BuildOutcome;
import flint_tool.engine.session : Session;
import flint_tool.engine.target : BuildTarget;
import flint_tool.support.archive : Entry;

@safe:

/// One file `flint package` wrote.
struct PackageOutput
{
    /// "executable", "archive", "image", "spdx", "cyclonedx" or "receipt".
    string kind;
    /// Path relative to the current directory.
    string path;
    /// SHA-256.
    string sha256;
    /// Size in bytes.
    long bytes;
}

/// `flint.package/1`, also written next to the outputs as the package receipt.
struct PackagePayload
{
    /// Schema.
    string schema = "flint.package/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// The project.
    ProjectInfo project;
    /// Target.
    string target;
    /// The C library.
    string libc;
    /// No interpreter and no shared libraries.
    bool fully_static;
    /// Shared libraries the executable needs.
    string[] needed;
    /// The build receipt of the executable.
    string build_receipt;
    /// The image reference, with --container.
    string image;
    /// The image manifest digest, with --container.
    string image_digest;
    /// Components in the SBOM.
    long components;
    /// Every output.
    PackageOutput[] outputs;
}

/// What to package.
struct PackageRequest
{
    /// Project directory.
    string project;
    /// Target name; empty for the default.
    string target;
    /// Also write an OCI image.
    bool container;
    /// Also write SBOMs.
    bool sbom;
    /// Fail on toolchain mismatches.
    bool verify;
    /// Require a current lock.
    bool locked;
}

/// `flint package`.
int commandPackage(ref Session session, PackageRequest request)
{
    import std.file : mkdirRecurse;
    import std.path : buildPath;
    import flint_tool.commands.project : TargetKind, info, locate;
    import flint_tool.engine.target : hostTarget, muslTarget, selectTarget;

    Report report;
    PackagePayload payload;
    Target project;
    if (!locate(session, request.project, project, report))
        return finish(session, report, payload);
    payload.project = info(session, project);
    if (!packageable(project.kind == TargetKind.workspace, project.manifest.type, report))
        return finish(session, report, payload);
    payload.target = request.target.length ? request.target : request.container ? muslTarget : hostTarget();
    BuildTarget target;
    if (!selectTarget(session.home, payload.target, target, report) || !containable(request, target, report))
        return finish(session, report, payload);
    payload.libc = target.libc;
    BuildOutcome outcome;
    if (!releaseBuild(session, project, request, target, outcome, report))
        return finish(session, report, payload);
    payload.build_receipt = displayed(outcome.receipt);
    if (!verifyLinkage(outcome.artifact, target, payload, report))
        return finish(session, report, payload);
    const directory = buildPath(project.root, ".flint", "package");
    mkdirRecurse(directory);
    const stem = buildPath(directory, project.manifest.name ~ "-" ~ project.manifest.version_ ~ "-" ~ target.name);
    const created = sourceDateEpoch();
    auto files = stagedFiles(project.root, outcome.artifact, project.manifest.artifactName());
    writeArchive(stem, project.manifest.name ~ "-" ~ project.manifest.version_, files, created, payload);
    if (request.sbom)
        writeSboms(session, project, outcome, target, stem, created, payload);
    if (request.container)
        writeImage(project, target, files, stem, created, payload);
    payload.outputs = [output("executable", outcome.artifact)] ~ payload.outputs;
    writeReceiptFile(stem ~ ".package.json", payload);
    payload.outputs ~= output("receipt", stem ~ ".package.json");
    foreach (ref item; payload.outputs[1 .. $])
        session.progress("Packaged", item.path);
    return finish(session, report, payload);
}

private bool packageable(bool workspace, string type, ref Report report)
{
    if (workspace)
        report.error("FLINT-E0004", "flint package packages a project, not the workspace",
                "flint package -C <project>");
    else if (type != "executable")
        report.error("FLINT-E0709", "only executable projects are packaged",
                "[project]\ntype = \"executable\"    # libraries are published as repositories");
    return report.ok;
}

private bool containable(const ref PackageRequest request, const ref BuildTarget target, ref Report report)
{
    import flint_tool.engine.target : muslTarget;

    if (!request.container || target.fullyStatic)
        return true;
    report.error("FLINT-E0710", "a FROM scratch image needs a fully static executable; " ~ target.name
            ~ " links the C library dynamically", "flint package --container --target " ~ muslTarget);
    return false;
}

/// The release profile for `target`, rebuilt from scratch, stripped.
private bool releaseBuild(ref Session session, const ref Target project, const ref PackageRequest request,
        const ref BuildTarget target, out BuildOutcome outcome, ref Report report)
{
    import std.path : buildPath;
    import flint_tool.engine.builder : BuildRequest, buildProject;
    import flint_tool.engine.target : ldcConfiguration, targetCflags, targetDflags;
    import flint_tool.support.files : writeIfChanged;

    BuildRequest build;
    build.profile = "release";
    build.verify = request.verify;
    build.locked = request.locked;
    // DUB's up-to-date check does not see a change of target, so packaging always rebuilds.
    build.force = true;
    const configuration = buildPath(project.root, ".flint", "generated", "ldc2-" ~ target.name ~ ".conf");
    if (target.cross)
    {
        writeIfChanged(configuration, ldcConfiguration(target));
        build.target = target.name;
    }
    build.targetDflags = targetDflags(target, configuration) ~ "-L--strip-all";
    build.targetCflags = targetCflags(target);
    return buildProject(session, project.manifest, project.resolution, build, outcome, report);
}

/// Shared libraries a glibc executable may need: the C library itself.
private immutable string[] glibcLibraries = [
    "libc.so.6", "libm.so.6", "libpthread.so.0", "libdl.so.2", "librt.so.1", "libgcc_s.so.1",
    "ld-linux-x86-64.so.2", "ld-linux-aarch64.so.1"
];

private bool verifyLinkage(string artifact, const ref BuildTarget target, ref PackagePayload payload, ref Report report)
{
    import std.algorithm.searching : canFind;
    import std.file : read;
    import flint_tool.support.elf : inspectElf;

    const facts = inspectElf(cast(const(ubyte)[]) read(artifact));
    payload.fully_static = facts.fullyStatic();
    payload.needed = facts.needed.dup;
    if (target.fullyStatic && !facts.fullyStatic())
    {
        const reason = "interpreter `" ~ facts.interpreter ~ "`, needs " ~ (facts.needed.length
                ? facts.needed[0] : "nothing");
        report.error("FLINT-E0711", artifact ~ " is not fully static (" ~ reason ~ ")", "flint package --verbose");
        return false;
    }
    foreach (library; facts.needed)
    {
        if (!glibcLibraries.canFind(library))
        {
            report.error("FLINT-E0711", artifact ~ " needs the shared library " ~ library
                    ~ "; packages link everything but the C library statically",
                    "declare it under [native] (static by default) or with linkage = \"bundled\"");
            return false;
        }
    }
    return true;
}

/// The executable under bin/, then the project's config/ and resources/.
private Entry[] stagedFiles(string root, string artifact, string executable)
{
    import std.file : read;
    import std.path : buildPath;
    import flint_tool.support.archive : octal644, octal755;
    import flint_tool.support.files : findFiles;

    Entry[] files = [
        Entry("bin/"), Entry("bin/" ~ executable, cast(const(ubyte)[]) read(artifact), octal755)
    ];
    foreach (directory; ["config", "resources"])
    {
        const found = findFiles(buildPath(root, directory), "**");
        if (found.length)
            files ~= Entry(directory ~ "/");
        string[] made = [directory];
        foreach (relative; found)
        {
            addParents(directory, relative, made, files);
            files ~= Entry(directory ~ "/" ~ relative, cast(const(ubyte)[]) read(buildPath(root,
                    directory, relative)), octal644);
        }
    }
    foreach (ref file; files)
    {
        if (file.path[$ - 1] == '/')
            file.mode = octal755;
    }
    return files;
}

private void addParents(string directory, string relative, ref string[] made, ref Entry[] files)
{
    import std.algorithm.searching : canFind;
    import std.path : dirName;

    const parent = dirName(relative);
    if (parent == ".")
        return;
    addParents(directory, parent, made, files);
    const path = directory ~ "/" ~ parent;
    if (!made.canFind(path))
    {
        made ~= path;
        files ~= Entry(path ~ "/");
    }
}

private void writeArchive(string stem, string top, scope const Entry[] files, long created, ref PackagePayload payload)
{
    import std.file : write;
    import flint_tool.support.archive : gzip, octal755, tarArchive;

    Entry[] prefixed = [Entry(top ~ "/", null, octal755)];
    foreach (ref file; files)
        prefixed ~= Entry(top ~ "/" ~ file.path, file.data, file.mode);
    write(stem ~ ".tar.gz", gzip(tarArchive(prefixed, created)));
    payload.outputs ~= output("archive", stem ~ ".tar.gz");
}

private void writeSboms(ref Session session, const ref Target project, const ref BuildOutcome outcome,
        const ref BuildTarget target, string stem, long created, ref PackagePayload payload)
{
    import std.file : write;
    import std.path : buildPath;
    import flint_tool.engine.oci : rfc3339;
    import flint_tool.engine.sbom : collect, renderCycloneDx, renderSpdx;
    import flint_tool.support.files : sha256File;

    string[2][] sources;
    foreach (source; outcome.native.sources)
        sources ~= [source, sha256File(buildPath(project.root, source))];
    const inventory = collect(session.home, project.manifest, project.resolution, target.name,
            sha256File(outcome.artifact), sources);
    payload.components = cast(long) inventory.components.length;
    const release = session.home.platform.release;
    write(stem ~ ".spdx.json", renderSpdx(inventory, release, rfc3339(created)));
    write(stem ~ ".cdx.json", renderCycloneDx(inventory, release, rfc3339(created)));
    payload.outputs ~= output("spdx", stem ~ ".spdx.json");
    payload.outputs ~= output("cyclonedx", stem ~ ".cdx.json");
}

private void writeImage(const ref Target project, const ref BuildTarget target, scope const Entry[] files,
        string stem, long created, ref PackagePayload payload)
{
    import std.algorithm.searching : startsWith;
    import std.file : write;
    import flint_tool.engine.oci : ImageSpec, imageArchive, rfc3339;
    import flint_tool.support.archive : octal755;

    ImageSpec spec;
    spec.name = project.manifest.name;
    spec.tag = project.manifest.version_;
    spec.architecture = target.architecture;
    spec.executable = project.manifest.artifactName();
    spec.created = created;
    spec.files = [Entry("app/", null, octal755)];
    foreach (ref file; files)
    {
        // The executable goes to /app itself, beside config/ and resources/, which it reads relative to /app.
        if (file.path == "bin/")
            continue;
        const path = file.path.startsWith("bin/") ? "app/" ~ file.path[4 .. $] : "app/" ~ file.path;
        spec.files ~= Entry(path, file.data, file.mode);
    }
    spec.labels = [
        "org.opencontainers.image.title": spec.name,
        "org.opencontainers.image.version": spec.tag,
        "org.opencontainers.image.created": rfc3339(created),
        "dev.flint.target": target.name
    ];
    if (project.manifest.license.length)
        spec.labels["org.opencontainers.image.licenses"] = project.manifest.license;
    if (project.manifest.description.length)
        spec.labels["org.opencontainers.image.description"] = project.manifest.description;
    const image = imageArchive(spec);
    write(stem ~ ".oci.tar", image.archive);
    payload.image = spec.name ~ ":" ~ spec.tag;
    payload.image_digest = image.manifestDigest;
    payload.outputs ~= output("image", stem ~ ".oci.tar");
}

private PackageOutput output(string kind, string path)
{
    import std.file : getSize;
    import flint_tool.support.files : sha256File;

    return PackageOutput(kind, displayed(path), sha256File(path), cast(long) getSize(path));
}

private string displayed(string path)
{
    import flint_tool.engine.builder : display;

    return display(path);
}

private void writeReceiptFile(string path, const ref PackagePayload payload)
{
    import flint.serde.owned : serialize;
    import flint_tool.support.files : writeIfChanged;

    auto text = serialize(payload);
    assert(text.ok, "package receipt serialization failed");
    writeIfChanged(path, text.value ~ "\n");
}

/// SOURCE_DATE_EPOCH, as reproducible builds define it, or the current time.
long sourceDateEpoch()
{
    import std.conv : ConvException, to;
    import std.datetime.systime : Clock;
    import std.process : environment;

    const fixed = environment.get("SOURCE_DATE_EPOCH", "");
    if (fixed.length)
    {
        try
            return fixed.to!long;
        catch (ConvException)
        {
        }
    }
    return Clock.currTime.toUnixTime();
}
