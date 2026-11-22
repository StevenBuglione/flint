/// The command-line schema, bound by flint.cli.
module flint_tool.commands.args;

import flint.cli : Arg, Command, Option, Subcommand;

@safe:

/// `flint new`.
@Command("flint new", "Create a project that builds, runs and tests")
struct NewArgs
{
    /// Project name.
    @Arg(0, "Project name: lower-case letters, digits and hyphens") string name;
    /// Starters to scaffold.
    @Option("starter", 's', "Comma-separated starters whose core packages to add (web,data,cli,...)") string starter;
    /// Target directory.
    @Option("path", 0, "Directory to create (default: ./<name>)") string path;
    /// Project type.
    @Option("type", 't', "executable or library") string type = "executable";
    /// Print the files without writing them.
    @Option("plan", 0, "Print the files that would be written, without writing") bool plan;
    /// JSON output.
    @Option("json", 0, "Emit flint.new/1 JSON on stdout") bool json;
}

/// `flint build`.
@Command("flint build", "Build the project, or workspace packages, with a canonical profile")
struct BuildArgs
{
    /// Workspace packages.
    @Arg(0, "Workspace packages to build (default: all); ignored in a project") string[] packages;
    /// Profile.
    @Option("profile", 'p', "dev, release, size or sanitize") string profile = "dev";
    /// Compiler override.
    @Option("compiler", 'c', "Override the profile's compiler (dmd or ldc2); non-canonical") string compiler;
    /// Extra compiler flags.
    @Option("dflags", 0, "Add a compiler flag on top of the profile (repeatable); non-canonical") string[] dflags;
    /// Extra linker flags.
    @Option("lflags", 0, "Add a linker flag on top of the profile (repeatable); non-canonical") string[] lflags;
    /// Fail on toolchain mismatches.
    @Option("verify", 0, "Turn toolchain mismatches into errors") bool verify;
    /// Require a current lock.
    @Option("locked", 0, "Fail when flint.lock is missing instead of writing it") bool locked;
    /// Rebuild everything.
    @Option("force", 'f', "Rebuild even when up to date") bool force;
    /// Project directory.
    @Option("project", 'C', "Run in this project or workspace directory") string project;
    /// Stream tool output.
    @Option("verbose", 'v', "Stream DUB and compiler output") bool verbose;
    /// JSON output.
    @Option("json", 0, "Emit flint.build/1 JSON on stdout") bool json;
}

/// `flint run`.
@Command("flint run", "Build if needed, then run the executable; arguments after -- go to the program")
struct RunArgs
{
    /// Profile.
    @Option("profile", 'p', "dev, release or size") string profile = "dev";
    /// Extra compiler flags.
    @Option("dflags", 0, "Add a compiler flag (repeatable); non-canonical") string[] dflags;
    /// Fail on toolchain mismatches.
    @Option("verify", 0, "Turn toolchain mismatches into errors") bool verify;
    /// Require a current lock.
    @Option("locked", 0, "Fail when flint.lock is missing") bool locked;
    /// Project directory.
    @Option("project", 'C', "Run in this project directory") string project;
    /// Stream tool output.
    @Option("verbose", 'v', "Stream DUB and compiler output") bool verbose;
    /// JSON output.
    @Option("json", 0, "Capture the program's output in flint.run/1 JSON") bool json;
}

/// `flint test`.
@Command("flint test", "Run unittests with the canonical flags")
struct TestArgs
{
    /// Workspace packages.
    @Arg(0, "Workspace packages to test (default: all); ignored in a project") string[] packages;
    /// Compilers.
    @Option("compiler", 'c', "dmd, ldc (ldc2) or both (default: the test profile's compiler)") string compiler;
    /// Fail on toolchain mismatches.
    @Option("verify", 0, "Turn toolchain mismatches into errors") bool verify;
    /// Require a current lock.
    @Option("locked", 0, "Fail when flint.lock is missing") bool locked;
    /// Rebuild everything.
    @Option("force", 'f', "Rebuild even when up to date") bool force;
    /// ASan and UBSan.
    @Option("sanitize", 0, "Build with ASan and UBSan (LDC, the sanitize profile; embedded C included)") bool sanitize;
    /// Live scenarios.
    @Option("scenarios", 0, "Also run declared live scenarios (mq: Kafka, JetStream)") bool scenarios;
    /// Project directory.
    @Option("project", 'C', "Run in this project or workspace directory") string project;
    /// Stream tool output.
    @Option("verbose", 'v', "Stream DUB, compiler and test output") bool verbose;
    /// JSON output.
    @Option("json", 0, "Emit flint.test/1 JSON on stdout") bool json;
}

/// `flint check`.
@Command("flint check", "Run every layout, safety, format and lint check, as CI does")
struct CheckArgs
{
    /// Restrict to one gate.
    @Option("gate", 'g', "Run only this gate: structural (the workspace's tools/gates.py gate)") string gate;
    /// Workspace packages for the structural gate.
    @Option("package", 0, "Restrict the structural gate to this workspace package (repeatable)") string[] packages;
    /// Project directory.
    @Option("project", 'C', "Run in this project or workspace directory") string project;
    /// Show more detail.
    @Option("verbose", 'v', "Show more detail") bool verbose;
    /// JSON output.
    @Option("json", 0, "Emit flint.check/1 JSON on stdout") bool json;
}

