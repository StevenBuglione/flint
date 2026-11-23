/// `flint generate`: the canonical shape of each component, so people and agents never invent structure (ADR-021
/// sections 2 and 6, ADR-027). Output is deterministic for the same inputs.
module flint_tool.project.generators;

@safe:

/// The generators.
immutable string[] generatorKinds = [
    "entity", "repository", "service", "controller", "config", "migration", "agents", "debug"
];

/// One generated file.
struct GeneratedFile
{
    /// Path relative to the project.
    string path;
    /// Content.
    string content;
}

/// What a generator produces: files and the core packages they need.
struct Generation
{
    /// New files.
    GeneratedFile[] files;
    /// Core packages to add to [dependencies], without the `flint:` prefix.
    string[] packages;
    /// What to do next, in one line.
    string next;
}

/// Whether `name` is a PascalCase type name.
bool validTypeName(string name)
{
    if (name.length == 0 || !(name[0] >= 'A' && name[0] <= 'Z'))
        return false;
    foreach (ch; name)
    {
        if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')))
            return false;
    }
    return true;
}

/// `OrderItem` → `order_item`: the feature folder and module segment.
string snakeCase(string name)
{
    string text;
    foreach (i, ch; name)
    {
        if (ch >= 'A' && ch <= 'Z')
        {
            if (i > 0)
                text ~= '_';
            text ~= cast(char)(ch + 32);
        }
        else
            text ~= ch;
    }
    return text;
}

/// `Order` → `orders`, the resource path segment.
string plural(string snake)
{
    import std.algorithm.searching : endsWith;

    if (snake.endsWith("s") || snake.endsWith("x") || snake.endsWith("ch") || snake.endsWith("sh"))
        return snake ~ "es";
    if (snake.endsWith("y") && snake.length > 1 && "aeiou".indexOfChar(snake[$ - 2]) < 0)
        return snake[0 .. $ - 1] ~ "ies";
    return snake ~ "s";
}

private ptrdiff_t indexOfChar(string text, char ch)
{
    foreach (i, item; text)
    {
        if (item == ch)
            return i;
    }
    return -1;
}

/// Produce `kind` for `name` in a project whose module root is `root`. `nextMigration` is the next free migration
/// number and `existing` lists the project's files (to connect a service to an existing repository).
Generation generate(string kind, string name, string root, long nextMigration, scope const(string)[] existing)
{
    import std.algorithm.searching : canFind;
    import std.format : format;

    const feature = snakeCase(name);
    const base = "src/" ~ root ~ "/" ~ feature ~ "/";
    const module_ = root ~ "." ~ feature;
    Generation result;
    switch (kind)
    {
    case "entity":
        result.files = [GeneratedFile(base ~ feature ~ ".d", entity(name, module_, feature))];
        result.packages = ["arena", "engine-data", "serde", "validate"];
        result.next = "flint generate repository " ~ name;
        break;
    case "repository":
        result.files = [GeneratedFile(base ~ "repository.d", repository(name, module_, feature))];
        result.packages = ["engine-data", "engine-di"];
        result.next = "flint generate service " ~ name;
        break;
    case "service":
        result.files = [
            GeneratedFile(base ~ "service.d", service(name, module_, existing.canFind(base ~ "repository.d")))
        ];
        result.packages = ["arena", "engine-di", "engine-web"];
        result.next = "flint generate controller " ~ name;
        break;
    case "controller":
        result.files = [GeneratedFile(base ~ "controller.d", controller(name, module_, feature))];
        result.packages = ["arena", "validate", "engine-web"];
        result.next = "register " ~ name
            ~ "Controller in the AppContext and the Application struct of src/" ~ root ~ "/app.d";
        break;
    case "config":
        result.files = [GeneratedFile(base ~ "properties.d", properties(name, module_, feature))];
        result.packages = ["config"];
        result.next = "add a [" ~ feature ~ "] table to config/application.toml and load!" ~ name
            ~ "Properties at startup";
        break;
    case "migration":
        result.files = [
            GeneratedFile(format("resources/migrations/V%06d__%s.sql", nextMigration, feature),
                    migration(name, feature))
        ];
        result.packages = ["engine-migrate", "engine-sql"];
        result.next = "apply it with flint.engine.migrate's migrate at startup; it runs once, in version order";
        break;
    default:
        break;
    }
    return result;
}

