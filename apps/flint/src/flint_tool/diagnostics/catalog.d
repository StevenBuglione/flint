/// The stable catalogue of diagnostics flint raises (ADR-021 section 6, diagnostics v1).
///
/// Codes are API: a code is never reused for a different problem and never removed.
module flint_tool.diagnostics.catalog;

@safe:

private enum ffiExplanation = "Embedded C (native/ or [native.c]) and native libraries are reached from D "
    ~ "only through `<root>.ffi` modules (and `<root>.sys`), which wrap them in a safe D API. An extern(C) "
    ~ "declaration elsewhere, or a C file among the D sources (ImportC), would let any module call C directly.";

private enum ffiExample = "// src/shop/ffi/checksum.d\nmodule shop.ffi.checksum;\n\n"
    ~ "extern (C) uint shop_crc32(scope const(ubyte)* data, size_t length) @system nothrow @nogc;";

/// The stable process exit codes (ADR-021 section 1).
enum ExitCode : int
{
    /// Success.
    ok = 0,
    /// The user's code failed to build, test or pass a check.
    user = 1,
    /// The environment or toolchain is wrong.
    environment = 2,
    /// Dependency resolution or the lock failed.
    dependency = 3,
    /// The command line was wrong.
    usage = 4
}

/// One catalogue entry.
struct CodeInfo
{
    /// `FLINT-Ennnn`.
    string code;
    /// Exit code the error maps to.
    ExitCode exit;
    /// One-line title.
    string title;
    /// Long explanation for `flint explain`.
    string explanation;
    /// A correct example or the exact fix.
    string example;
}

/// Find a code, case-insensitively, with or without the `FLINT-` prefix.
const(CodeInfo)* lookup(scope const(char)[] code)
{
    import std.ascii : toUpper;

    char[] normalized;
    foreach (ch; code)
        normalized ~= toUpper(ch);
    if (normalized.length && normalized[0] == 'E')
        normalized = "FLINT-".dup ~ normalized;
    foreach (ref entry; catalog)
    {
        if (entry.code == normalized)
            return &entry;
    }
    return null;
}