/// `flint fmt`.
@Command("flint fmt", "Format D sources with the pinned dfmt")
struct FmtArgs
{
    /// Report only.
    @Option("check", 0, "Report unformatted files without rewriting them") bool check;
    /// Project directory.
    @Option("project", 'C', "Run in this project or workspace directory") string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.fmt/1 JSON on stdout") bool json;
}

/// `flint lock`.
@Command("flint lock", "Write flint.lock, or verify it with --check")
struct LockArgs
{
    /// Verify only.
    @Option("check", 0, "Verify flint.lock without writing it") bool check;
    /// Project directory.
    @Option("project", 'C', "Run in this project directory") string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.lock/1 JSON on stdout") bool json;
}

/// Options every deps subcommand takes.
struct DepsCommon
{
    /// Project directory.
    @Option("project", 'C', "Run in this project directory") string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.deps/1 JSON on stdout") bool json;
}

/// `flint deps why`.
struct DepsWhyArgs
{
    /// Package.
    @Arg(0, "Package to explain, such as github.com/acme/money or flint:log") string name;
    /// Project directory.
    @Option("project", 'C', "Run in this project directory") string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.deps/1 JSON on stdout") bool json;
}

/// `flint deps update`.
struct DepsUpdateArgs
{
    /// Packages.
    @Arg(0, "Repository-path dependencies to update (default: all)") string[] names;
    /// Project directory.
    @Option("project", 'C', "Run in this project directory") string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.deps/1 JSON on stdout") bool json;
}

/// `flint package`.
@Command("flint package", "Build a release executable for a target and package it, static by default")
struct PackageArgs
{
    /// Target.
    @Option("target", 't', "linux-x86_64-glibc or linux-x86_64-musl (default: the host; musl with --container)")
    string target;
    /// OCI image.
    @Option("container", 0, "Also write a FROM scratch OCI image around the static musl executable") bool container;
    /// SBOMs.
    @Option("sbom", 0, "Also write SPDX 2.3 and CycloneDX 1.6 SBOMs") bool sbom;
    /// Fail on toolchain mismatches.
    @Option("verify", 0, "Turn toolchain mismatches into errors") bool verify;
    /// Require a current lock.
    @Option("locked", 0, "Fail when flint.lock is missing instead of writing it") bool locked;
    /// Project directory.
    @Option("project", 'C', "Package this project directory") string project;
    /// Stream tool output.
    @Option("verbose", 'v', "Stream DUB and compiler output") bool verbose;
    /// JSON output.
    @Option("json", 0, "Emit flint.package/1 JSON on stdout") bool json;
}

/// `flint deps audit`.
struct DepsAuditArgs
{
    /// Target.
    @Option("target", 't', "Audit the executable for this target (default: the host)") string target;
    /// Project directory.
    @Option("project", 'C', "Run in this project directory") string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.deps/1 JSON on stdout") bool json;
}

/// `flint deps`.
@Command("flint deps", "Inspect and change the dependency graph")
struct DepsArgs
{
    /// tree.
    @Subcommand("tree", "Print the resolved dependency graph") DepsCommon tree;
    /// why.
    @Subcommand("why", "Show why a package is in the graph") DepsWhyArgs why;
    /// update.
    @Subcommand("update", "Raise repository-path dependencies to their latest release") DepsUpdateArgs update;
    /// vendor.
    @Subcommand("vendor", "Copy repository-path modules into vendor/ for offline builds") DepsCommon vendor;
    /// audit.
    @Subcommand("audit", "Verify hashes and list licences and LGPL/AGPL obligations") DepsAuditArgs audit;
}

/// Options every toolchain subcommand takes.
struct ToolchainCommon
{
    /// Toolchain directory.
    @Option("toolchain-dir", 0, "Toolchain directory (default: <flint>/.tools)") string directory;
    /// JSON output.
    @Option("json", 0, "Emit flint.toolchain/1 JSON on stdout") bool json;
}

/// `flint toolchain install`.
@Command("flint toolchain install", "Install the pinned toolchain and write its receipt")
struct ToolchainInstallArgs
{
    /// Toolchain directory.
    @Option("toolchain-dir", 0, "Install into this directory (default: <flint>/.tools)") string directory;
    /// Print the commands only.
    @Option("plan", 0, "Print the installer commands without running them") bool plan;
    /// Skip PGO.
    @Option("no-pgo", 0, "Build the DMD fork without profile-guided optimisation") bool noPgo;
    /// Linker.
    @Option("dmd-linker", 0, "Configure DMD to link with this installed ld.lld or mold") string linker;
    /// Sanitizer runtime.
    @Option("sanitizers", 0, "Also build the LDC runtime flint test --sanitize links") bool sanitizers;
    /// musl.
    @Option("musl", 0, "Also install what flint package --target linux-x86_64-musl needs") bool musl;
    /// JSON output.
    @Option("json", 0, "Emit flint.toolchain/1 JSON on stdout") bool json;
}