/// Replace each `{key}` of a template.
private string fill(string text, scope const string[2][] values)
{
    import std.array : replace;

    string result = text;
    foreach (pair; values)
        result = result.replace("{" ~ pair[0] ~ "}", pair[1]);
    return result;
}

private string[2][] names(string name, string module_, string feature)
{
    return [
        ["Name", name], ["module", module_], ["feature", feature], ["features", plural(feature)]
    ];
}

private enum entityTemplate = `/// The {Name} entity: its table row and its JSON representation.
module {module}.{feature};

import flint.arena : Text;
import flint.engine.data : Column, Id, Table;
import flint.serde : JsonName;
import flint.validate : NotBlank;

@safe:

/// One {feature} row; text belongs to the current request arena.
@Table("{features}")
struct {Name}
{
    /// Database primary key.
    @Id
    ulong id;
    /// Required name.
    @Column("name")
    @JsonName("name")
    @NotBlank
    Text name;
}
`;

private enum repositoryTemplate = `/// Persistence of {Name} rows: the repository contract and its SQL implementation.
module {module}.repository;

import {module}.{feature} : {Name};
import flint.engine.data : CrudRepository, SqlRepository;
import flint.engine.di : BeanRegistrar, Bind;

@safe:

/// The repository contract services depend on.
alias {Name}Repository = CrudRepository!({Name}, ulong);

/// Binds the contract to the SQL implementation for the AppContext.
alias {Name}Bindings = BeanRegistrar!(Bind!({Name}Repository, SqlRepository!({Name}, ulong)));
`;

private enum plainServiceTemplate = `/// {Name} business rules.
module {module}.service;

import flint.engine.di : Service;

@safe:

/// Constructor-injected application service.
@Service
final class {Name}Service
{
    /// Describe the service; replace with the feature's operations.
    string describe() const pure nothrow @nogc
    {
        return "{Name}Service";
    }
}
`;

private enum serviceTemplate = `/// {Name} business rules over the repository contract.
module {module}.service;

import {module}.{feature} : {Name};
import {module}.repository : {Name}Repository;
import flint.arena : Result;
import flint.engine.di : Service;
import flint.engine.web : RequestContext;

@safe:

/// Constructor-injected application service.
@Service
final class {Name}Service
{
    private {Name}Repository repository;

    /// Receive the registered repository implementation.
    this({Name}Repository repository)
    {
        this.repository = repository;
    }

    /// Find one row using the request arena and cancellation context.
    Result!{Name} find(ulong id, ref scope RequestContext context) nothrow @nogc
    {
        return repository.findById(id, context.arena, context.cancellation);
    }

    /// Persist a validated row.
    Result!{Name} create(scope const ref {Name} value, ref scope RequestContext context) nothrow @nogc
    {
        return repository.save(value, context.arena, context.cancellation);
    }
}
`;

private enum controllerTemplate = `/// HTTP routes of the {feature} resource.
module {module}.controller;

import {module}.{feature} : {Name};
import {module}.service : {Name}Service;
import flint.arena : Result;
import flint.validate : Valid;
import flint.engine.web : Get, PathVariable, Post, RequestBody, RequestContext, RestController;

@safe:

/// Compile-time route registration for /api/{features}.
@RestController("/api/{features}")
struct {Name}Controller
{
    /// Injected service.
    {Name}Service service;

    /// Receive the service from the AppContext.
    this({Name}Service service)
    {
        this.service = service;
    }

    /// Return one {feature} or the framework's error representation.
    @Get("/:id")
    Result!{Name} get(@PathVariable("id") ulong id, ref scope RequestContext context) nothrow @nogc
    {
        return service.find(id, context);
    }

    /// Validate and create one {feature}.
    @Post("")
    Result!{Name} post(@RequestBody @Valid scope const ref {Name} value,
            ref scope RequestContext context) nothrow @nogc
    {
        return service.create(value, context);
    }
}
`;

