/// The command-line schema, bound by flint.cli.
module flint_tool.commands.args;

import flint.cli : Arg, Command, Option, Subcommand;

@safe:

/// `flint new`.
@Command("flint new", "Create a project that builds, runs and tests")
struct NewArgs
{
    /// Project name.
    @Arg(0, "Project name: lower-case letters, digits and hyphens")
    string name;
    /// Starters to scaffold.
    @Option("starter", 's', "Comma-separated starters whose core packages to add (web,data,cli,...)")
    string starter;
    /// Target directory.
    @Option("path", 0, "Directory to create (default: ./<name>)")
    string path;
    /// Project type.
    @Option("type", 't', "executable or library")
    string type = "executable";
    /// Print the files without writing them.
    @Option("plan", 0, "Print the files that would be written, without writing")
    bool plan;
    /// JSON output.
    @Option("json", 0, "Emit flint.new/1 JSON on stdout")
    bool json;
}

/// `flint build`.
@Command("flint build", "Build the project, or workspace packages, with a canonical profile")
struct BuildArgs
{
    /// Workspace packages.
    @Arg(0, "Workspace packages to build (default: all); ignored in a project")
    string[] packages;
    /// Profile.
    @Option("profile", 'p', "dev, release, size or sanitize")
    string profile = "dev";
    /// Compiler override.
    @Option("compiler", 'c', "Override the profile's compiler (dmd or ldc2); non-canonical")
    string compiler;
    /// Extra compiler flags.
    @Option("dflags", 0, "Add a compiler flag on top of the profile (repeatable); non-canonical")
    string[] dflags;
    /// Extra linker flags.
    @Option("lflags", 0, "Add a linker flag on top of the profile (repeatable); non-canonical")
    string[] lflags;
    /// Fail on toolchain mismatches.
    @Option("verify", 0, "Turn toolchain mismatches into errors")
    bool verify;
    /// Require a current lock.
    @Option("locked", 0, "Fail when flint.lock is missing instead of writing it")
    bool locked;
    /// Rebuild everything.
    @Option("force", 'f', "Rebuild even when up to date")
    bool force;
    /// Compile the platform modules from source.
    @Option("no-platform-cache", 0, "Compile the platform modules from source instead of linking cached archives")
    bool noPlatformCache;
    /// Build without debug information and link without a symbol table, as the Go comparator's `-s -w`.
    @Option("no-debug", 0, "Build without debug information and link without a symbol table (the measured builds)")
    bool noDebug;
    /// Link the platform's archives into a dev build instead of the shared platform object.
    @Option("static", 0, "Link the platform modules statically into a dev build, as release and size builds do")
    bool staticLink;
    /// Project directory.
    @Option("project", 'C', "Run in this project or workspace directory")
    string project;
    /// Stream tool output.
    @Option("verbose", 'v', "Stream DUB and compiler output")
    bool verbose;
    /// JSON output.
    @Option("json", 0, "Emit flint.build/1 JSON on stdout")
    bool json;
}

/// `flint run`.
@Command("flint run", "Build if needed, then run the executable; arguments after -- go to the program")
struct RunArgs
{
    /// Profile.
    @Option("profile", 'p', "dev, release or size")
    string profile = "dev";
    /// Extra compiler flags.
    @Option("dflags", 0, "Add a compiler flag (repeatable); non-canonical")
    string[] dflags;
    /// Fail on toolchain mismatches.
    @Option("verify", 0, "Turn toolchain mismatches into errors")
    bool verify;
    /// Require a current lock.
    @Option("locked", 0, "Fail when flint.lock is missing")
    bool locked;
    /// Project directory.
    @Option("project", 'C', "Run in this project directory")
    string project;
    /// Debugger.
    @Option("debug", 0, "Start the program under gdb (or lldb) with Flint's pretty-printers")
    bool debug_;
    /// Stream tool output.
    @Option("verbose", 'v', "Stream DUB and compiler output")
    bool verbose;
    /// JSON output.
    @Option("json", 0, "Capture the program's output in flint.run/1 JSON")
    bool json;
}

/// `flint watch`.
@Command("flint watch", "Rebuild and restart, or retest, on every change; arguments after -- go to the program")
struct WatchArgs
{
    /// Tests.
    @Option("test", 0, "Run the tests on every change (the default for libraries)")
    bool test;
    /// Build only.
    @Option("build", 0, "Only build on every change")
    bool build;
    /// Project directory.
    @Option("project", 'C', "Watch this project directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit one flint.watch/1 JSON line per cycle on stdout")
    bool json;
}