/// `flint toolchain`.
@Command("flint toolchain", "Install, verify or describe the pinned toolchain")
struct ToolchainArgs
{
    /// install.
    @Subcommand("install", "Install the pinned toolchain and write its receipt") ToolchainInstallArgs install;
    /// verify.
    @Subcommand("verify", "Check the toolchain against policy and the fork patches") ToolchainCommon verify;
    /// info.
    @Subcommand("info", "Describe the installed toolchain") ToolchainCommon info;
}

/// `flint doctor`.
@Command("flint doctor", "Explain environment problems that would make a build non-canonical")
struct DoctorArgs
{
    /// Project directory.
    @Option("project", 'C', "Also check this project or workspace") string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.doctor/1 JSON on stdout") bool json;
}

/// Options of `flint daemon start`.
struct DaemonStartArgs
{
    /// Profile whose flags key the server.
    @Option("profile", 'p', "Profile whose compiler flags the server is keyed by") string profile = "dev";
    /// JSON output.
    @Option("json", 0, "Emit flint.daemon/1 JSON on stdout") bool json;
}

/// Options of `flint daemon stop` and `status`.
struct DaemonCommon
{
    /// JSON output.
    @Option("json", 0, "Emit flint.daemon/1 JSON on stdout") bool json;
}

/// `flint daemon`.
@Command("flint daemon", "Manage the DMD compile server")
struct DaemonArgs
{
    /// start.
    @Subcommand("start", "Start the compile server for a profile's flags") DaemonStartArgs start;
    /// stop.
    @Subcommand("stop", "Stop every compile server of this user") DaemonCommon stop;
    /// status.
    @Subcommand("status", "List compile servers") DaemonCommon status;
}

/// `flint version`.
@Command("flint version", "Print the tool, toolchain and source identities")
struct VersionArgs
{
    /// Verify this executable against its receipt.
    @Option("verify", 0, "Verify this flint executable against the receipt next to it") bool verify;
    /// JSON output.
    @Option("json", 0, "Emit flint.version/1 JSON on stdout") bool json;
}

/// `flint explain`.
@Command("flint explain", "Explain a diagnostic code, with a correct example")
struct ExplainArgs
{
    /// Code.
    @Arg(0, "Diagnostic code, such as FLINT-E0401") string code;
    /// List all codes.
    @Option("list", 'l', "List every code") bool list;
    /// JSON output.
    @Option("json", 0, "Emit flint.explain/1 JSON on stdout") bool json;
}

/// `flint receipt`.
@Command("flint receipt", "Verify an artifact against its build receipt")
struct ReceiptArgs
{
    /// Artifact.
    @Arg(0, "Artifact path; its receipt is <artifact>.receipt.json") string artifact;
    /// Refuse non-canonical receipts.
    @Option("canonical", 0, "Refuse artifacts whose receipt is non-canonical") bool canonical;
    /// JSON output.
    @Option("json", 0, "Emit flint.receipt/1 JSON on stdout") bool json;
}

/// The root command.
@Command("flint", "One tool to create, build, run, test and check Flint projects with the pinned toolchain.", "0.7.0")
struct FlintArgs
{
    /// new.
    @Subcommand("new", "Create a project that builds, runs and tests") NewArgs create;
    /// build.
    @Subcommand("build", "Build with a canonical profile and write a receipt") BuildArgs build;
    /// run.
    @Subcommand("run", "Build if needed, then run") RunArgs run;
    /// test.
    @Subcommand("test", "Run unittests with the canonical flags") TestArgs test;
    /// check.
    @Subcommand("check", "Run every check, as CI does") CheckArgs check;
    /// fmt.
    @Subcommand("fmt", "Format D sources") FmtArgs fmt;
    /// lock.
    @Subcommand("lock", "Write or verify flint.lock") LockArgs lock;
    /// deps.
    @Subcommand("deps", "Inspect and change the dependency graph") DepsArgs deps;
    /// package.
    @Subcommand("package", "Package a release executable, with an OCI image and SBOMs") PackageArgs package_;
    /// toolchain.
    @Subcommand("toolchain", "Install, verify or describe the pinned toolchain") ToolchainArgs toolchain;
    /// doctor.
    @Subcommand("doctor", "Explain environment problems") DoctorArgs doctor;
    /// daemon.
    @Subcommand("daemon", "Manage the DMD compile server") DaemonArgs daemon;
    /// version.
    @Subcommand("version", "Print tool, toolchain and source identities") VersionArgs version_;
    /// explain.
    @Subcommand("explain", "Explain a diagnostic code") ExplainArgs explain;
    /// receipt.
    @Subcommand("receipt", "Verify an artifact against its receipt") ReceiptArgs receipt;
}