private enum propertiesTemplate = `/// Typed {feature} configuration, from [{feature}] in config/application*.toml.
module {module}.properties;

import flint.config : ConfigurationProperties, Default, Required;

@safe:

/// Settings under [{feature}]; unknown keys are errors.
@ConfigurationProperties("{feature}")
struct {Name}Properties
{
    /// Required endpoint.
    @Required
    string endpoint;
    /// Timeout in milliseconds.
    @Default("5000")
    uint timeoutMillis;
}
`;

private enum migrationTemplate = `-- {Name}: applied once, in version order, by flint.engine.migrate.
-- Never edit an applied migration; add a new one (a changed checksum stops startup).
CREATE TABLE {features} (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);
`;

private string entity(string name, string module_, string feature)
{
    return fill(entityTemplate, names(name, module_, feature));
}

private string repository(string name, string module_, string feature)
{
    return fill(repositoryTemplate, names(name, module_, feature));
}

private string service(string name, string module_, bool withRepository)
{
    return fill(withRepository ? serviceTemplate : plainServiceTemplate, names(name, module_, snakeCase(name)));
}

private string controller(string name, string module_, string feature)
{
    return fill(controllerTemplate, names(name, module_, feature));
}

private string properties(string name, string module_, string feature)
{
    return fill(propertiesTemplate, names(name, module_, feature));
}

private string migration(string name, string feature)
{
    return fill(migrationTemplate, names(name, null, feature));
}

/// VS Code launch and task configurations: build with flint, debug the dev build with gdb and Flint's
/// pretty-printers (or lldb with its summaries).
GeneratedFile[] debugConfigs(string executable, string home)
{
    const printers = home ~ "/tools/debug";
    const launch = fill(launchTemplate, [["executable", executable], ["printers", printers]]);
    return [
        GeneratedFile(".vscode/launch.json", launch),
        GeneratedFile(".vscode/tasks.json", tasksTemplate)
    ];
}

private enum launchTemplate = `{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "flint: debug {executable} (gdb)",
            "type": "cppdbg",
            "request": "launch",
            "program": "${workspaceFolder}/.flint/build/dev/{executable}",
            "args": [],
            "cwd": "${workspaceFolder}",
            "MIMode": "gdb",
            "preLaunchTask": "flint build",
            "setupCommands": [
                { "text": "-enable-pretty-printing", "ignoreFailures": true },
                { "text": "source {printers}/flint_gdb.py", "ignoreFailures": false }
            ]
        },
        {
            "name": "flint: debug {executable} (lldb)",
            "type": "lldb",
            "request": "launch",
            "program": "${workspaceFolder}/.flint/build/dev/{executable}",
            "args": [],
            "cwd": "${workspaceFolder}",
            "preLaunchTask": "flint build",
            "initCommands": ["command script import {printers}/flint_lldb.py"]
        }
    ]
}
`;

private enum tasksTemplate = `{
    "version": "2.0.0",
    "tasks": [
        { "label": "flint build", "type": "shell", "command": "flint build", "group": "build",
          "problemMatcher": [] },
        { "label": "flint test", "type": "shell", "command": "flint test", "group": "test",
          "problemMatcher": [] },
        { "label": "flint watch", "type": "shell", "command": "flint watch", "isBackground": true,
          "problemMatcher": [] }
    ]
}
`;

/// AGENTS.md: the Flint way, for coding agents and people, specific to this project.
string agentsGuide(string name, string root, string type)
{
    return fill(agentsTemplate, [["name", name], ["root", root], ["type", type]]);
}