/// `flint test`.
@Command("flint test", "Run unittests with the canonical flags")
struct TestArgs
{
    /// Workspace packages.
    @Arg(0, "Workspace packages to test (default: all); ignored in a project")
    string[] packages;
    /// Compilers.
    @Option("compiler", 'c', "dmd, ldc (ldc2) or both (default: the test profile's compiler)")
    string compiler;
    /// Fail on toolchain mismatches.
    @Option("verify", 0, "Turn toolchain mismatches into errors")
    bool verify;
    /// Require a current lock.
    @Option("locked", 0, "Fail when flint.lock is missing")
    bool locked;
    /// Rebuild everything.
    @Option("force", 'f', "Rebuild even when up to date")
    bool force;
    /// ASan and UBSan.
    @Option("sanitize", 0, "Build with ASan and UBSan (LDC, the sanitize profile; embedded C included)")
    bool sanitize;
    /// Live scenarios.
    @Option("scenarios", 0, "Also run declared live scenarios (mq: Kafka, JetStream)")
    bool scenarios;
    /// Project directory.
    @Option("project", 'C', "Run in this project or workspace directory")
    string project;
    /// Stream tool output.
    @Option("verbose", 'v', "Stream DUB, compiler and test output")
    bool verbose;
    /// JSON output.
    @Option("json", 0, "Emit flint.test/1 JSON on stdout")
    bool json;
}

/// `flint check`.
@Command("flint check", "Run every layout, safety, format and lint check, as CI does")
struct CheckArgs
{
    /// Restrict to one gate.
    @Option("gate", 'g', "Run only this gate: structural (the workspace's tools/gates.py gate)")
    string gate;
    /// Workspace packages for the structural gate.
    @Option("package", 0, "Restrict the structural gate to this workspace package (repeatable)")
    string[] packages;
    /// One repo of the split.
    @Option("repo", 0, "Restrict the structural gate to one repo's packages (policy/repos.json)")
    string repo;
    /// Project directory.
    @Option("project", 'C', "Run in this project or workspace directory")
    string project;
    /// Show more detail.
    @Option("verbose", 'v', "Show more detail")
    bool verbose;
    /// JSON output.
    @Option("json", 0, "Emit flint.check/1 JSON on stdout")
    bool json;
}

/// `flint fmt`.
@Command("flint fmt", "Format D sources with the pinned dfmt")
struct FmtArgs
{
    /// Report only.
    @Option("check", 0, "Report unformatted files without rewriting them")
    bool check;
    /// Project directory.
    @Option("project", 'C', "Run in this project or workspace directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.fmt/1 JSON on stdout")
    bool json;
}

/// `flint lock`.
@Command("flint lock", "Write flint.lock, or verify it with --check")
struct LockArgs
{
    /// Verify only.
    @Option("check", 0, "Verify flint.lock without writing it")
    bool check;
    /// Project directory.
    @Option("project", 'C', "Run in this project directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.lock/1 JSON on stdout")
    bool json;
}

/// Options every deps subcommand takes.
struct DepsCommon
{
    /// Project directory.
    @Option("project", 'C', "Run in this project directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.deps/1 JSON on stdout")
    bool json;
}

/// `flint deps why`.
struct DepsWhyArgs
{
    /// Package.
    @Arg(0, "Package to explain, such as github.com/acme/money or flint:log")
    string name;
    /// Project directory.
    @Option("project", 'C', "Run in this project directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.deps/1 JSON on stdout")
    bool json;
}

/// `flint deps update`.
struct DepsUpdateArgs
{
    /// Packages.
    @Arg(0, "Repository-path dependencies to update (default: all)")
    string[] names;
    /// Project directory.
    @Option("project", 'C', "Run in this project directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.deps/1 JSON on stdout")
    bool json;
}

/// `flint package`.
@Command("flint package", "Build a release executable for a target and package it, static by default")
struct PackageArgs
{
    /// Target.
    @Option("target", 't', "linux-x86_64-glibc or linux-x86_64-musl (default: the host; musl with --container)")
    string target;
    /// OCI image.
    @Option("container", 0, "Also write a FROM scratch OCI image around the static musl executable")
    bool container;
    /// SBOMs.
    @Option("sbom", 0, "Also write SPDX 2.3 and CycloneDX 1.6 SBOMs")
    bool sbom;
    /// Fail on toolchain mismatches.
    @Option("verify", 0, "Turn toolchain mismatches into errors")
    bool verify;
    /// Require a current lock.
    @Option("locked", 0, "Fail when flint.lock is missing instead of writing it")
    bool locked;
    /// Project directory.
    @Option("project", 'C', "Package this project directory")
    string project;
    /// Stream tool output.
    @Option("verbose", 'v', "Stream DUB and compiler output")
    bool verbose;
    /// JSON output.
    @Option("json", 0, "Emit flint.package/1 JSON on stdout")
    bool json;
}