/// Every code flint can raise, in numeric order.
immutable CodeInfo[] catalog = [
    // 00xx: command line.
    CodeInfo("FLINT-E0001", ExitCode.usage,
            "unknown command or option",
            "The command line names a command, subcommand or option that flint does not have, or an option value "
            ~ "could not be parsed. flint never guesses: it stops before doing any work.",
            "flint build --profile release\nflint help build      # lists every option"),
    CodeInfo("FLINT-E0002", ExitCode.usage, "a required argument or subcommand is missing",
            "The command needs a subcommand (for example `flint toolchain verify`) or a positional argument "
            ~ "(for example the project name of `flint new`).",
            "flint new shop\nflint toolchain verify\nflint daemon status"),
    CodeInfo("FLINT-E0003", ExitCode.usage, "invalid option value",
            "An option has a value outside its documented set, such as an unknown profile or compiler.",
            "flint build --profile dev        # dev, release or size\n"
            ~ "flint test --compiler both       # dmd, ldc or both"),
    CodeInfo("FLINT-E0004", ExitCode.usage,
            "conflicting options",
            "Two options ask for incompatible behaviour, such as `--check` with a command that rewrites files.",
            "flint fmt --check     # report only\nflint fmt             # rewrite"),
    CodeInfo("FLINT-E0005", ExitCode.usage, "unknown diagnostic code",
            "`flint explain` was given a code that is not in the catalogue. Codes have the form FLINT-Ennnn.",
            "flint explain FLINT-E0401\nflint explain --list"),
    CodeInfo("FLINT-E0006", ExitCode.usage, "target directory already exists",
            "`flint new` never overwrites files. The directory for the new project already exists.",
            "flint new shop2\nflint new shop --path elsewhere/shop"),
    CodeInfo("FLINT-E0007", ExitCode.usage,
            "nothing matches the query",
            "`flint docs` and `flint examples` search an index of the pinned Flint libraries, built from their "
            ~ "sources by the pinned compiler. No public symbol or tested example matches every word of the query.",
            "flint docs              # list the packages\nflint docs config load\nflint examples rest controller"),
    CodeInfo("FLINT-E0008", ExitCode.usage, "the file to generate already exists",
            "`flint generate` never overwrites a file (except AGENTS.md, which it owns). The component already "
            ~ "exists, or another file has its path.", "flint generate entity OrderLine"),
    CodeInfo("FLINT-E0009", ExitCode.usage, "not a starter",
            "`flint add` wires starters: packages of auto-configuration over the core packages, listed in "
            ~ "policy/starters.json. A starter is named by its domain, such as `web` or `data`, or in full, such as "
            ~ "`starter-web`.",
            "flint add web\nflint add data security"),

    // 01xx: the manifest.
    CodeInfo("FLINT-E0101", ExitCode.usage, "not inside a Flint project",
            "No flint.toml was found in the current directory or any parent. flint commands that act on a project "
            ~ "run inside it, or name it with --project.",
            "cd shop && flint build\nflint build --project shop"),
    CodeInfo("FLINT-E0102", ExitCode.user, "flint.toml is not valid TOML",
            "The manifest could not be parsed. The location points at the first byte the parser rejected.",
            "[project]\nname = \"shop\"          # strings are quoted\nversion = \"0.1.0\""),
    CodeInfo("FLINT-E0103", ExitCode.user, "unknown key in flint.toml",
            "flint.toml has a closed schema so that typos never pass silently. The diagnostic suggests the closest "
            ~ "known key. Sections are [project], [build], [starters], [dependencies], [test-dependencies], "
            ~ "[profile.<name>], [targets], [[waivers]] and [unchecked].",
            "[project]\nversion = \"0.1.0\"       # not `verison`"),
    CodeInfo("FLINT-E0104", ExitCode.user, "required manifest key is missing",
            "[project] needs `name`, `version` and `flint` (the platform version).",
            "[project]\nname = \"shop\"\nversion = \"0.1.0\"\nflint = \"1.0\""),
    CodeInfo("FLINT-E0105", ExitCode.user, "manifest value has the wrong type or format",
            "A manifest value has the wrong TOML type or does not match its format: versions are semantic versions, "
            ~ "flag lists are arrays of strings, and dependency entries are tables.",
            "version = \"0.1.0\"\ndflags = [\"-mcpu=native\"]\n\"flint:log\" = {}"),
    CodeInfo("FLINT-E0106", ExitCode.user, "invalid project name",
            "A project name is lower-case ASCII letters, digits and hyphens, starts with a letter, and is at most "
            ~ "64 bytes. Its module root replaces hyphens with underscores and must not be `flint` (reserved for the "
            ~ "core libraries) or a D keyword.",
            "name = \"order-service\"     # modules: order_service.*"),
    CodeInfo("FLINT-E0107", ExitCode.environment, "platform version not provided by this Flint installation",
            "`flint = \"x.y\"` pins the toolchain, the core library set and the rule set together. The installed "
            ~ "Flint provides a different platform version.",
            "flint = \"1.0\"\nflint version     # shows the installed platform"),
    CodeInfo("FLINT-E0108", ExitCode.user, "unknown build profile",
            "Profiles are defined by Flint's policy (dev, test, release, size, sanitize). A project may add flags to "
            ~ "them under [profile.<name>] but cannot invent new ones yet.",
            "[profile.release]\ndflags = [\"-mcpu=native\"]"),
    CodeInfo("FLINT-E0109", ExitCode.user, "invalid waiver",
            "A waiver lifts one rule for one file and must give a reason. Every build lists active waivers "
            ~ "in its output and receipt. An [unchecked] entry names a local DUB dependency and gives a reason.",
            "[[waivers]]\nrule = \"FLINT-E0502\"\nfile = \"src/shop/legacy.d\"\n"
            ~ "reason = \"vendored parser, tracked in #12\""),
    CodeInfo("FLINT-E0110", ExitCode.user, "unsupported target",
            "The [targets] list names a target this Flint release cannot build. Milestone 7 builds the host target, "
            ~ "linux-x86_64-glibc.",
            "[targets]\ndefault = [\"linux-x86_64-glibc\"]"),

    // 02xx: the lock file.
    CodeInfo("FLINT-E0201", ExitCode.dependency, "flint.lock is missing",
            "Builds with --locked require an existing flint.lock. `flint lock` writes it from flint.toml.",
            "flint lock\ngit add flint.lock"),
    CodeInfo("FLINT-E0202", ExitCode.dependency, "flint.lock is out of date",
            "flint.lock records the exact dependency graph, content hashes and toolchain identity. What flint resolves "
            ~ "now differs, so the build is not reproducible from the lock. Review the change and accept it.",
            "flint lock          # rewrite flint.lock from the current inputs\ngit diff flint.lock"),
    CodeInfo("FLINT-E0203", ExitCode.dependency, "flint.lock is malformed",
            "flint.lock is generated and must not be edited by hand. Regenerate it.",
            "flint lock"),

    // 03xx: dependencies.
    CodeInfo("FLINT-E0301", ExitCode.dependency, "unknown Flint core package",
            "Core packages are named `flint:<package>` after the 37 packages in policy/packages.json.",
            "[dependencies]\n\"flint:web\" = {}"),
    CodeInfo("FLINT-E0302", ExitCode.dependency,
            "path dependency not found",
            "A `path` dependency must name a directory containing a flint.toml (a Flint project) or a dub.sdl or "
            ~ "dub.json (a local DUB package). Relative paths are resolved from the project root.",
            "[dependencies]\nshared-model = { path = \"../shared-model\" }"),
    CodeInfo("FLINT-E0303", ExitCode.dependency, "remote dependencies are not available yet",
            "Repository-path dependencies with semantic versions are resolved by minimal version selection in "
            ~ "Milestone 8. Milestone 7 resolves Flint core packages and path dependencies.",
            "[dependencies]\nstripe = { path = \"../vendor/flint-stripe\" }"),
    CodeInfo("FLINT-E0304", ExitCode.dependency, "dependency cycle",
            "Path dependencies form a cycle. Flint rejects cycles, including through generated code.",
            "Move the shared types into a third project both depend on."),
    CodeInfo("FLINT-E0305", ExitCode.dependency, "core packages take no version",
            "The versions of Flint core packages come from the platform version (`flint = \"1.0\"`), like a "
            ~ "Spring Boot BOM, so a project never mixes incompatible core versions.",
            "[dependencies]\n\"flint:log\" = {}"),
    CodeInfo("FLINT-E0306", ExitCode.dependency, "dependency name collides",
            "A dependency's module root equals the project's own module root or another dependency's.",
            "Rename one of the projects; module roots must be unique in a build."),
    CodeInfo("FLINT-E0307", ExitCode.dependency,
            "dependency not available offline",
            "FLINT_PROXY=off or FLINT_OFFLINE=1 builds only from the content-addressed cache under the Flint home and "
            ~ "from vendor/. The required module version is in neither.",
            "flint lock        # once, online\nflint deps vendor # to build anywhere without a network"),
    CodeInfo("FLINT-E0308", ExitCode.dependency,
            "repository or version not found",
            "flint fetches a repository-path dependency with git from https://<path>, or from FLINT_PROXY/<path>, and "
            ~ "takes version x.y.z from tag vx.y.z. The repository could not be fetched or has no such tag.",
            "\"github.com/acme/flint-stripe\" = \"1.4.2\"   # needs tag v1.4.2"),
    CodeInfo("FLINT-E0309", ExitCode.dependency, "dependency content differs from its recorded hash",
            "Cached and vendored module trees are content-addressed and verified on every use. A file changed after it "
            ~ "was fetched, so the build would not be reproducible.",
            "delete the cache entry or vendor/<path> and fetch again; never edit fetched sources"),
    CodeInfo("FLINT-E0310", ExitCode.dependency, "published module has a path dependency",
            "A repository-path module must resolve the same way on every machine, so it may depend only on Flint core "
            ~ "packages and other repository paths.",
            "[dependencies]\n\"github.com/acme/money\" = \"1.2.0\""),
    CodeInfo("FLINT-E0311", ExitCode.dependency, "package not in the dependency graph",
            "`flint deps why` explains a package the project actually depends on.", "flint deps tree"),
    CodeInfo("FLINT-E0312", ExitCode.dependency, "component licence unknown",
            "`flint deps audit` lists every component's SPDX licence expression. A dependency whose flint.toml sets "
            ~ "no `license` cannot be checked for obligations; review its terms before distributing.",
            "[project]\nlicense = \"Apache-2.0\""),
    CodeInfo("FLINT-E0313", ExitCode.dependency, "component used without the safety checks",
            "A DUB package listed under [unchecked] skipped Flint's safety checks (@safe defaults, @trusted "
            ~ "confinement, the ffi boundary). Every build, its receipt and `flint deps audit` show the waiver "
            ~ "and its reason.",
            "[unchecked]\nlegacy-xml = \"vendored parser pending a Flint port\""),

    CodeInfo("FLINT-E0314", ExitCode.dependency, "DUB package version not in the compatibility index",
            "Third-party DUB packages are used through the curated compatibility index (policy/dub-index.toml), "
            ~ "which pins each version's repository, tag commit, tree hash, licence, DUB dependencies and native "
            ~ "recipes. A version it does not list cannot be resolved reproducibly.",
            "[dependencies]\n\"dub:tinyendian\" = \"0.2.0\""),
    CodeInfo("FLINT-E0315", ExitCode.dependency, "two versions of one DUB package",
            "Two requesters need different versions of the same DUB package. Flint never picks one silently; the "
            ~ "message names both requesters and both versions.", "require the same version in both places"),
    CodeInfo("FLINT-E0316", ExitCode.user, "DUB package fails the safety checks",
            "Flint runs its D safety rules (module @safe: defaults, @trusted confinement and SAFETY rationale, "
            ~ "string mixins) over a DUB package's sources. A package that fails them is used only under an "
            ~ "[unchecked] waiver that names it and gives a reason; the waiver appears in every build, its receipt, "
            ~ "the SBOM and flint deps audit.",
            "[unchecked]\n\"dub:dyaml\" = \"YAML parsing until flint:serde " ~ "reads YAML\""),

    CodeInfo("FLINT-E0318", ExitCode.dependency, "native package not in Flint's recipe index",
            "[native] packages resolve only against Flint's checked-in recipe index (native/conan-index), whose "
            ~ "recipes pin the source archives, hashes, licences and build flags of policy/native-lock.json. Nothing "
            ~ "outside it is fetched.",
            "[native]\nzlib = \"1.4\""),
    CodeInfo("FLINT-E0320", ExitCode.dependency, "two versions of one native package",
            "Two requesters (the project, a dependency's [native], or an indexed DUB package) need different versions "
            ~ "of the same native library. The build fails and names both; flint never picks one.",
            "require the same version in both places"),
    CodeInfo("FLINT-E0321", ExitCode.dependency,
            "system library unavailable",
            "`system = true` takes the host's library through pkg-config, and marks the build non-portable. "
            ~ "pkg-config does not know the library, or the host's version is older than the one written.",
            "install the library's development package, or remove `system = true` to build Flint's pinned recipe"),

    // 04xx: project layout and module paths.
    CodeInfo("FLINT-E0401", ExitCode.user, "module name does not match its file path",
            "Module paths must match file paths under src/ and test/, so a reader can find any module from its "
            ~ "name. `src/shop/order/service.d` declares `module shop.order.service;` and `package.d` names its "
            ~ "directory.",
            "// src/shop/order/service.d\nmodule shop.order.service;"),
    CodeInfo("FLINT-E0402", ExitCode.user, "module declaration missing or unreadable",
            "Every source file starts with an explicit `module` declaration. The policy lexer also rejects token "
            ~ "strings (q{...}) and unterminated literals, whose contents it cannot check.",
            "module shop.app;\n\n@safe:"),
    CodeInfo("FLINT-E0403", ExitCode.user, "module outside the project's module root",
            "The first segment of every module is the project's module root (its name with hyphens replaced by "
            ~ "underscores), and sources live in src/<root>/ and test/<root>/.", "src/shop/app.d -> module shop.app;"),
    CodeInfo("FLINT-E0404", ExitCode.user, "source file outside the project layout",
            "D sources live under src/<root>/ (the application) and test/<root>/ (tests mirroring src/). Other "
            ~ "top-level directories are config/, resources/, native/ and .flint/.",
            "mkdir -p src/shop && git mv app.d src/shop/app.d"),
    CodeInfo("FLINT-E0405", ExitCode.user, "reserved module root",
            "The module root `flint` belongs to the Flint core libraries, and D keywords cannot be module names.",
            "name = \"flint-tool\"    # module root flint_tool"),
    CodeInfo("FLINT-E0406", ExitCode.user, "module file and package directory both exist",
            "A module with children uses name/package.d, never both name.d and a name/ directory.",
            "git mv src/shop/order.d src/shop/order/package.d"),
    CodeInfo("FLINT-E0407", ExitCode.user, "configuration file outside the convention",
            "Configuration has one shape: config/application.toml plus config/application-<profile>.toml. Flint "
            ~ "projects use TOML only; YAML is not offered because of its implicit typing.",
            "config/application.toml\nconfig/application-prod.toml"),
    CodeInfo("FLINT-E0408", ExitCode.user, "generated code outside .flint/generated",
            "Generated code is rebuilt from its inputs into .flint/generated/ and never committed.",
            "git rm -r generated/ && echo .flint/ >> .gitignore"),
    CodeInfo("FLINT-E0409", ExitCode.user, ".flint/ is not ignored by git",
            ".flint/ holds caches, receipts and generated code. It must be listed in .gitignore.",
            "echo .flint/ >> .gitignore"),
    CodeInfo("FLINT-E0410", ExitCode.user, "source belongs to another package",
            "In the Flint workspace, every module under packages/<name>/source belongs to that package's module root "
            ~ "from policy/packages.json.", "packages/log/source/flint/log/sinks.d -> module flint.log.sinks;"),

    // 05xx: safety rules.
    CodeInfo("FLINT-E0501", ExitCode.user,
            "module-scope @safe: missing",
            "Every module declares `@safe:` before its first declaration (only imports may precede it). Raw FFI "
            ~ "modules in an allowlisted sys/ or ffi/ directory may declare `@system:` instead.",
            "module shop.app;\n\nimport std.stdio : writeln;\n\n@safe:"),
    CodeInfo("FLINT-E0502", ExitCode.user, "unsafe annotation outside a sys/ or ffi/ module",
            "`@trusted` and `@system` are confined to low-level modules: <root>.sys.* and <root>.ffi.* in a project, "
            ~ "or the prefixes policy/safety-policy.json allows in the Flint workspace.",
            "move the function into src/shop/sys/clock.d and give it a // SAFETY: rationale"),
    CodeInfo("FLINT-E0503", ExitCode.user, "@trusted without an adjacent SAFETY rationale",
            "Every @trusted function has a `// SAFETY:` comment on the two lines above it explaining ownership, "
            ~ "bounds and lifetime. The comment does not prove safety; it lets a reviewer check it.",
            "// SAFETY: the buffer is owned by the caller and outlives the call; length is checked above.\n"
            ~ "private int readInto(ubyte[] buffer) @trusted"),
    CodeInfo("FLINT-E0504", ExitCode.user,
            "@trusted scope or block",
            "Trusting a whole scope (`@trusted:` or `@trusted { ... }`) is prohibited. Mark individual functions.",
            "// SAFETY: ...\nprivate void one() @trusted { }"),
    CodeInfo("FLINT-E0505", ExitCode.user, "@trusted function too long",
            "A @trusted function body is at most 60 source lines, so its safety argument stays reviewable.",
            "split the function: keep only the unsafe operation in the @trusted part"),
    CodeInfo("FLINT-E0506", ExitCode.user, "string mixin outside an approved generator",
            "String mixins are allowed only in registered generator modules (policy/safety-policy.json). "
            ~ "Application code applies UDAs and calls documented template APIs.",
            "use the framework's UDA or template API instead of mixin(...)"),
    CodeInfo("FLINT-E0507", ExitCode.user, "import of an undeclared dependency",
            "A direct import requires a direct dependency, even when another dependency already exposes the module.",
            "[dependencies]\n\"flint:log\" = {}"),
    CodeInfo("FLINT-E0508", ExitCode.user, "import across a private package boundary",
            "internal/, sys/ and ffi/ modules of another package are private. Import the package's public modules.",
            "import flint.log : Logger;     // not flint.log.sys.sinks"),
    CodeInfo("FLINT-E0509", ExitCode.user, "heavy import in a core module",
            "Tier-0 and tier-1 packages and BetterC packages may not import `std`, `std.algorithm`, `std.range` or "
            ~ "`std.regex`.", "import core.stdc.string : memcpy;"),
    CodeInfo("FLINT-E0510", ExitCode.user, "unknown Flint module",
            "The import names a `flint.*` module that no core package owns.", "import flint.config : load;"),
    CodeInfo("FLINT-E0511", ExitCode.user, "generated code breaks the rules",
            "Mixin expansions may not contain import declarations or unsafe annotations, and compiler-generated "
            ~ "imports obey the same dependency rules as written ones.",
            "generate data, not imports; keep @trusted code in handwritten sys/ modules"),
    CodeInfo("FLINT-E0512", ExitCode.user, "unbalanced @trusted body",
            "The policy lexer could not find the end of a @trusted function body.",
            "check the braces of the function the location points at"),
    CodeInfo("FLINT-E0513", ExitCode.user, "C reached outside an ffi module", ffiExplanation, ffiExample),
    CodeInfo("FLINT-E0514", ExitCode.user, "module-level thread-local mutable variable",
            "A module-level mutable variable is thread-local in D, so task fibers that interleave on one thread "
            ~ "share it. Per-task state lives in FiberLocal!T; process state is shared or immutable. Reviewed "
            ~ "thread roots are listed in policy/safety-policy.json (ADR-030).",
            "private shared FiberLocal!SecurityContext context;"),

    // 052x: workspace structure (the structural gate).
    CodeInfo("FLINT-E0521", ExitCode.user, "dependency cycle in the package graph",
            "policy/packages.json is a directed acyclic graph.", "remove one edge of the cycle"),
    CodeInfo("FLINT-E0522", ExitCode.user, "dependency on a higher tier",
            "A package may depend only on packages of its own or a lower tier.",
            "move the shared code down a tier"),
    CodeInfo("FLINT-E0523", ExitCode.user, "CLI packages may not depend on web or data packages",
            "Tier-4 CLI/TUI packages stay independent of the tier-2 web and tier-3 data stacks.",
            "compose them in the application instead"),
    CodeInfo("FLINT-E0524", ExitCode.user, "root dub.sdl subpackages differ from policy",
            "The root dub.sdl lists exactly the packages in policy/packages.json.",
            "subPackage \"packages/<name>\""),
    CodeInfo("FLINT-E0525", ExitCode.user, "package dependencies differ from policy",
            "Each package's dub.sdl declares exactly the dependencies policy/packages.json allows.",
            "dependency \"flint:arena\" version=\"*\""),
    CodeInfo("FLINT-E0526", ExitCode.user, "noncanonical dependency recipe",
            "Package recipes declare Flint dependencies only, in the canonical `version=\"*\"` form.",
            "dependency \"flint:arena\" version=\"*\""),
    CodeInfo("FLINT-E0527", ExitCode.user, "compiler dependency audit failed",
            "Packages with approved string mixins are compiled with DMD -deps and -mixin in debug and release "
            ~ "profiles, and every expansion and compiler-generated import is audited. The compile failed or "
            ~ "produced no expansion.",
            "add a positive unittest that instantiates the generator"),

    // 06xx: formatting and lint.
    CodeInfo("FLINT-E0528", ExitCode.user, "a starter contains D source",
            "A starter is a dependency bundle and a configuration section, as a Spring Boot starter is (ADR-029). "
            ~ "Behaviour belongs in a framework library, the programming model, or in a Flint Boot library under "
            ~ "boot/, the wiring and defaults. Only a starter's example/ project may hold D source.",
            "starters/web/dub.sdl:\n  targetType \"none\"\n"
            ~ "  dependency \"flint:boot-autoconfigure-web\" version=\"*\""),
    CodeInfo("FLINT-E0529", ExitCode.user, "an undeclared Boot-layer import",
            "A Flint Boot library may import only what policy/boot.json declares for it, which keeps the "
            ~ "direction framework libraries -> flint:boot -> auto-configuration -> starters. Framework libraries "
            ~ "never import Boot.",
            "policy/boot.json:\n  \"boot-autoconfigure-web\": { \"dependencies\": " ~ "[\"web\", \"boot\"] }"),
    CodeInfo("FLINT-E0530", ExitCode.user, "a class-typed field may be null",
            "A field whose type is a class or interface the project declares is null until something assigns it. "
            ~ "Every constructor of the aggregate must assign it, as constructor injection does; a value without "
            ~ "identity belongs in a struct. A field with no constructor, or initialised to null, is flagged.",
            "@RestController(\"/api/orders\")\nstruct OrderController\n{\n    private OrderService orders;\n    "
            ~ "this(OrderService orders) { this.orders = orders; }\n}"),
    CodeInfo("FLINT-E0531", ExitCode.user, "an attribute the framework makes unneeded",
            "In an application that uses a starter, flint:web picks where a controller runs from its handlers: on "
            ~ "the reactor when every handler is nothrow @nogc, otherwise on a worker thread. `nothrow` or `@nogc` on "
            ~ "some handlers of a worker-thread controller changes nothing, and `scope` on an argument the framework "
            ~ "passes as an owned value is noise. `flint check` reports the attributes per handler.",
            "@Get(\"/:id\")\nResult!Order get(@PathVariable(\"id\") ulong id)\n{\n    return orders.find(id);\n}"),
    CodeInfo("FLINT-E0532", ExitCode.user, "a dependency crosses repos the wrong way",
            "After the repo split each flint:* package lives in one repo (the `repo` field of policy/packages.json "
            ~ "and policy/boot.json). Dependencies point only from portfolio repos to boot, framework and flint, as "
            ~ "policy/repos.json lists; an edge the coordinator is still deciding is listed under pending_edges.",
            "policy/repos.json:\n  \"framework\": { \"may_depend_on\": [\"flint\"] }"),
    CodeInfo("FLINT-E0601", ExitCode.user, "source is not formatted",
            "One formatter: dfmt 0.15.2 with the repository's dfmt.ini. `flint check` compares its output byte for "
            ~ "byte.", "flint fmt"),
    CodeInfo("FLINT-E0602", ExitCode.user, "D-Scanner finding",
            "D-Scanner 0.15.2 with dscanner.ini reports a warning or error.",
            "fix the reported line; the message names the check"),
    CodeInfo("FLINT-E0603", ExitCode.user, "clang-tidy finding",
            "`flint check` runs the pinned clang-tidy over embedded C with the fixed profile in "
            ~ "policy/native-c.toml (bugprone, cert, clang-analyzer, performance and portability checks). "
            ~ "Every finding is an error.",
            "fix the reported line; the message names the check"),

    // 07xx: build, test and run.
    CodeInfo("FLINT-E0701", ExitCode.user, "build failed",
            "The compiler or linker rejected the code. The compiler's own messages follow the diagnostic.",
            "flint build --verbose"),
    CodeInfo("FLINT-E0702", ExitCode.user, "tests failed",
            "A unittest failed or the test binary exited with a nonzero status.",
            "flint test --verbose"),
    CodeInfo("FLINT-E0703", ExitCode.user, "the program exited with a failure status",
            "`flint run --json` ran the program; it failed or was killed.", "flint run -- --help"),
    CodeInfo("FLINT-E0704", ExitCode.user, "the build produced no artifact",
            "DUB reported success but the expected executable or library is missing.",
            "flint build --verbose"),
    CodeInfo("FLINT-E0705", ExitCode.user, "package has no implementation sources",
            "Source-free packages are failures, never passes.", "implement the package's public modules"),
    CodeInfo("FLINT-E0706", ExitCode.user, "interrupted",
            "The command was interrupted; running children were stopped.", "run the command again"),
    CodeInfo("FLINT-E0707", ExitCode.user, "nothing to run",
            "`flint run` needs an executable project.", "[project]\ntype = \"executable\""),
    CodeInfo("FLINT-E0708", ExitCode.user, "embedded C failed to compile",
            "The pinned clang compiles native/ (or [native.c] sources) as C11 or C17 with -Wall -Wextra -Werror, "
            ~ "_FORTIFY_SOURCE=3, the stack protector, stack-clash protection and zero-initialised automatic "
            ~ "variables (policy/native-c.toml). Warnings are errors.",
            "flint build --verbose"),

    CodeInfo("FLINT-E0709", ExitCode.user, "only executables are packaged",
            "`flint package` builds and packages an executable project. Libraries are published as repositories "
            ~ "with release tags and consumed by repository path.", "[project]\ntype = \"executable\""),
    CodeInfo("FLINT-E0710", ExitCode.user, "a scratch image needs a static executable",
            "`flint package --container` writes a FROM scratch image, which has no C library or loader, so the "
            ~ "executable must be fully static: the linux-x86_64-musl target.",
            "flint package --container --target linux-x86_64-musl"),
    CodeInfo("FLINT-E0711", ExitCode.user, "the packaged executable is not static",
            "Packages link Flint, the D runtime and native packages statically; only the C library of a glibc "
            ~ "target is shared, and musl targets are fully static. The executable needs another shared library "
            ~ "or a loader.",
            "[native]\nzlib = { version = \"1.3.1\", linkage = \"bundled\" }   # ships lib/ with an rpath"),

    // 08xx: toolchain and environment.
    CodeInfo("FLINT-E0801", ExitCode.environment, "Flint installation not found",
            "flint finds its installation (policy/, packages/, toolchain/) by walking up from its own executable, or "
            ~ "from FLINT_HOME.", "export FLINT_HOME=/path/to/flint"),
    CodeInfo("FLINT-E0802", ExitCode.environment, "toolchain component missing",
            "A pinned compiler, DUB or tool is not installed in the toolchain directory.",
            "flint toolchain install"),
    CodeInfo("FLINT-E0803", ExitCode.environment, "toolchain version mismatch",
            "An installed component reports a version other than the one pinned in policy/toolchains.json.",
            "flint toolchain install"),
    CodeInfo("FLINT-E0804", ExitCode.environment, "toolchain receipt missing",
            "The forked DMD and DUB can be traced to the patches in toolchain/ only through the receipt "
            ~ "`flint toolchain install` writes. Without it the build is non-canonical.", "flint toolchain install"),
    CodeInfo("FLINT-E0805", ExitCode.environment, "toolchain fork patches changed",
            "The installed DMD or DUB was built from different fork patches than the ones in toolchain/.",
            "flint toolchain install"),
    CodeInfo("FLINT-E0806", ExitCode.environment, "toolchain binary differs from its receipt",
            "An installed binary's SHA-256 differs from the one recorded when it was installed.",
            "flint toolchain install"),
    CodeInfo("FLINT-E0807", ExitCode.environment, "quality tool missing",
            "dfmt and D-Scanner 0.15.2 are installed into .tools/bin by tools/install_quality_tools.py.",
            "python3 tools/install_quality_tools.py"),
    CodeInfo("FLINT-E0808", ExitCode.environment, "native providers not installed",
            "Packages that link C providers need the native install receipt for this target under .native/install. "
            ~ "Pure-D packages build without it.",
            "python3 tools/native_build.py --profile ci --target linux-x86_64-glibc --phase build --emit-dub"),
    CodeInfo("FLINT-E0809", ExitCode.environment, "policy file invalid",
            "A file under policy/ that flint reads is missing or does not match its schema.",
            "git checkout -- policy/"),
    CodeInfo("FLINT-E0810", ExitCode.environment, "compile server unavailable",
            "The compile server did not start or is disabled. Builds still work, more slowly.",
            "unset FLINT_DMD_SERVER && flint daemon start"),
    CodeInfo("FLINT-E0811", ExitCode.environment, "environment overrides the canonical build",
            "A variable such as DFLAGS, FLINT_DMD_SERVER=0 or FLINT_DUB_PIPELINE=0 changes builds. flint clears "
            ~ "DFLAGS for its own builds and records the rest in receipts.",
            "unset DFLAGS FLINT_DMD_SERVER FLINT_DUB_PIPELINE"),
    CodeInfo("FLINT-E0812", ExitCode.environment, "PATH selects a different toolchain",
            "The dmd, dub or ldc2 first on PATH is not the pinned one. flint always uses the pinned toolchain; "
            ~ "commands you run by hand may not.",
            "export PATH=\"$FLINT_HOME/.tools/dmd2/linux/bin64:$PATH\""),
    CodeInfo("FLINT-E0813", ExitCode.environment,
            "source identity unknown",
            "git is unavailable or the project is not a repository, so receipts cannot name the source commit.",
            "git init && git add -A && git commit -m initial"),
    CodeInfo("FLINT-E0814", ExitCode.environment, "toolchain installation failed",
            "The pinned installer (tools/install_toolchains.py) failed. Its output follows the diagnostic.",
            "flint toolchain install --plan    # shows the exact commands"),

    CodeInfo("FLINT-E0815", ExitCode.environment, "fixture peer unavailable",
            "A package declares fixture peers in policy/test-peers.toml (ADR-018). A peer's pinned binary is missing "
            ~ "or has no pinned release, so the package's offline tests ran but its peer-dependent suites did not. "
            ~ "The run fails instead of skipping them silently.",
            "python3 tools/install_peers.py --peer go --peer postgres"),
    CodeInfo("FLINT-E0816", ExitCode.environment, "C toolchain missing",
            "Embedded C, clang-tidy and `flint test --sanitize` use the pinned LLVM release (and, for "
            ~ "sanitizers, the sanitizer-aware LDC runtime) under the toolchain directory; a host compiler is "
            ~ "never used.",
            "flint toolchain install                # add --sanitizers for flint test --sanitize"),
    CodeInfo("FLINT-E0817", ExitCode.environment, "target unavailable",
            "`flint package --target` builds for the host target natively and, on Linux x86-64, for "
            ~ "linux-x86_64-musl by cross-linking with the pinned clang, the Alpine LDC runtime and the pinned musl "
            ~ "sysroot. Other targets build on their own runners.", "flint toolchain install --musl"),
    CodeInfo("FLINT-E0818", ExitCode.environment, "native package engine missing",
            "Native packages are resolved and built by Flint's pinned, checksum-verified native engine, which "
            ~ "`flint toolchain install` installs with an isolated home and Flint's recipe index as its only source.",
            "flint toolchain install"),
    CodeInfo("FLINT-E0819", ExitCode.environment, "native package failed to build",
            "A native package failed to build from its pinned source with the pinned toolchain. The message names "
            ~ "the package and the log; the engine's own output is never shown.", "flint build --verbose"),
    CodeInfo("FLINT-E0820", ExitCode.environment, "DUB cannot load libcurl",
            "DUB downloads from code.dlang.org through Phobos' std.net.curl, which loads libcurl at run time "
            ~ "(libcurl.so.4 and its variants). On hosts whose loader does not search libcurl's directory, NixOS for "
            ~ "example, every `dub fetch` fails although curl itself works. flint's builds never download, but "
            ~ "`flint toolchain install` fetches the pinned dfmt and D-Scanner sources with DUB.",
            "export LD_LIBRARY_PATH=\"$(nix-build '<nixpkgs>' -A curl.out --no-out-link)/lib\"   # NixOS"),
    CodeInfo("FLINT-E0821", ExitCode.environment, "dmd.conf breaks under a path with spaces",
            "DMD expands %@P% (the directory of dmd.conf) before it splits DFLAGS at whitespace. A toolchain installed "
            ~ "before tools/install_toolchains.py quoted those arguments fails every DMD build once its path contains "
            ~ "a space. Reinstalling quotes them; nothing else changes.", "flint toolchain install"),
    CodeInfo("FLINT-E0822", ExitCode.environment, "no debugger",
            "`flint run --debug` starts gdb, or lldb when gdb is missing, with Flint's pretty-printers "
            ~ "(tools/debug/flint_gdb.py, flint_lldb.py). Neither debugger is on PATH.",
            "sudo apt-get install gdb      # or: xcode-select --install for lldb"),
    // 09xx: receipts.
    CodeInfo("FLINT-E0901", ExitCode.environment, "receipt missing",
            "Every artifact flint builds has a JSON receipt next to it (<artifact>.receipt.json).",
            "flint build"),
    CodeInfo("FLINT-E0902", ExitCode.environment, "artifact differs from its receipt",
            "The artifact's SHA-256 differs from the receipt's, so it was modified or replaced after the build.",
            "flint build"),
    CodeInfo("FLINT-E0903", ExitCode.environment, "toolchain differs from the receipt",
            "The receipt records a different compiler, DUB or patch identity than the current toolchain.",
            "flint build      # rebuild with the current toolchain"),
    CodeInfo("FLINT-E0904", ExitCode.environment, "non-canonical input refused",
            "The receipt marks the artifact non-canonical (extra flags, profile overrides or an unverified "
            ~ "toolchain); measurement and verification refuse it.",
            "flint build --profile release      # without --dflags or [profile] overrides"),
    CodeInfo("FLINT-E0905", ExitCode.environment, "receipt malformed",
            "The receipt is not valid JSON of the flint.receipt/1 schema.", "flint build"),
    // 10xx: API manifests of the Spring port (ADR-030).
    CodeInfo("FLINT-E1001", ExitCode.user, "a Java source file did not parse",
            "`flint api extract` reads Java declarations: types, their members and annotations. It skips method "
            ~ "bodies and initializers by balanced brackets. A file whose declarations it cannot follow is left out "
            ~ "of the manifest, so the manifest is incomplete until the parser handles the construct.",
            "flint api extract --source ~/.flint/cache/api/spring-framework-v7.1.0 --project spring-framework "
            ~ "--version v7.1.0"),
    CodeInfo("FLINT-E1002", ExitCode.user, "API elements are unclassified",
            "Every type, method, constructor, field, enum constant, annotation attribute and record component of "
            ~ "an upstream manifest must be classified in api/mapping.json: ported (with its D symbol), adapted "
            ~ "(with the rulebook rules R1-R14 it follows) or excluded (with a rulebook category).",
            `"org.springframework.http.HttpStatus": ` ~ `{"status": "ported", "d": "flint.http.HttpStatus"}`),
    CodeInfo("FLINT-E1003", ExitCode.user, "the API mapping is invalid",
            "api/mapping.json has the shape docs/spring/api-mapping.md describes. A ported element needs its D "
            ~ "symbol `d` under `flint.`, an adapted one its `rules` (R1 to R14), an excluded one a rulebook "
            ~ "`category`, and a deferred one its `phase`. The mapping's `rulebook` must be the rulebook's current "
            ~ "version, and its `upstream` list must name each manifest classified.",
            `"org.springframework.jmx.**": ` ~ `{"status": "excluded", "category": "jvm-platform"}`),
    CodeInfo("FLINT-E1004", ExitCode.usage,
            "API input missing or malformed",
            "A source tree, manifest (flint.api-manifest/1) or pin file (api/upstreams.json, "
            ~ "flint.api-upstreams/1) named on the command line or in the Flint home cannot be read.",
            "flint api fetch spring-boot\nflint api extract --source DIR --project spring-boot --version v4.2.0"),
    CodeInfo("FLINT-E1005", ExitCode.dependency,
            "an upstream archive cannot be fetched",
            "`flint api fetch` downloads each archive pinned in api/upstreams.json, verifies its SHA-256 and "
            ~ "unpacks it into the reference cache. The download failed, the digest differs from the pin, or the "
            ~ "archive did not unpack. A digest mismatch is never ignored: re-pin only after checking the upstream.",
            "flint api fetch spring-framework\nFLINT_CACHE=/tmp/cache flint api fetch"),
];