private enum agentsTemplate = `# {name}: working in a Flint project

This file is generated by ` ~ "`flint new` and `flint generate agents`" ~ `. It states the one Flint way to
build this {type}. Follow it instead of general D habits.

## Ask flint, not memory

- ` ~ "`flint docs <words>`" ~ ` searches the exact API of the pinned Flint libraries; `
    ~ "`flint docs flint.config.load`" ~ `
  shows a symbol with its signature and tested examples. ` ~ "`flint examples <topic>`" ~ ` shows compiled examples.
- ` ~ "`flint explain FLINT-Ennnn`" ~ ` explains any diagnostic with a correct example.
- ` ~ "`flint mcp`" ~ ` serves the same knowledge, and build, test and check, to MCP clients.
- Every command takes ` ~ "`--json`" ~ ` and never prompts. Exit codes: 0 ok, 1 your code, 2 environment,
  3 dependencies, 4 usage.

## The loop

` ~ "```sh" ~ `
flint build          # fast checks, then the dev build
flint test           # src/ and test/
flint check          # everything CI runs
flint fmt            # the one formatter
flint watch          # rebuild, retest or restart on every change
` ~ "```" ~ `

Fix the first error first: each has a code, a location and a fix line.

## Layout

- ` ~ "`flint.toml`" ~ ` is the only manifest; ` ~ "`flint.lock`" ~ ` is generated (`
    ~ "`flint lock`" ~ `), never edited.
- ` ~ "`src/{root}/`" ~ ` holds the code, package-by-feature: `
    ~ "`src/{root}/order/{order,repository,service,controller}.d`" ~ `.
  Module names match paths: ` ~ "`src/{root}/order/service.d`" ~ ` is ` ~ "`module {root}.order.service;`" ~ `.
- ` ~ "`test/{root}/`" ~ ` mirrors ` ~ "`src/`" ~ `. ` ~ "`config/application.toml`" ~ ` plus `
    ~ "`application-<profile>.toml`" ~ `
  is the only configuration (TOML, bound to ` ~ "`@ConfigurationProperties`" ~ ` structs).
- ` ~ "`resources/migrations/V000001__name.sql`" ~ ` are migrations; ` ~ "`native/`"
    ~ ` is embedded C, reached only from
  ` ~ "`src/{root}/ffi/`" ~ `.
- Create components with ` ~ "`flint generate entity|repository|service|controller|config|migration <Name>`" ~ `.
- ` ~ "`.flint/`" ~ ` is generated output. Never edit it, never commit it.

## Code

- Every module starts with ` ~ "`module ...;`" ~ ` then ` ~ "`@safe:`" ~ `. Builds use ` ~ "`-preview=dip1000`" ~ `.
- Errors are values: return ` ~ "`Result!T`" ~ ` or ` ~ "`flint.arena.Error`" ~ ` with a ` ~ "`Status`"
    ~ `; check ` ~ "`.ok`" ~ ` or ` ~ "`.code`" ~ `.
  Do not throw for expected failures, and do not ignore a returned error.
- Prefer structs; classes only for DI services (` ~ "`@Service final class`" ~ `). Inject through constructors.
- Use explicit selective imports: ` ~ "`import flint.config : load;`" ~ `. Never ` ~ "`import std;`" ~ `.
- Print errors with ` ~ "`flint.term.writeStream(Stream.error, text)`" ~ ` (` ~ "`std.stdio.stderr`" ~ ` is not @safe).
- Dependencies go in ` ~ "`flint.toml`" ~ ` (` ~ "`\"flint:engine-web\" = {}`" ~ `, a repository path with a version, or
  ` ~ "`\"dub:<name>\"`" ~ ` from the compatibility index), never a dub.sdl.

## Do not

- write ` ~ "`@trusted`" ~ ` or ` ~ "`extern(C)`" ~ ` outside ` ~ "`src/{root}/ffi/`" ~ ` (each `
    ~ "`@trusted`" ~ ` needs a ` ~ "`// SAFETY:`" ~ ` line);
- use string mixins, runtime reflection or your own framework: use the UDAs and templates Flint provides;
- add flags, ` ~ "`DFLAGS`" ~ ` or a second build tool: profiles live in ` ~ "`[profile.*]`"
    ~ ` and are recorded in receipts;
- edit generated files, ` ~ "`flint.lock`" ~ ` or anything under ` ~ "`.flint/`" ~ `;
- silence a check: a waiver (` ~ "`[[waivers]]`" ~ `, ` ~ "`[unchecked]`"
    ~ `) names the rule and gives a reason, and every
  build shows it.
`;