/// `flint deps audit`.
struct DepsAuditArgs
{
    /// Target.
    @Option("target", 't', "Audit the executable for this target (default: the host)")
    string target;
    /// Project directory.
    @Option("project", 'C', "Run in this project directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.deps/1 JSON on stdout")
    bool json;
}

/// `flint deps`.
@Command("flint deps", "Inspect and change the dependency graph")
struct DepsArgs
{
    /// tree.
    @Subcommand("tree", "Print the resolved dependency graph")
    DepsCommon tree;
    /// why.
    @Subcommand("why", "Show why a package is in the graph")
    DepsWhyArgs why;
    /// update.
    @Subcommand("update", "Raise repository-path dependencies to their latest release")
    DepsUpdateArgs update;
    /// vendor.
    @Subcommand("vendor", "Copy repository-path modules into vendor/ for offline builds")
    DepsCommon vendor;
    /// audit.
    @Subcommand("audit", "Verify hashes and list licences and LGPL/AGPL obligations")
    DepsAuditArgs audit;
}

/// Options every toolchain subcommand takes.
struct ToolchainCommon
{
    /// Toolchain directory.
    @Option("toolchain-dir", 0, "Toolchain directory (default: <flint>/.tools)")
    string directory;
    /// JSON output.
    @Option("json", 0, "Emit flint.toolchain/1 JSON on stdout")
    bool json;
}

/// `flint toolchain install`.
@Command("flint toolchain install", "Install the pinned toolchain and write its receipt")
struct ToolchainInstallArgs
{
    /// Toolchain directory.
    @Option("toolchain-dir", 0, "Install into this directory (default: <flint>/.tools)")
    string directory;
    /// Print the commands only.
    @Option("plan", 0, "Print the installer commands without running them")
    bool plan;
    /// Skip PGO.
    @Option("no-pgo", 0, "Build the DMD fork without profile-guided optimisation")
    bool noPgo;
    /// Linker.
    @Option("dmd-linker", 0, "Configure DMD to link with this installed ld.lld or mold")
    string linker;
    /// Sanitizer runtime.
    @Option("sanitizers", 0, "Also build the LDC runtime flint test --sanitize links")
    bool sanitizers;
    /// musl.
    @Option("musl", 0, "Also install what flint package --target linux-x86_64-musl needs")
    bool musl;
    /// JSON output.
    @Option("json", 0, "Emit flint.toolchain/1 JSON on stdout")
    bool json;
}

/// `flint toolchain`.
@Command("flint toolchain", "Install, verify or describe the pinned toolchain")
struct ToolchainArgs
{
    /// install.
    @Subcommand("install", "Install the pinned toolchain and write its receipt")
    ToolchainInstallArgs install;
    /// verify.
    @Subcommand("verify", "Check the toolchain against policy and the fork patches")
    ToolchainCommon verify;
    /// info.
    @Subcommand("info", "Describe the installed toolchain")
    ToolchainCommon info;
}

/// `flint doctor`.
@Command("flint doctor", "Explain environment problems that would make a build non-canonical")
struct DoctorArgs
{
    /// Project directory.
    @Option("project", 'C', "Also check this project or workspace")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.doctor/1 JSON on stdout")
    bool json;
}

/// Options of `flint daemon start`.
struct DaemonStartArgs
{
    /// Profile whose flags key the server.
    @Option("profile", 'p', "Profile whose compiler flags the server is keyed by")
    string profile = "dev";
    /// JSON output.
    @Option("json", 0, "Emit flint.daemon/1 JSON on stdout")
    bool json;
}

/// Options of `flint daemon stop` and `status`.
struct DaemonCommon
{
    /// JSON output.
    @Option("json", 0, "Emit flint.daemon/1 JSON on stdout")
    bool json;
}

/// `flint daemon`.
@Command("flint daemon", "Manage the DMD compile server")
struct DaemonArgs
{
    /// start.
    @Subcommand("start", "Start the compile server for a profile's flags")
    DaemonStartArgs start;
    /// stop.
    @Subcommand("stop", "Stop every compile server of this user")
    DaemonCommon stop;
    /// status.
    @Subcommand("status", "List compile servers")
    DaemonCommon status;
}

/// `flint version`.
@Command("flint version", "Print the tool, toolchain and source identities")
struct VersionArgs
{
    /// Verify this executable against its receipt.
    @Option("verify", 0, "Verify this flint executable against the receipt next to it")
    bool verify;
    /// JSON output.
    @Option("json", 0, "Emit flint.version/1 JSON on stdout")
    bool json;
}

/// `flint generate`.
@Command("flint generate", "Write the canonical shape of a component, or AGENTS.md")
struct GenerateArgs
{
    /// Kind.
    @Arg(0, "entity, repository, service, controller, config, migration or agents")
    string kind;
    /// Name.
    @Arg(1, "PascalCase component name, such as Order (not for agents)")
    string name;
    /// Plan.
    @Option("plan", 0, "Print the files and flint.toml changes without writing")
    bool plan;
    /// Project directory.
    @Option("project", 'C', "Generate in this project directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.generate/1 JSON on stdout")
    bool json;
}

/// `flint add`.
@Command("flint add", "Wire starters into the project: dependency, configuration section and lock")
struct AddArgs
{
    /// Starters.
    @Arg(0, "Starters, such as web or data")
    string[] starters;
    /// Plan.
    @Option("plan", 0, "Print the flint.toml and configuration changes without writing")
    bool plan;
    /// Project directory.
    @Option("project", 'C', "Add to this project directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.add/1 JSON on stdout")
    bool json;
}

/// `flint openapi`.
@Command("flint openapi",
        "Print the OpenAPI document of a starter-web application, or write it and a TypeScript client")
struct OpenApiArgs
{
    /// Output file.
    @Option("output", 'o', "Write the document to this file instead of standard output")
    string output;
    /// TypeScript client.
    @Option("typescript", 0, "Also write a typed TypeScript client to this file")
    string typescript;
    /// Project directory.
    @Option("project", 'C', "Document this project directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.openapi/1 JSON on stdout")
    bool json;
}

/// `flint config`.
@Command("flint config", "Print every resolved configuration key with its value and source")
struct ConfigArgs
{
    /// Profile.
    @Option("profile", 'p', "Configuration profile (default dev)")
    string profile = "dev";
    /// Project directory.
    @Option("project", 'C', "Run in this project directory")
    string project;
    /// JSON output.
    @Option("json", 0, "Emit flint.config/1 JSON on stdout")
    bool json;
}

/// `flint lsp`.
@Command("flint lsp", "Serve the Language Server Protocol on stdio: diagnostics, hover, definition and completion")
struct LspArgs
{
}

/// `flint mcp`.
@Command("flint mcp", "Serve the Flint API, diagnostics and build loop to MCP clients over stdio")
struct McpArgs
{
    /// Call log.
    @Option("log", 0, "Append one JSON line per tool call to this file")
    string log;
}

/// `flint docs`.
@Command("flint docs", "Search the pinned Flint API: signatures, documentation and tested examples")
struct DocsArgs
{
    /// Query words or a qualified name.
    @Arg(0, "Words to search for, or a qualified name such as flint.config.load")
    string[] query;
    /// Export.
    @Option("export", 0, "Write llms.txt and llms-full.txt to this directory")
    string exportDirectory;
    /// Limit.
    @Option("limit", 'n', "Show at most this many symbols (default 10)")
    uint limit = 10;
    /// JSON output.
    @Option("json", 0, "Emit flint.docs/1 JSON on stdout")
    bool json;
}

/// `flint examples`.
@Command("flint examples", "Show compiled, tested examples for a topic")
struct ExamplesArgs
{
    /// Topic words.
    @Arg(0, "Topic, such as \"rest controller\" or \"config load\"")
    string[] topic;
    /// Limit.
    @Option("limit", 'n', "Show at most this many examples (default 5)")
    uint limit = 5;
    /// JSON output.
    @Option("json", 0, "Emit flint.examples/1 JSON on stdout")
    bool json;
}

/// `flint explain`.
@Command("flint explain", "Explain a diagnostic code, with a correct example")
struct ExplainArgs
{
    /// Code.
    @Arg(0, "Diagnostic code, such as FLINT-E0401")
    string code;
    /// List all codes.
    @Option("list", 'l', "List every code")
    bool list;
    /// JSON output.
    @Option("json", 0, "Emit flint.explain/1 JSON on stdout")
    bool json;
}

/// `flint receipt`.
@Command("flint receipt", "Verify an artifact against its build receipt")
struct ReceiptArgs
{
    /// Artifact.
    @Arg(0, "Artifact path; its receipt is <artifact>.receipt.json")
    string artifact;
    /// Refuse non-canonical receipts.
    @Option("canonical", 0, "Refuse artifacts whose receipt is non-canonical")
    bool canonical;
    /// JSON output.
    @Option("json", 0, "Emit flint.receipt/1 JSON on stdout")
    bool json;
}

/// `flint api extract`.
@Command("flint api extract", "Write the API manifest of an upstream Java source tree")
struct ApiExtractArgs
{
    /// Source tree.
    @Option("source", 's', "Root of the upstream Java source tree")
    string source;
    /// Project.
    @Option("project", 'p', "Upstream project name, such as spring-framework")
    string project;
    /// Tag; `--version` is accepted for it (flint.cli reserves --version for itself).
    @Option("tag", 0, "Upstream tag, such as v7.1.0 (also --version TAG)")
    string tag;
    /// Output.
    @Option("output", 'o', "Manifest to write (default: api/upstream/<project>-<tag>.json)")
    string output;
    /// Extra exclusions.
    @Option("exclude", 0, "Leave out this root-relative path prefix (repeatable; adds to api/upstreams.json)")
    string[] excludes;
    /// JSON output.
    @Option("json", 0, "Emit flint.api-extract/1 JSON on stdout")
    bool json;
}

/// `flint api fetch`.
@Command("flint api fetch", "Download the pinned upstream sources into the reference cache, verified by SHA-256")
struct ApiFetchArgs
{
    /// Projects.
    @Arg(0, "Pinned projects to fetch (default: all of api/upstreams.json)")
    string[] projects;
    /// Cache override.
    @Option("cache", 0, "Reference cache directory (default: <flint home>/.flint/cache/api)")
    string cache;
    /// Test-source archives.
    @Option("tests", 0, "Fetch the test-source archives of api/upstream-tests.json, into <project>-<version>-tests")
    bool tests;
    /// JSON output.
    @Option("json", 0, "Emit flint.api-fetch/1 JSON on stdout")
    bool json;
}

/// `flint api coverage`.
@Command("flint api coverage", "Classify manifest elements against api/mapping.json; fail on unclassified ones")
struct ApiCoverageArgs
{
    /// Manifests.
    @Option("manifest", 'm', "Upstream manifest to classify (repeatable)")
    string[] manifests;
    /// Mapping.
    @Option("mapping", 0, "The mapping (default: api/<repo>/mapping.json, else api/mapping.json)")
    string mapping;
    /// Repo.
    @Option("repo", 0, "Classify every manifest api/upstreams.json assigns to this repo")
    string repo;
    /// Release mode.
    @Option("release", 0, "Require every element classified, whatever the baseline says (the release gate)")
    bool release;
    /// Lower the baseline.
    @Option("update-baseline", 0, "Lower coverage-baseline.json to the current counts; refuses to raise any")
    bool updateBaseline;
    /// Baseline path.
    @Option("baseline", 0, "The ratchet's baseline (default: coverage-baseline.json beside the mapping)")
    string baseline;
    /// Slice files.
    @Option("slice", 0,
            "Slice whose complete checklists must be complete (repeatable; default: docs/spring/*/slice.json)")
    string[] slices;
    /// How many unclassified ids to print.
    @Option("show", 0, "Unclassified element ids to print per manifest (default: 20)")
    uint show = 20;
    /// JSON output.
    @Option("json", 0, "Emit flint.api-coverage/1 JSON on stdout, with every unclassified id")
    bool json;
}

/// `flint api diff`.
@Command("flint api diff", "List API elements added, removed or changed between two manifests")
struct ApiDiffArgs
{
    /// Older manifest.
    @Arg(0, "The older manifest")
    string older;
    /// Newer manifest.
    @Arg(1, "The newer manifest")
    string newer;
    /// JSON output.
    @Option("json", 0, "Emit flint.api-diff/1 JSON on stdout")
    bool json;
}

/// `flint api checklist`.
@Command("flint api checklist", "Write per-module checklists of a porting slice, with statuses from the mapping")
struct ApiChecklistArgs
{
    /// Slice file.
    @Option("slice", 0, "flint.api-slice/1 file naming the checklists")
    string slice;
    /// Output directory.
    @Option("output", 'o', "Directory for <name>.md and README.md")
    string output;
    /// JSON output.
    @Option("json", 0, "Emit flint.api-checklist/1 JSON on stdout")
    bool json;
}

/// `flint api headers`.
@Command("flint api headers", "Check the ADR-030 header of every D file ported from an upstream")
struct ApiHeadersArgs
{
    /// Paths.
    @Arg(0, "Source directories or D files (default: .)")
    string[] paths;
    /// JSON output.
    @Option("json", 0, "Emit flint.api-headers/1 JSON on stdout")
    bool json;
}

/// `flint api`.
@Command("flint api", "Extract, compare and classify the upstream Java APIs that Flint ports")
struct ApiArgs
{
    /// fetch.
    @Subcommand("fetch", "Download the pinned upstream sources into the reference cache, verified by SHA-256")
    ApiFetchArgs fetch;
    /// extract.
    @Subcommand("extract", "Write the API manifest of an upstream Java source tree")
    ApiExtractArgs extract;
    /// coverage.
    @Subcommand("coverage", "Classify manifest elements against api/mapping.json; fail on unclassified ones")
    ApiCoverageArgs coverage;
    /// diff.
    @Subcommand("diff", "List API elements added, removed or changed between two manifests")
    ApiDiffArgs diff;
    /// checklist.
    @Subcommand("checklist", "Write per-module checklists of a porting slice")
    ApiChecklistArgs checklist;
    /// headers.
    @Subcommand("headers", "Check the header of every ported D file against the licence matrix")
    ApiHeadersArgs headers;
}

/// The root command.
@Command("flint", "One tool to create, build, run, test and check Flint projects with the pinned toolchain.", "0.7.0")
struct FlintArgs
{
    /// new.
    @Subcommand("new", "Create a project that builds, runs and tests")
    NewArgs create;
    /// build.
    @Subcommand("build", "Build with a canonical profile and write a receipt")
    BuildArgs build;
    /// run.
    @Subcommand("run", "Build if needed, then run")
    RunArgs run;
    /// test.
    @Subcommand("test", "Run unittests with the canonical flags")
    TestArgs test;
    /// check.
    @Subcommand("check", "Run every check, as CI does")
    CheckArgs check;
    /// fmt.
    @Subcommand("fmt", "Format D sources")
    FmtArgs fmt;
    /// lock.
    @Subcommand("lock", "Write or verify flint.lock")
    LockArgs lock;
    /// deps.
    @Subcommand("deps", "Inspect and change the dependency graph")
    DepsArgs deps;
    /// package.
    @Subcommand("package", "Package a release executable, with an OCI image and SBOMs")
    PackageArgs package_;
    /// toolchain.
    @Subcommand("toolchain", "Install, verify or describe the pinned toolchain")
    ToolchainArgs toolchain;
    /// doctor.
    @Subcommand("doctor", "Explain environment problems")
    DoctorArgs doctor;
    /// daemon.
    @Subcommand("daemon", "Manage the DMD compile server")
    DaemonArgs daemon;
    /// version.
    @Subcommand("version", "Print tool, toolchain and source identities")
    VersionArgs version_;
    /// explain.
    @Subcommand("explain", "Explain a diagnostic code")
    ExplainArgs explain;
    /// docs.
    @Subcommand("docs", "Search the pinned Flint API")
    DocsArgs docs;
    /// generate.
    @Subcommand("generate", "Write the canonical shape of a component")
    GenerateArgs generate;
    /// add.
    @Subcommand("add", "Wire starters into the project")
    AddArgs add;
    /// openapi.
    @Subcommand("openapi", "OpenAPI document and TypeScript client from the controllers")
    OpenApiArgs openapi;
    /// config.
    @Subcommand("config", "Print the resolved configuration")
    ConfigArgs config;
    /// watch.
    @Subcommand("watch", "Rebuild and restart, or retest, on every change")
    WatchArgs watch;
    /// mcp.
    @Subcommand("mcp", "Serve Flint knowledge and the build loop over MCP")
    McpArgs mcp;
    /// lsp.
    @Subcommand("lsp", "Serve the Language Server Protocol on stdio")
    LspArgs lsp;
    /// examples.
    @Subcommand("examples", "Show tested examples for a topic")
    ExamplesArgs examples;
    /// receipt.
    @Subcommand("receipt", "Verify an artifact against its receipt")
    ReceiptArgs receipt;
    /// api.
    @Subcommand("api", "Upstream API manifests, coverage and diffs")
    ApiArgs api;
}
