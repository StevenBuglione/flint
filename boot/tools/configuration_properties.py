#!/usr/bin/env python3
"""Flint Boot's configuration properties: one spec, three outputs.

The `@ConfigurationProperties` classes of Boot's Phase 1 modules are Java Beans with dozens of fields each. This tool
holds their specification (field names, types, defaults and descriptions, taken from spring-boot v4.2.0's sources)
and renders:

1. the D classes (rulebook R6: Java's getter and setter names), under `boot/{core,module}/<module>/source/...`;
2. Boot's configuration metadata for each module, `META-INF/flint/flint-configuration-metadata.json`, in the
   format of Boot's `META-INF/spring-configuration-metadata.json` (groups, properties, hints);
3. a JSON Schema for `application.yaml` and `application-*.yaml`, `boot/configuration-metadata/application.schema.json`,
   which YAML editors use for completion and validation; keys are accepted under `flint.*` and `spring.*`.

    python3 boot/tools/configuration_properties.py --write   # regenerate every output
    python3 boot/tools/configuration_properties.py --check   # fail when a committed output differs

Descriptions are Boot's field Javadoc (Apache-2.0, attributed in each generated file's header).
"""
import argparse
import json
import os
import re
import sys
import textwrap

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
class F:
    def __init__(self, name, dtype, default, doc, ro=False, uda=None, setter=None, ctor=False, setter_body=None,
                 schema=None, throws=False):
        self.name, self.dtype, self.default, self.doc, self.ro, self.uda = name, dtype, default, doc, ro, uda
        # schema: the type the metadata and schema describe, when the D type is erased (Boot's
        # Map<SerializationFeature, Boolean> held as Map!(string, bool), so generated code shares one map type)
        self.schema = schema
        # setter: the D expression the setter stores, when Boot's setter does more than assign (cleanContextPath)
        self.setter = setter
        # ctor: the default is a run-time value (Boot's UUID password), assigned in the constructor
        self.ctor = ctor
        # setter_body: the setter's statements, when Boot's setter does more than store a value
        self.setter_body = setter_body
        # throws: the setter rejects a value with an exception, which the binder reports as a BindException
        self.throws = throws


class Enum:
    def __init__(self, name, doc, members):
        self.name, self.doc, self.members = name, doc, members


class Cls:
    def __init__(self, name, doc, fields, nested=(), enums=(), prefix=None, state=(), base=None, methods=()):
        self.name, self.doc, self.fields, self.nested, self.enums, self.prefix = name, doc, fields, list(nested), list(enums), prefix
        # state: private declarations that are not properties (no getter, setter or metadata), such as Boot's uniqueName
        self.state = list(state)
        # base: the class's base type (Boot's `implements`); methods: hand-written members appended after the
        # accessors, each a list of lines at the class body's indent
        self.base, self.methods = base, [list(m) for m in methods]


KEYWORDS = {'template', 'version', 'function', 'delegate', 'out', 'ref', 'in', 'body', 'module', 'scope', 'alias', 'enum'}


def field(name):
    return name + '_' if name in KEYWORDS else name


def cap(name):
    return name[0].upper() + name[1:]


def doc_lines(text, indent):
    pad = ' ' * indent
    return '\n'.join(pad + '/// ' + line for line in textwrap.wrap(text, 116 - indent))


def render_enum(e, indent):
    pad = ' ' * indent
    out = [doc_lines(e.doc, indent), f'{pad}enum {e.name}', f'{pad}{{']
    for i, (member, mdoc) in enumerate(e.members):
        out.append(doc_lines(mdoc, indent + 4))
        out.append(f'{pad}    {member}' + (',' if i + 1 < len(e.members) else ''))
    out.append(f'{pad}}}')
    return '\n'.join(out)


def render_class(c, indent=0, static=False):
    pad = ' ' * indent
    out = []
    if c.prefix:
        out.append(doc_lines(c.doc + f' Bound under `{c.prefix}` (Boot\'s `{c.prefix.replace("flint.", "spring.", 1)}` is accepted as an alias).' if c.prefix.startswith('flint.') else c.doc + f' Bound under `{c.prefix}`.', indent))
        out.append(f'{pad}@ConfigurationProperties("{c.prefix}")')
    else:
        out.append(doc_lines(c.doc, indent))
    out.append(f'{pad}{"static " if static else ""}final class {c.name}' + (f' : {c.base}' if c.base else ''))
    out.append(f'{pad}{{')
    body = []
    for e in c.enums:
        body.append(render_enum(e, indent + 4))
    for n in c.nested:
        body.append(render_class(n, indent + 4, static=True))
    fields = []
    for f in c.fields:
        init = '' if f.default is None or f.ro or f.ctor else f' = {f.default}'
        fields.append(f'{pad}    {f.uda + " " if f.uda else ""}private {f.dtype} {field(f.name)}{init};')
    fields += [f'{pad}    {decl}' for decl in c.state]
    if fields:
        body.append('\n'.join(fields))
    ros = [f for f in c.fields if f.ro or f.ctor]
    if ros:
        pure = '' if impure(c) else ' pure nothrow'
        ctor = [f'{pad}    /// Boot\'s defaults.', f'{pad}    this(){pure}', f'{pad}    {{']
        for f in ros:
            ctor.append(f'{pad}        {field(f.name)} = {f.default};')
        ctor.append(f'{pad}    }}')
        body.append('\n'.join(ctor))
    for f in c.fields:
        getter = ('is' if f.dtype == 'bool' else 'get') + cap(f.name)
        qual = ' const pure nothrow @nogc' if not f.ro and is_value(f.dtype) else ' pure nothrow @nogc'
        rtype = f.dtype
        body.append('\n'.join([doc_lines(f.doc, indent + 4), f'{pad}    {f.uda + " " if f.uda else ""}{rtype} {getter}(){qual}', f'{pad}    {{',
                               f'{pad}        return {field(f.name)};', f'{pad}    }}']))
        if not f.ro:
            statements = f.setter_body or [f'this.{field(f.name)} = {f.setter or field(f.name)};']
            body.append('\n'.join([f'{pad}    /// Set `{f.name}`.', f'{pad}    void set{cap(f.name)}({f.dtype} {field(f.name)})' + ('' if f.throws else ' pure nothrow @nogc'),
                                   f'{pad}    {{'] + [f'{pad}        {line}' if line else '' for line in statements] + [f'{pad}    }}']))
    for method in c.methods:
        body.append('\n'.join(f'{pad}    {line}' if line else '' for line in method))
    out.append('\n\n'.join(body))
    out.append(f'{pad}}}')
    return '\n'.join(out)


def is_container(dtype):
    """Whether a property of `dtype` needs a container descriptor (a map, an optional or an array)."""
    return dtype.startswith(('Map!', 'Optional!')) or dtype.endswith('[]')


BUILTIN_ELEMENTS = {'bool', 'int', 'long', 'string', 'Duration'}


def element_type(dtype):
    """The element type of an optional or array property type; None for maps (their keys and values are scalars)."""
    if dtype.startswith('Optional!('):
        return dtype[len('Optional!('):-1]
    if dtype.startswith('Optional!'):
        return dtype[len('Optional!'):]
    if dtype.endswith('[]'):
        return dtype[:-2]
    return None


def exported_types(items):
    """The D type expressions a unit's exporter describes: every class, nested class and enum it declares, then
    the container type of every field, as `typeof(Class.field)` so nested names resolve at module level."""
    types, containers = [], []

    def walk_class(c, path):
        types.append(path)
        for e in c.enums:
            types.append(f'{path}.{e.name}')
        for f in c.fields:
            if is_container(f.dtype):
                member = f'{path}.{field(f.name)}'
                containers.append((f.dtype, f'typeof({member})'))
                # The element type, when the binder needs its descriptor too (an enum, not a scalar or string).
                element = element_type(f.dtype)
                if element is not None and element not in BUILTIN_ELEMENTS:
                    access = '.init.get()' if f.dtype.startswith('Optional!') else '.init[0]'
                    containers.append((element, f'typeof({member}{access})'))
        for n in c.nested:
            walk_class(n, f'{path}.{n.name}')

    for item in items:
        if isinstance(item, Enum):
            types.append(item.name)
        else:
            walk_class(item, item.name)
    seen, unique = set(), []
    for dtype, expression in containers:
        if dtype not in seen:
            seen.add(dtype)
            unique.append(expression)
    return types + unique


def render_exporter(items):
    """The module's `flintAotDescriptors`: Flint AOT calls it instead of generating these descriptors, so their
    template instances compile once with the platform (aot-contract.md section 3; owner's template diet)."""
    entries = [f'        descriptorOf!({t})(),' for t in exported_types(items)]
    return '\n'.join([
        '/// Flint AOT\'s descriptors of this module\'s properties types and their container property types, compiled',
        '/// once with the platform instead of in each application\'s generated module (aot-contract.md section 3).',
        'imported!"flint.engine.aot.descriptor".Descriptor[] flintAotDescriptors()',
        '{',
        '    import flint.engine.aot.descriptor : descriptorOf;',
        '',
        '    return [',
    ] + entries + ['    ];', '}'])


def impure(c):
    """Whether `c`'s constructor runs run-time code (a `ctor` default, here or in a nested class it creates)."""
    nested = {n.name: n for n in c.nested}
    return any(f.ctor or (f.ro and f.dtype in nested and impure(nested[f.dtype])) for f in c.fields)


def is_value(dtype):
    if dtype.endswith('[]'):
        return False
    return dtype in ('bool', 'int', 'long', 'string', 'Duration') or dtype.startswith('Optional!') or dtype[0].isupper() and '!' not in dtype and dtype not in ('Map',)




def header(path, extra=''):
    return (f"// Ported from spring-boot v4.2.0: {path}\n"
            "// Copyright 2012-present the original author or authors.\n"
            "// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).\n"
            "// Modified by the Flint authors: Java Beans getters and setters are kept (rulebook R6); `spring.*` keys\n"
            "// become `flint.*` with `spring.*` accepted as an alias (ADR-030)" + (extra and '; ' + extra) + ".")


CP = 'import flint.boot.context.properties : ConfigurationProperties;'
OPT = 'import flint.java.util : Optional;'
DUR = 'import core.time : Duration;'
MAP = 'import flint.java.util : LinkedHashMap, Map;'
DU = 'import flint.boot.convert : ChronoUnit, DurationUnit;'

dbhealth = Cls('DataSourceHealthIndicatorProperties', 'External configuration properties for `DataSourceHealthIndicator`.', [
    F('ignoreRoutingDataSources', 'bool', 'false', 'Whether to ignore AbstractRoutingDataSources when creating database health indicators.'),
], prefix='management.health.db')

# ---- jdbc -----------------------------------------------------------------------------------------------------
datasource = Cls('DataSourceProperties', 'Base settings of the auto-configured `DataSource`.', [
    F('generateUniqueName', 'bool', 'true', 'Whether to generate a random datasource name (`generate-unique-name`, default true).'),
    F('name', 'string', None, 'Datasource name to use if "generate-unique-name" is false. Defaults to "testdb" when using an embedded database, otherwise null.'),
    F('type', 'string', None, 'Fully qualified name of the DataSource implementation to use. By default, a connection pool implementation is auto-detected from the build.'),
    F('driverClassName', 'string', None, 'Fully qualified name of the JDBC driver. Auto-detected based on the URL by default.'),
    F('url', 'string', None, 'JDBC URL of the database.'),
    F('username', 'string', None, 'Login username of the database.'),
    F('password', 'string', None, 'Login password of the database.'),
    F('embeddedDatabaseConnection', 'EmbeddedDatabaseConnection', 'EmbeddedDatabaseConnection.SQLITE', 'Connection details for an embedded database. Defaults to the most suitable embedded database available in the build: SQLite, which Flint\'s JDBC driver always provides.'),
    F('xa', 'Xa', 'new Xa', 'XA settings (`xa.*`).', ro=True),
], nested=[Cls('Xa', 'XA-specific datasource settings.', [
    F('dataSourceClassName', 'string', None, 'XA datasource fully qualified name.'),
    F('properties', 'Map!(string, string)', 'new LinkedHashMap!(string, string)', 'Properties to pass to the XA data source.', ro=True),
])], prefix='flint.datasource', state=['private string uniqueName; // generated once, by determineDatabaseName'])

jdbc = Cls('JdbcProperties', 'Settings of the auto-configured `JdbcTemplate`.', [
    F('template', 'Template', 'new Template', '`flint.jdbc.template.*`.', ro=True),
], nested=[Cls('Template', '`JdbcTemplate` settings.', [
    F('ignoreWarnings', 'bool', 'true', 'Whether to ignore JDBC statement warnings (SQLWarning). When set to false, throw an SQLWarningException instead.'),
    F('fetchSize', 'int', '-1', "Number of rows that should be fetched from the database when more rows are needed. Use -1 to use the JDBC driver's default configuration."),
    F('maxRows', 'int', '-1', "Maximum number of rows. Use -1 to use the JDBC driver's default configuration."),
    F('queryTimeout', 'Optional!Duration', None, "Query timeout. Default is to use the JDBC driver's default configuration. If a duration suffix is not specified, seconds will be used.", uda='@DurationUnit(ChronoUnit.SECONDS)'),
    F('skipResultsProcessing', 'bool', 'false', 'Whether results processing should be skipped. Can be used to optimize callable statement processing when we know that no results are being passed back.'),
    F('skipUndeclaredResults', 'bool', 'false', 'Whether undeclared results should be skipped.'),
    F('resultsMapCaseInsensitive', 'bool', 'false', 'Whether execution of a CallableStatement will return the results in a Map that uses case-insensitive names for the parameters.'),
])], prefix='flint.jdbc')

edc = Enum('EmbeddedDatabaseConnection', 'Connection details for embedded databases. Flint adds `SQLITE`, the embedded engine Flint ships; Boot\'s JVM engines keep their names.', [
    ('NONE', 'No connection.'), ('H2', 'H2 (JVM only; no Flint driver).'), ('DERBY', 'Derby (JVM only; no Flint driver).'),
    ('HSQLDB', 'HSQLDB (JVM only; no Flint driver).'), ('SQLITE', 'SQLite in memory: Flint\'s embedded database (Flint addition).')])


# ---- sql ------------------------------------------------------------------------------------------------------
mode = Enum('DatabaseInitializationMode', 'Whether a database should be initialized by scripts.', [
    ('ALWAYS', 'Always initialize the database.'), ('EMBEDDED', 'Only initialize an embedded database.'), ('NEVER', 'Never initialize the database.')])
sqlinit = Cls('SqlInitializationProperties', 'Settings of SQL database initialization.', [
    F('schemaLocations', 'string[]', None, 'Locations of the schema (DDL) scripts to apply to the database.'),
    F('dataLocations', 'string[]', None, 'Locations of the data (DML) scripts to apply to the database.'),
    F('platform', 'string', '"all"', 'Platform to use in the default schema or data script locations, schema-${platform}.sql and data-${platform}.sql.'),
    F('username', 'string', None, 'Username of the database to use when applying initialization scripts (if different).'),
    F('password', 'string', None, 'Password of the database to use when applying initialization scripts (if different).'),
    F('continueOnError', 'bool', 'false', 'Whether initialization should continue when an error occurs.'),
    F('separator', 'string', '";"', 'Statement separator in the schema and data scripts.'),
    F('encoding', 'string', None, 'Encoding of the schema and data scripts (a charset name).'),
    F('mode', 'DatabaseInitializationMode', 'DatabaseInitializationMode.EMBEDDED', 'Mode to apply when determining whether initialization should be performed.'),
], prefix='flint.sql.init')

# ---- transaction ----------------------------------------------------------------------------------------------
tx = Cls('TransactionProperties', 'Settings of the transaction managers.', [
    F('defaultTimeout', 'Optional!Duration', None, 'Default transaction timeout. If a duration suffix is not specified, seconds will be used.', uda='@DurationUnit(ChronoUnit.SECONDS)'),
    F('rollbackOnCommitFailure', 'Optional!bool', None, 'Whether to roll back on commit failures.'),
], prefix='flint.transaction', base='TransactionManagerCustomizer!AbstractPlatformTransactionManager', methods=[[
    '/// Apply the default timeout (in whole seconds) and rollback-on-commit-failure that are set.',
    'override void customize(AbstractPlatformTransactionManager transactionManager)',
    '{',
    '    if (defaultTimeout.isPresent())',
    '        transactionManager.setDefaultTimeout(cast(int) defaultTimeout.get().total!"seconds");',
    '    if (rollbackOnCommitFailure.isPresent())',
    '        transactionManager.setRollbackOnCommitFailure(rollbackOnCommitFailure.get());',
    '}']])

# ---- web server -----------------------------------------------------------------------------------------------
tomcatprops = Cls('TomcatServerProperties', "Tomcat server properties: only the keep-alive request limit, which Flint's engine applies as Tomcat does (owner 8163a833; Boot's class lives in spring-boot-tomcat).", [
    F('maxKeepAliveRequests', 'int', '100', 'Maximum number of HTTP requests that can be pipelined before the connection is closed. When set to 0 or 1, keep-alive and pipelining are disabled. When set to -1, an unlimited number of pipelined or keep-alive requests are allowed.'),
], prefix='server.tomcat')

server = Cls('ServerProperties', 'Settings of the embedded web server.', [
    F('port', 'Optional!int', None, 'Server HTTP port. The server factory uses 8080 when unset; 0 picks a free port.'),
    F('address', 'string', None, 'Network address to which the server should bind.'),
    F('serverHeader', 'string', None, 'Value to use for the Server response header (if empty, no header is sent).'),
    F('shutdown', 'Shutdown', 'Shutdown.GRACEFUL', 'Type of shutdown that the server will support.'),
    F('compression', 'Compression', 'new Compression', 'Response compression (`server.compression.*`).', ro=True),
    F('http2', 'Http2', 'new Http2', 'HTTP/2 (`server.http2.*`).', ro=True),
    F('servlet', 'Servlet', 'new Servlet', 'Servlet settings (`server.servlet.*`).', ro=True),
    F('flint', 'Flint', 'new Flint', "Flint servlet engine settings (`server.flint.*`), in place of Boot's `server.tomcat.*`.", ro=True),
], nested=[Cls('Flint', "Flint servlet engine settings (Flint addition, in place of Boot's `server.tomcat.*`).", [
    F('threads', 'int', '0', 'Number of reactor threads serving requests. 0 uses every CPU the process may run on, up to 16, as Tomcat\'s request thread pool spans the CPUs.'),
    F('maxHandlers', 'int', '200', 'Maximum number of requests handled at once, across the reactor threads, as Tomcat\'s server.tomcat.threads.max. Requests past it wait on their connections. 0 runs one handler per connection slot.',
      throws=True, setter_body=['if (maxHandlers < 0)', '{', '    import flint.java.lang : IllegalArgumentException;', '',
                                '    throw new IllegalArgumentException("Max handlers must not be negative");', '}',
                                'this.maxHandlers = maxHandlers;']),
    F('mainThread', 'bool', 'false', 'Whether the main thread serves requests once the application has started, as one of the reactor threads, instead of waiting idle for the context to close: one thread fewer for every stop-the-world collection to signal (docs/spring/phase1/gc.md, section 3c). `FlintApplication.runMain` sets it by default; an application that calls `run` itself leaves it off.'),
]), Cls('Servlet', 'Servlet properties.', [
    F('contextParameters', 'Map!(string, string)', 'new LinkedHashMap!(string, string)', 'Servlet context init parameters.', ro=True),
    F('contextPath', 'string', None, 'Context path of the application.', setter='cleanContextPath(contextPath)'),
    F('applicationDisplayName', 'string', '"application"', 'Display name of the application.'),
    F('registerDefaultServlet', 'bool', 'false', 'Whether to register the default Servlet with the container.'),
], state=['''// Boot's cleanContextPath: trimmed, without a trailing slash ("/petclinic/" is "/petclinic", "/" is "").
private static string cleanContextPath(string contextPath) pure nothrow @nogc
{
    import flint.engine.aot.text : stripWhite;

    const candidate = contextPath.length ? contextPath.stripWhite : null;
    return candidate.length && candidate[$ - 1] == '/' ? candidate[0 .. $ - 1] : candidate;
}'''])], prefix='server')
shutdown = Enum('Shutdown', 'Types of server shutdown.', [
    ('GRACEFUL', 'The server supports graceful shutdown: in-flight requests finish, new ones are refused.'),
    ('IMMEDIATE', 'The server shuts down immediately.')])
compression = Cls('Compression', 'Response compression.', [
    F('enabled', 'bool', 'false', 'Whether response compression is enabled.'),
    F('mimeTypes', 'string[]', '["text/html", "text/xml", "text/plain", "text/css", "text/javascript", "application/javascript", "application/json", "application/xml"]', 'Comma-separated list of MIME types that should be compressed.'),
    F('additionalMimeTypes', 'string[]', None, 'Comma-separated list of additional MIME types that should be compressed.'),
    F('excludedUserAgents', 'string[]', None, 'Comma-separated list of user agents for which responses should not be compressed.'),
])
http2 = Cls('Http2', 'HTTP/2 settings.', [F('enabled', 'bool', 'false', 'Whether to enable HTTP/2 support, if the current environment supports it.')])

# ---- core autoconfigure: WebProperties ----------------------------------------------------------------------
locale_resolver = Enum('LocaleResolver', 'How the locale is resolved.', [
    ('FIXED', 'Always use the configured locale.'), ('ACCEPT_HEADER', 'Use the "Accept-Language" header, or the configured locale if the header is not set.')])
web = Cls('WebProperties', 'General web settings.', [
    F('locale', 'string', None, 'Locale to use (a language tag such as `en-US`). By default, this locale is overridden by the "Accept-Language" header.'),
    F('localeResolver', 'LocaleResolver', 'LocaleResolver.ACCEPT_HEADER', 'Define how the locale should be resolved.'),
    F('resources', 'Resources', 'new Resources', 'Static resource handling (`flint.web.resources.*`).', ro=True),
    F('error', 'ErrorProperties', 'new ErrorProperties', 'Error handling (`flint.web.error.*`).', ro=True),
], enums=[locale_resolver], nested=[Cls('Resources', 'Static resource handling.', [
    F('staticLocations', 'string[]', '["classpath:/META-INF/resources/", "classpath:/resources/", "classpath:/static/", "classpath:/public/"]', 'Locations of static resources.'),
    F('addMappings', 'bool', 'true', 'Whether to enable default resource handling.'),
])], prefix='flint.web')

# ---- webmvc ------------------------------------------------------------------------------------------------
matching = Enum('MatchingStrategy', 'Strategies for matching request paths against registered mappings.', [
    ('ANT_PATH_MATCHER', 'Use the `AntPathMatcher` implementation.'), ('PATH_PATTERN_PARSER', 'Use the `PathPatternParser` implementation.')])
mvc = Cls('WebMvcProperties', 'Spring MVC settings.', [
    F('messageCodesResolverFormat', 'string', None, "Formatting strategy for message codes. For instance, 'PREFIX_ERROR_CODE'."),
    F('format', 'Format', 'new Format', 'Date and time formats (`flint.mvc.format.*`).', ro=True),
    F('dispatchTraceRequest', 'bool', 'false', 'Whether to dispatch TRACE requests to the FrameworkServlet doService method.'),
    F('dispatchOptionsRequest', 'bool', 'true', 'Whether to dispatch OPTIONS requests to the FrameworkServlet doService method.'),
    F('publishRequestHandledEvents', 'bool', 'true', 'Whether to publish a ServletRequestHandledEvent at the end of each request.'),
    F('logRequestDetails', 'bool', 'false', 'Whether logging of (potentially sensitive) request details at DEBUG and TRACE level is allowed.'),
    F('logResolvedException', 'bool', 'false', 'Whether to enable warn logging of exceptions resolved by a "HandlerExceptionResolver", except for "DefaultHandlerExceptionResolver".'),
    F('staticPathPattern', 'string', '"/**"', 'Path pattern used for static resources.'),
    F('webjarsPathPattern', 'string', '"/webjars/**"', 'Path pattern used for WebJar assets.'),
    F('async', 'Async', 'new Async', 'Asynchronous request handling (`flint.mvc.async.*`).', ro=True),
    F('servlet', 'Servlet', 'new Servlet', 'The dispatcher servlet (`flint.mvc.servlet.*`).', ro=True),
    F('view', 'View', 'new View', 'View resolution (`flint.mvc.view.*`).', ro=True),
    F('contentnegotiation', 'Contentnegotiation', 'new Contentnegotiation', 'Content negotiation (`flint.mvc.contentnegotiation.*`).', ro=True),
    F('pathmatch', 'Pathmatch', 'new Pathmatch', 'Path matching (`flint.mvc.pathmatch.*`); deprecated since 4.2.0.', ro=True),
    F('problemdetails', 'Problemdetails', 'new Problemdetails', 'RFC 9457 problem details (`flint.mvc.problemdetails.*`).', ro=True),
], enums=[matching], nested=[
    Cls('Async', 'Asynchronous request handling.', [F('requestTimeout', 'Optional!Duration', None, 'Amount of time before asynchronous request handling times out. If this value is not set, the default timeout of the underlying implementation is used.')]),
    Cls('Servlet', 'Dispatcher servlet settings.', [
        F('path', 'string', '"/"', 'Path of the dispatcher servlet. Setting a custom value for this property is not compatible with the PathPatternParser matching strategy.'),
        F('loadOnStartup', 'int', '-1', 'Load on startup priority of the dispatcher servlet.')]),
    Cls('View', 'View resolution.', [F('prefix', 'string', None, 'MVC view prefix.'), F('suffix', 'string', None, 'MVC view suffix.')]),
    Cls('Contentnegotiation', 'Content negotiation.', [
        F('favorParameter', 'bool', 'false', 'Whether a request parameter ("format" by default) should be used to determine the requested media type.'),
        F('parameterName', 'string', None, 'Query parameter name to use when "favor-parameter" is enabled.'),
        F('mediaTypes', 'Map!(string, string)', 'new LinkedHashMap!(string, string)', 'Map file extensions to media types for content negotiation. For instance, yml to text/yaml.', ro=True),
        F('defaultContentTypes', 'string[]', None, 'List of default content types to be used when no specific content type is requested.')]),
    Cls('Pathmatch', 'Path matching.', [F('matchingStrategy', 'MatchingStrategy', 'MatchingStrategy.PATH_PATTERN_PARSER', 'Choice of strategy for matching request paths against registered mappings.')]),
    Cls('Format', 'Date and time formats.', [
        F('date', 'string', None, "Date format to use, for example 'dd/MM/yyyy'."),
        F('time', 'string', None, "Time format to use, for example 'HH:mm:ss'."),
        F('dateTime', 'string', None, "Date-time format to use, for example 'yyyy-MM-dd HH:mm:ss'.")]),
    Cls('Problemdetails', 'RFC 9457 problem details.', [F('enabled', 'bool', 'false', 'Whether RFC 9457 Problem Details support should be enabled.')]),
], prefix='flint.mvc')

# ---- jackson -----------------------------------------------------------------------------------------------
ctor_detector = Enum('ConstructorDetectorStrategy', 'Strategies to use to auto-detect constructors.', [
    ('DEFAULT', 'Use heuristics to see if "properties" mode is to be used.'),
    ('USE_PROPERTIES_BASED', 'Assume "properties" mode if not explicitly annotated otherwise.'),
    ('USE_DELEGATING', 'Assume "delegating" mode if not explicitly annotated otherwise.'),
    ('EXPLICIT_ONLY', 'Refuse to decide implicit mode and instead throw an InvalidDefinitionException for ambiguous cases.')])
def fm(name, key, doc):
    # Boot's Map<Feature, Boolean>, keyed by the feature's name as bound (`indent-output` or `INDENT_OUTPUT`): one map
    # type for every feature enum, so Flint AOT's generated module instantiates one map, not one per enum (owner's
    # template diet, 2670d5be). StandardJsonMapperBuilderCustomizer converts the names as Boot's binder does.
    return F(name, 'Map!(string, bool)', 'new LinkedHashMap!(string, bool)', doc, ro=True, schema=f'Map!({key}, bool)')
jackson = Cls('JacksonProperties', 'Jackson settings.', [
    F('dateFormat', 'string', None, "Date format string or a fully-qualified date format class name. For instance, 'yyyy-MM-dd HH:mm:ss'."),
    F('propertyNamingStrategy', 'string', None, "One of the constants on Jackson's PropertyNamingStrategies. Can also be a fully-qualified class name of a PropertyNamingStrategy implementation."),
    F('visibility', 'Map!(string, string)', 'new LinkedHashMap!(string, string)', 'Jackson visibility thresholds that can be used to limit which methods (and fields) are auto-detected.', ro=True, schema='Map!(PropertyAccessor, JsonAutoDetect.Visibility)'),
    fm('serialization', 'SerializationFeature', 'Jackson on/off features that affect the way objects are serialized.'),
    fm('deserialization', 'DeserializationFeature', 'Jackson on/off features that affect the way objects are deserialized.'),
    fm('mapper', 'MapperFeature', 'Jackson general purpose on/off features.'),
    F('defaultPropertyInclusion', 'Optional!(JsonInclude.Include)', None, "Controls the inclusion of properties during serialization. Configured with one of the values in Jackson's JsonInclude.Include enumeration."),
    F('defaultLeniency', 'Optional!bool', None, 'Global default setting (if any) for leniency.'),
    F('constructorDetector', 'ConstructorDetectorStrategy', 'ConstructorDetectorStrategy.DEFAULT', 'Strategy to use to auto-detect constructor, and in particular behavior with single-argument constructors.'),
    F('timeZone', 'string', None, 'Time zone used when formatting dates. For instance, "America/Los_Angeles" or "GMT+10".'),
    F('locale', 'string', None, 'Locale used for formatting.'),
    F('useJackson2Defaults', 'bool', 'false', 'Whether to configure Jackson 3 with the same defaults as Boot previously used for Jackson 2.'),
    F('findAndAddModules', 'bool', 'true', 'Whether to find and add modules to the auto-configured JsonMapper.Builder.'),
    F('datatype', 'Datatype', 'new Datatype', 'Datatype features (`flint.jackson.datatype.*`).', ro=True),
    fm('read', 'StreamReadFeature', 'Jackson on/off token reader features common to multiple formats.'),
    fm('write', 'StreamWriteFeature', 'Jackson on/off token writer features common to multiple formats.'),
    F('json', 'Json', 'new Json', 'JSON-specific features (`flint.jackson.json.*`).', ro=True),
], enums=[ctor_detector], nested=[
    Cls('Datatype', 'Datatype features.', [
        fm('enum', 'EnumFeature', 'Jackson on/off features for enums.'),
        fm('datetime', 'DateTimeFeature', 'Jackson on/off features for DateTimes.')]),
    Cls('Json', 'JSON-specific features.', [
        fm('read', 'JsonReadFeature', 'Jackson on/off token reader features that are specific to JSON.'),
        fm('write', 'JsonWriteFeature', 'Jackson on/off token writer features that are specific to JSON.')]),
], prefix='flint.jackson')

# ---- core autoconfigure: ErrorProperties ---------------------------------------------------------------------
include_attribute = Enum('IncludeAttribute', 'When an attribute is included.', [
    ('NEVER', 'Never add error attribute.'), ('ALWAYS', 'Always add error attribute.'),
    ('ON_PARAM', 'Add error attribute when the appropriate request parameter is not "false".')])
error = Cls('ErrorProperties', 'Error handling settings, bound under `flint.web.error` through `WebProperties` (Boot 4 deprecated `server.error.*` at error level in favour of `spring.web.error.*`).', [
    F('path', 'string', '"/error"', 'Path of the error controller.'),
    F('includeException', 'bool', 'false', 'Include the "exception" attribute.'),
    F('includeStacktrace', 'IncludeAttribute', 'IncludeAttribute.NEVER', 'When to include the "trace" attribute.'),
    F('includeMessage', 'IncludeAttribute', 'IncludeAttribute.NEVER', 'When to include the "message" attribute.'),
    F('includeBindingErrors', 'IncludeAttribute', 'IncludeAttribute.NEVER', 'When to include the "errors" attribute.'),
    F('includePath', 'IncludeAttribute', 'IncludeAttribute.ALWAYS', 'When to include the "path" attribute.'),
    F('whitelabel', 'Whitelabel', 'new Whitelabel', 'The default error page (`whitelabel.*`).', ro=True),
], enums=[include_attribute], nested=[Cls('Whitelabel', 'The default HTML error page.', [
    F('enabled', 'bool', 'true', 'Whether to enable the default error page displayed in browsers in case of a server error.')])])


class Unit:
    """One generated D module and the module directory whose metadata it contributes to."""

    def __init__(self, path, header, name, doc, imports, items, package):
        self.path, self.header, self.name, self.doc, self.imports, self.items, self.package = (
            path, header, name, doc, imports, items, package)

    def render(self, existing=None):
        """The module text. When `existing` carries the generated-region markers, only that region is replaced, so
        hand-written code (an auto-configuration beside its properties) and its imports survive regeneration."""
        rendered = [render_enum(i, 0) if isinstance(i, Enum) else render_class(i) for i in self.items]
        rendered.append(render_exporter(self.items))
        region = BEGIN + '\n\n' + '\n\n'.join(rendered) + '\n\n' + END
        if existing is not None and BEGIN in existing and END in existing:
            head, rest = existing.split(BEGIN, 1)
            return head + region + rest.split(END, 1)[1]
        parts = [self.header, '', doc_lines(self.doc, 0), f'module {self.name};', '']
        if self.imports:
            parts += self.imports + ['']
        parts += ['@safe:', '', '']
        return '\n'.join(parts) + region + '\n'


BEGIN = '// ---- begin: generated by boot/tools/configuration_properties.py from its spec; edit the spec, not this region'
END = '// ---- end: generated region'


WEB_SERVER = 'boot/module/flint-boot-web-server'
SECURITY = 'boot/module/flint-boot-security'
messages = Cls('MessageSourceProperties', 'Settings of the auto-configured `MessageSource`.', [
    F('basename', 'string[]', '["messages"]', 'List of basenames (essentially a fully-qualified classpath location), each following the ResourceBundle convention with relaxed support for slash based locations. If it does not contain a package qualifier (such as "org.mypackage"), it will be resolved from the classpath root.'),
    F('commonMessages', 'string[]', None, 'List of locale-independent property file resources containing common messages.'),
    F('encoding', 'string', '"UTF-8"', 'Message bundles encoding (a charset name).'),
    F('cacheDuration', 'Optional!Duration', None, 'Loaded resource bundle files cache duration. When not set, bundles are cached forever. If a duration suffix is not specified, seconds will be used.', uda='@DurationUnit(ChronoUnit.SECONDS)'),
    F('fallbackToSystemLocale', 'bool', 'true', 'Whether to fall back to the system Locale if no files for a specific Locale have been found. If this is turned off, the only fallback will be the default file (e.g. "messages.properties" for basename "messages").'),
    F('alwaysUseMessageFormat', 'bool', 'false', 'Whether to always apply the MessageFormat rules, parsing even messages without arguments.'),
    F('useCodeAsDefaultMessage', 'bool', 'false', 'Whether to use the message code as the default message instead of throwing a "NoSuchMessageException". Recommended during development only.'),
], prefix='flint.messages')

webendpoint = Cls('WebEndpointProperties', 'Settings of the actuator\'s web endpoints.', [
    F('exposure', 'Exposure', 'new Exposure', 'Which endpoints are exposed (`exposure.*`).', ro=True),
    F('basePath', 'string', '"/actuator"', 'Base path for Web endpoints. Relative to the servlet context path (server.servlet.context-path) or WebFlux base path (spring.webflux.base-path) when the management server is sharing the main server port. Relative to the management server base path (management.server.base-path) when a separate management server port (management.server.port) is configured.'),
    F('pathMapping', 'Map!(string, string)', 'new LinkedHashMap!(string, string)', 'Mapping between endpoint IDs and the path that should expose them.', ro=True),
    F('discovery', 'Discovery', 'new Discovery', 'Discovery page (`discovery.*`).', ro=True),
], nested=[Cls('Exposure', 'Endpoint exposure over the web.', [
    F('include', 'string[]', None, 'Endpoint IDs that should be included or "*" for all.'),
    F('exclude', 'string[]', None, 'Endpoint IDs that should be excluded or "*" for all.'),
]), Cls('Discovery', 'The discovery page.', [
    F('enabled', 'bool', 'true', 'Whether the discovery page is enabled.'),
])], prefix='management.endpoints.web')

show = Enum('Show', 'When to show components or details.', [('NEVER', 'Never show details in the health endpoint.'), ('WHEN_AUTHORIZED', 'Show details in the health endpoint to authorized users.'), ('ALWAYS', 'Always show details in the health endpoint.')])
healthendpoint = Cls('HealthEndpointProperties', 'Settings of the health endpoint.', [
    F('showComponents', 'Optional!Show', None, 'When to show components. If not specified the \'show-details\' setting will be used.'),
    F('showDetails', 'Show', 'Show.NEVER', 'When to show full health details.'),
    F('roles', 'string[]', None, 'Roles used to determine whether a user is authorized to be shown details. When empty, all authenticated users are authorized.'),
    F('status', 'Status', 'new Status', 'Health status settings (`status.*`).', ro=True),
], nested=[Cls('Status', 'Health status settings.', [
    F('order', 'string[]', None, 'List of health statuses in order of severity.'),
    F('httpMapping', 'Map!(string, int)', 'new LinkedHashMap!(string, int)', 'Mapping of health statuses to HTTP status codes. By default, registered health statuses map to sensible defaults (for example, UP maps to 200).', ro=True),
])], enums=[show], prefix='management.endpoint.health')

security = Cls('SecurityProperties', 'Settings of Spring Security\'s defaults.', [
    F('user', 'User', 'new User', 'The default user (`user.*`).', ro=True),
], nested=[Cls('User', 'The default user name and password.', [
    F('name', 'string', '"user"', 'Default user name.'),
    F('password', 'string', 'randomUUID().toString()', 'Password for the default user name.', ctor=True,
      setter_body=['if (!password.length)', '    return;', 'this.passwordGenerated = false;', 'this.password = password;']),
    F('roles', 'string[]', None, 'Granted roles for the default user name.'),
], state=['private bool passwordGenerated = true;', '''/// Whether the password was generated (no `user.password` was set).
bool isPasswordGenerated() const pure nothrow @nogc
{
    return passwordGenerated;
}'''])], prefix='flint.security')
securityfilter = Cls('SecurityFilterProperties', 'Settings of the Spring Security filter.', [
    F('order', 'int', '-100', 'Security filter chain order for Servlet-based web applications.'),
    F('dispatcherTypes', 'DispatcherType[]', '[EnumMembers!DispatcherType]', 'Security filter chain dispatcher types for Servlet-based web applications.', ctor=True),
], state=['''/// The order of Boot's default `SecurityFilterChain` (`Ordered.LOWEST_PRECEDENCE - 5`).
enum int BASIC_AUTH_ORDER = int.max - 5;''', '''/// The default order of the security filter (`OrderedFilter.REQUEST_WRAPPER_FILTER_MAX_ORDER - 100`).
enum int DEFAULT_FILTER_ORDER = -100;'''], prefix='flint.security.filter')

UNITS = [
    Unit(f'{WEB_SERVER}/source/flint/boot/web/server/package.d',
         header('module/spring-boot-web-server/src/main/java/org/springframework/boot/web/server/Shutdown.java\n// with Compression.java and Http2.java from the same directory', '`DataSize minResponseSize` waits on spring-core\'s `DataSize`'),
         'flint.boot.web.server', '`org.springframework.boot.web.server`: embedded web server support.', [], [shutdown, compression, http2], WEB_SERVER),
    Unit(f'{WEB_SERVER}/source/flint/boot/web/server/autoconfigure.d',
         header('module/spring-boot-web-server/src/main/java/org/springframework/boot/web/server/autoconfigure/ServerProperties.java\n// with module/spring-boot-tomcat/src/main/java/org/springframework/boot/tomcat/autoconfigure/TomcatServerProperties.java',
                '`InetAddress address` is the address text; the deprecated `forward-headers-strategy`, `max-http-request-header-size` (`DataSize`), `ssl`, `mime-mappings`, `reactive.*`, `request.*` and the servlet `jsp`, `session` and `encoding` groups follow with their modules'),
         'flint.boot.web.server.autoconfigure', '`org.springframework.boot.web.server.autoconfigure`: the web server properties.',
         [CP, 'import flint.boot.web.server : Compression, Http2, Shutdown;', MAP, OPT], [server, tomcatprops], WEB_SERVER),
    Unit('boot/module/flint-boot-actuator/source/flint/boot/actuate/autoconfigure/endpoint/web.d',
         header('module/spring-boot-actuator-autoconfigure/src/main/java/org/springframework/boot/actuate/autoconfigure/endpoint/web/WebEndpointProperties.java\n// with ../expose/IncludeExcludeEndpointFilter.java',
                '`Map<EndpointId, String>` is keyed by the id text; the endpoint filter matches ids as Boot does, `*` for all'),
         'flint.boot.actuate.autoconfigure.endpoint.web', '`org.springframework.boot.actuate.autoconfigure.endpoint.web`: the web endpoint properties and exposure filter.',
         [CP, MAP], [webendpoint], 'boot/module/flint-boot-actuator'),
    Unit('boot/module/flint-boot-health/source/flint/boot/health/autoconfigure.d',
         header('module/spring-boot-health/src/main/java/org/springframework/boot/health/autoconfigure/actuate/endpoint/HealthEndpointProperties.java\n// with HealthProperties.java, HealthEndpointAutoConfiguration.java, HealthEndpointConfiguration.java,\n// AutoConfiguredHealthEndpointGroup(s).java, AvailabilityProbesAutoConfiguration.java and\n// AvailabilityProbesHealthEndpointGroups.java from the same directory, and\n// ../../contributor/PingHealthContributorAutoConfiguration.java',
                '`group.*`, `logging.*` and the reactive registry follow with health groups configuration and WebFlux'),
         'flint.boot.health.autoconfigure', '`org.springframework.boot.health.autoconfigure`: the health endpoint auto-configuration.',
         [CP, OPT, MAP], [healthendpoint], 'boot/module/flint-boot-health'),
    Unit('boot/core/flint-boot-autoconfigure/source/flint/boot/autoconfigure/context.d',
         header('core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/context/MessageSourceProperties.java\n// with MessageSourceAutoConfiguration.java and ResourceBasedMessageSourceConfigurer.java from the same directory',
                '`Charset encoding` is a charset name; `List<Resource> commonMessages` are resource locations'),
         'flint.boot.autoconfigure.context', '`org.springframework.boot.autoconfigure.context`: the `MessageSource` properties and auto-configuration.',
         [CP, DU, DUR, OPT], [messages], 'boot/core/flint-boot-autoconfigure'),
    Unit('boot/core/flint-boot-autoconfigure/source/flint/boot/autoconfigure/web.d',
         header('core/spring-boot-autoconfigure/src/main/java/org/springframework/boot/autoconfigure/web/ErrorProperties.java\n// with WebProperties.java from the same directory', '`Locale locale` is a language tag'),
         'flint.boot.autoconfigure.web', '`org.springframework.boot.autoconfigure.web`: web properties shared by the server modules.',
         [CP], [error, web], 'boot/core/flint-boot-autoconfigure'),
    Unit('boot/module/flint-boot-webmvc/source/flint/boot/webmvc/autoconfigure/package.d',
         header('module/spring-boot-webmvc/src/main/java/org/springframework/boot/webmvc/autoconfigure/WebMvcProperties.java',
                'media types are text until `flint.http.MediaType` can be combined with `flint:java`; `apiversion.*` follows with API versioning'),
         'flint.boot.webmvc.autoconfigure', '`org.springframework.boot.webmvc.autoconfigure`: the MVC properties. The auto-configurations (`WebMvcAutoConfiguration`, `DispatcherServletAutoConfiguration`) join this module on web-mvc\'s `WebMvcConfigurationSupport`.',
         [CP, DUR, OPT, MAP], [mvc], 'boot/module/flint-boot-webmvc'),
    Unit('boot/module/flint-boot-jackson/source/flint/boot/jackson/autoconfigure.d',
         header('module/spring-boot-jackson/src/main/java/org/springframework/boot/jackson/autoconfigure/JacksonProperties.java',
                '`TimeZone` and `Locale` are their text forms; `datatype.json-node` and `factory.constraints.*` follow with flint.jackson\'s `JsonNodeFeature` and `StreamReadConstraints`'),
         'flint.boot.jackson.autoconfigure', '`org.springframework.boot.jackson.autoconfigure`: the Jackson properties. `JacksonAutoConfiguration` joins this module on flint.jackson.databind\'s `JsonMapper.Builder`.',
         [CP, OPT, MAP, 'import flint.jackson.annotation : JsonAutoDetect, JsonInclude, PropertyAccessor;',
          'import flint.jackson.core : StreamReadFeature, StreamWriteFeature;', 'import flint.jackson.core.json : JsonReadFeature, JsonWriteFeature;',
          'import flint.jackson.databind.cfg : DateTimeFeature, DeserializationFeature, EnumFeature, MapperFeature, SerializationFeature;'],
         [jackson], 'boot/module/flint-boot-jackson'),
    Unit('boot/module/flint-boot-jdbc/source/flint/boot/jdbc/autoconfigure/package.d',
         header('module/spring-boot-jdbc/src/main/java/org/springframework/boot/jdbc/autoconfigure/DataSourceProperties.java\n// with JdbcProperties.java, DataSourceAutoConfiguration.java, DataSourceConfiguration.java and\n// DataSourceTransactionManagerAutoConfiguration.java from the same directory, and ../EmbeddedDatabaseConnection.java',
                '`type` is the class name; `jndiName` is excluded (jvm-platform); the `hikari` keys bind onto the pool data-access provides'),
         'flint.boot.jdbc.autoconfigure',
         '`org.springframework.boot.jdbc.autoconfigure`: the JDBC configuration properties. `flint.datasource.hikari.*` (alias `pool`) binds onto the pool `DataSource` the data-access module provides, as Boot binds `spring.datasource.hikari.*` onto `HikariDataSource`.',
         [CP, DU, DUR, OPT, MAP], [edc, datasource, jdbc], 'boot/module/flint-boot-jdbc'),
    Unit('boot/module/flint-boot-jdbc-health/source/flint/boot/jdbc/autoconfigure/health.d',
         header('module/spring-boot-jdbc/src/main/java/org/springframework/boot/jdbc/autoconfigure/health/DataSourceHealthIndicatorProperties.java\n// with DataSourceHealthContributorAutoConfiguration.java from the same directory',
                'the module is flint:boot-jdbc-health (deviation D-JDBC-2)'),
         'flint.boot.jdbc.autoconfigure.health', '`org.springframework.boot.jdbc.autoconfigure.health`: the auto-configuration of the `db` health contributor.',
         [CP], [dbhealth], 'boot/module/flint-boot-jdbc-health'),
    Unit('boot/module/flint-boot-sql/source/flint/boot/sql/init/package.d',
         header('module/spring-boot-sql/src/main/java/org/springframework/boot/sql/init/DatabaseInitializationMode.java'),
         'flint.boot.sql.init', '`org.springframework.boot.sql.init`: SQL database initialization support.', [], [mode], 'boot/module/flint-boot-sql'),
    Unit('boot/module/flint-boot-sql/source/flint/boot/sql/autoconfigure/init.d',
         header('module/spring-boot-sql/src/main/java/org/springframework/boot/sql/autoconfigure/init/SqlInitializationProperties.java', '`Charset encoding` is a charset name'),
         'flint.boot.sql.autoconfigure.init', '`org.springframework.boot.sql.autoconfigure.init`: the SQL initialization properties.',
         [CP, 'import flint.boot.sql.init : DatabaseInitializationMode;'], [sqlinit], 'boot/module/flint-boot-sql'),
    Unit('boot/module/flint-boot-transaction/source/flint/boot/transaction/autoconfigure.d',
         header('module/spring-boot-transaction/src/main/java/org/springframework/boot/transaction/autoconfigure/TransactionProperties.java'),
         'flint.boot.transaction.autoconfigure', '`org.springframework.boot.transaction.autoconfigure`: the transaction properties.',
         [CP, DU, DUR, OPT], [tx], 'boot/module/flint-boot-transaction'),
    Unit(f'{SECURITY}/source/flint/boot/security/autoconfigure/package.d',
         header('module/spring-boot-security/src/main/java/org/springframework/boot/security/autoconfigure/SecurityProperties.java\n// with SecurityAutoConfiguration.java and UserDetailsServiceAutoConfiguration.java from the same directory',
                '`List<String> roles` is a string array'),
         'flint.boot.security.autoconfigure', '`org.springframework.boot.security.autoconfigure`: Spring Security\'s properties and auto-configuration.',
         [CP, 'import std.uuid : randomUUID;'], [security], SECURITY),
    Unit(f'{SECURITY}/source/flint/boot/security/autoconfigure/web/servlet.d',
         header('module/spring-boot-security/src/main/java/org/springframework/boot/security/autoconfigure/web/servlet/SecurityFilterProperties.java\n// with SecurityFilterAutoConfiguration.java and ServletWebSecurityAutoConfiguration.java from the same directory',
                '`Set<DispatcherType>` is an array of Jakarta\'s `DispatcherType`, whose members Boot\'s enum mirrors'),
         'flint.boot.security.autoconfigure.web.servlet', '`org.springframework.boot.security.autoconfigure.web.servlet`: the security filter\'s properties and the servlet web security auto-configurations.',
         [CP, 'import flint.jakarta.servlet : DispatcherType;', 'import std.traits : EnumMembers;'], [securityfilter], SECURITY),
]

# Properties Boot core reads directly (Boot's additional-spring-configuration-metadata.json for core/spring-boot).
CORE_PROPERTIES = [
    ('flint.application.name', 'string', None, 'Application name. Shown in the console log format as [name].'),
    ('flint.application.group', 'string', None, 'Application group. Shown in the console log format after the name.'),
    ('flint.application.version', 'string', None, 'Application version, for the banner and the startup log.'),
    ('flint.main.banner-mode', ['off', 'console', 'log'], 'console', 'Mode used to display the banner when the application runs.'),
    ('flint.main.web-application-type', ['none', 'servlet', 'reactive'], None, 'Flag to explicitly request a specific type of web application.'),
    ('flint.main.log-startup-info', 'boolean', True, 'Whether to log information about the application when it starts.'),
    ('flint.banner.location', 'string', 'classpath:banner.txt', 'Banner text resource location.'),
    ('flint.output.ansi.enabled', ['detect', 'always', 'never'], 'detect', 'Configures the ANSI output.'),
    ('flint.profiles.active', 'list', None, 'Comma-separated list of active profiles. Can be overridden by a command line switch.'),
    ('flint.profiles.default', 'list', 'default', 'Name of the profile to enable if no profile is active.'),
    ('flint.profiles.include', 'list', None, 'Unconditionally activate the specified comma-separated list of profiles (or list of profiles if using YAML).'),
    ('flint.profiles.group', 'map-list', None, 'Profile groups to define a logical name for a related group of profiles.'),
    ('flint.config.name', 'list', 'application', 'Config file name.'),
    ('flint.config.location', 'list', None, 'Config file locations that replace the defaults.'),
    ('flint.config.additional-location', 'list', None, 'Config file locations used in addition to the defaults.'),
    ('flint.config.activate.on-profile', 'list', None, 'Profile expressions that should match for the document to be included.'),
    ('flint.boot.enableautoconfiguration', 'boolean', True, 'Whether auto-configuration is enabled.'),
    ('flint.autoconfigure.exclude', 'list', None, 'Auto-configuration classes to exclude.'),
    ('logging.level', 'map-level', None, 'Log levels severity mapping. For instance, `logging.level.org.springframework=DEBUG`.'),
]

# ---- metadata and JSON Schema ------------------------------------------------------------------------------

ENUM_SOURCES = {
    'SerializationFeature': ('framework/jackson-databind/source/flint/jackson/databind/cfg.d', 'SerializationFeature'),
    'DeserializationFeature': ('framework/jackson-databind/source/flint/jackson/databind/cfg.d', 'DeserializationFeature'),
    'MapperFeature': ('framework/jackson-databind/source/flint/jackson/databind/cfg.d', 'MapperFeature'),
    'EnumFeature': ('framework/jackson-databind/source/flint/jackson/databind/cfg.d', 'EnumFeature'),
    'DateTimeFeature': ('framework/jackson-databind/source/flint/jackson/databind/cfg.d', 'DateTimeFeature'),
    'StreamReadFeature': ('framework/jackson-core/source/flint/jackson/core/package.d', 'StreamReadFeature'),
    'StreamWriteFeature': ('framework/jackson-core/source/flint/jackson/core/package.d', 'StreamWriteFeature'),
    'JsonReadFeature': ('framework/jackson-core/source/flint/jackson/core/json/package.d', 'JsonReadFeature'),
    'JsonWriteFeature': ('framework/jackson-core/source/flint/jackson/core/json/package.d', 'JsonWriteFeature'),
    'PropertyAccessor': ('framework/jackson-annotations/source/flint/jackson/annotation/package.d', 'PropertyAccessor'),
    'JsonAutoDetect.Visibility': ('framework/jackson-annotations/source/flint/jackson/annotation/package.d', 'Visibility'),
    'JsonInclude.Include': ('framework/jackson-annotations/source/flint/jackson/annotation/package.d', 'Include'),
    'DispatcherType': ('framework/jakarta-servlet/source/flint/jakarta/servlet/package.d', 'DispatcherType'),
}

# The metadata names these enums by their module (Boot's `Set<DispatcherType>` is Jakarta's enum here).
JAVA_ENUMS = {'DispatcherType': 'flint.jakarta.servlet.DispatcherType'}


def kebab(name):
    return re.sub(r'(?<=[a-z0-9])([A-Z])', r'-\1', name).lower()


def enum_members(name, local):
    if name in local:
        return [m for m, _ in local[name].members]
    path, enum = ENUM_SOURCES[name]
    source = open(os.path.join(ROOT, path)).read()
    match = re.search(r'\benum ' + re.escape(enum) + r'\b[^{]*\{(.*?)\n\s*\}', source, re.S)
    return re.findall(r'^\s*([A-Z][A-Z0-9_]*)\s*(?:=[^,\n]*)?,?\s*(?://.*)?$', match.group(1), re.M)


def enums_of(cls, local):
    for e in cls.enums:
        local[e.name] = e
    for n in cls.nested:
        enums_of(n, local)


def value_schema(dtype, local, classes):
    """The JSON Schema of a field type, and its Boot metadata type name."""
    if dtype == 'bool' or dtype == 'Optional!bool':
        return {'type': 'boolean'}, 'java.lang.Boolean'
    if dtype in ('int', 'long', 'Optional!int', 'Optional!long'):
        return {'type': 'integer'}, 'java.lang.Integer' if 'int' in dtype else 'java.lang.Long'
    if dtype == 'string':
        return {'type': 'string'}, 'java.lang.String'
    if dtype in ('Duration', 'Optional!Duration'):
        return {'type': ['string', 'integer'], 'pattern': r'^([+-]?\d+(ns|us|ms|s|m|h|d)?|[+-]?[pP].*)$'}, 'java.time.Duration'
    if dtype == 'string[]':
        return {'oneOf': [{'type': 'array', 'items': {'type': 'string'}}, {'type': 'string'}]}, 'java.util.List<java.lang.String>'
    if dtype == 'Map!(string, string)':
        return {'type': 'object', 'additionalProperties': {'type': 'string'}}, 'java.util.Map<java.lang.String,java.lang.String>'
    if dtype == 'Map!(string, int)':
        return {'type': 'object', 'additionalProperties': {'type': 'integer'}}, 'java.util.Map<java.lang.String,java.lang.Integer>'
    match = re.match(r'Map!\((.+), (.+)\)$', dtype)
    if match:
        keys = enum_members(match.group(1), local)
        value = {'type': 'boolean'} if match.group(2) == 'bool' else enum_schema(enum_members(match.group(2), local))
        return {'type': 'object', 'propertyNames': {'enum': [kebab_enum(k) for k in keys] + keys},
                'additionalProperties': value}, f'java.util.Map<{match.group(1)},{match.group(2)}>'
    if dtype.endswith('[]') and (dtype[:-2] in local or dtype[:-2] in ENUM_SOURCES):
        return ({'oneOf': [{'type': 'array', 'items': enum_schema(enum_members(dtype[:-2], local))}, {'type': 'string'}]},
                f'java.util.Set<{JAVA_ENUMS.get(dtype[:-2], dtype[:-2])}>')
    inner = dtype[len('Optional!('):-1] if dtype.startswith('Optional!(') else dtype[len('Optional!'):] if dtype.startswith('Optional!') else dtype
    if inner in local or inner in ENUM_SOURCES:
        return enum_schema(enum_members(inner, local)), inner
    if inner in classes:
        return None, inner
    raise SystemExit(f'configuration_properties.py: no schema for type {dtype}')


def kebab_enum(member):
    return member.lower().replace('_', '-')


def enum_schema(members):
    # Boot binds enums leniently: any case, `-` or `_`; offer the kebab-case spellings Boot's metadata uses.
    return {'type': 'string', 'enum': [kebab_enum(m) for m in members] + members}


def default_value(f):
    if f.default is None or f.ro:
        return None
    text = f.default
    if f.ctor and not text.startswith('[EnumMembers!'):
        return None
    if text in ('true', 'false'):
        return text == 'true'
    if re.fullmatch(r'-?\d+', text):
        return int(text)
    if text.startswith('"'):
        return json.loads(text)
    if text.startswith('[EnumMembers!'):
        return sorted(kebab_enum(m) for m in enum_members(text[len('[EnumMembers!'):-1], {}))
    if text.startswith('['):
        return json.loads(text)
    if '.' in text:
        return kebab_enum(text.rsplit('.', 1)[1])
    return None


def walk(cls, prefix, local, classes, metadata, schema, source_type):
    """Add `cls`'s properties under `prefix` to the metadata lists and the nested schema object."""
    metadata['groups'].append({'name': prefix, 'type': source_type, 'sourceType': source_type})
    for f in cls.fields:
        key = f'{prefix}.{kebab(f.name)}'
        target = f.dtype if not f.dtype.startswith('Optional!') else f.dtype
        nested = classes.get(target)
        if nested is not None and f.ro:
            sub = schema.setdefault('properties', {}).setdefault(kebab(f.name), {'type': 'object', 'additionalProperties': False})
            walk(nested, key, local, classes, metadata, sub, f'{source_type}${nested.name}')
            continue
        value, java_type = value_schema(f.schema or f.dtype, local, classes)
        entry = {'name': key, 'type': java_type, 'description': f.doc, 'sourceType': source_type}
        default = default_value(f)
        if default is not None:
            entry['defaultValue'] = default
        metadata['properties'].append(entry)
        node = dict(value, description=f.doc)
        if default is not None:
            node['default'] = default
        schema.setdefault('properties', {})[kebab(f.name)] = node


def collect_classes(cls, out):
    out[cls.name] = cls
    for n in cls.nested:
        collect_classes(n, out)


def outputs():
    """Every generated file: path relative to the repository root, and its text."""
    files = {}
    metadata_by_package = {}
    schema = {'type': 'object', 'properties': {}}
    classes = {}
    local = {}
    for unit in UNITS:
        full = os.path.join(ROOT, unit.path)
        files[unit.path] = unit.render(open(full).read() if os.path.exists(full) else None)
        for item in unit.items:
            if isinstance(item, Cls):
                collect_classes(item, classes)
                enums_of(item, local)
            else:
                local[item.name] = item
    for unit in UNITS:
        metadata = metadata_by_package.setdefault(unit.package, {'groups': [], 'properties': [], 'hints': []})
        for item in unit.items:
            if isinstance(item, Cls) and item.prefix:
                node = schema
                for part in item.prefix.split('.'):
                    node = node.setdefault('properties', {}).setdefault(part, {'type': 'object'})
                walk(item, item.prefix, local, classes, metadata, node, f'{unit.name}.{item.name}')
    core = metadata_by_package.setdefault('boot/core/flint-boot', {'groups': [], 'properties': [], 'hints': []})
    for key, kind, default, doc in CORE_PROPERTIES:
        value = core_schema(kind)
        entry = {'name': key, 'type': core_java_type(kind), 'description': doc}
        if default is not None:
            entry['defaultValue'] = default
            value['default'] = default
        core['properties'].append(entry)
        if isinstance(kind, list):
            core['hints'].append({'name': key, 'values': [{'value': v} for v in kind]})
        node = schema
        parts = key.split('.')
        for part in parts[:-1]:
            node = node.setdefault('properties', {}).setdefault(part, {'type': 'object'})
        node.setdefault('properties', {})[parts[-1]] = dict(value, description=doc)
    for package, metadata in sorted(metadata_by_package.items()):
        files[f'{package}/META-INF/flint/flint-configuration-metadata.json'] = json.dumps(metadata, indent=2) + '\n'
    files['boot/configuration-metadata/application.schema.json'] = json.dumps(application_schema(schema), indent=2) + '\n'
    return files


def core_schema(kind):
    if isinstance(kind, list):
        return {'type': 'string', 'enum': kind + [k.upper() for k in kind]}
    return {
        'string': {'type': 'string'},
        'boolean': {'type': 'boolean'},
        'list': {'oneOf': [{'type': 'array', 'items': {'type': 'string'}}, {'type': 'string'}]},
        'map-list': {'type': 'object', 'additionalProperties': {'oneOf': [{'type': 'array', 'items': {'type': 'string'}}, {'type': 'string'}]}},
        'map-level': {'type': 'object', 'additionalProperties': {'type': 'string', 'enum': [
            'trace', 'debug', 'info', 'warn', 'error', 'fatal', 'off', 'TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL', 'OFF']}},
    }[kind]


def core_java_type(kind):
    if isinstance(kind, list):
        return 'java.lang.String'
    return {'string': 'java.lang.String', 'boolean': 'java.lang.Boolean', 'list': 'java.util.List<java.lang.String>',
            'map-list': 'java.util.Map<java.lang.String,java.util.List<java.lang.String>>',
            'map-level': 'java.util.Map<java.lang.String,org.springframework.boot.logging.LogLevel>'}[kind]


def application_schema(tree):
    """The editor schema: the property tree under `flint`, also accepted under `spring` (ADR-030's alias)."""
    flint = tree['properties'].get('flint')
    if flint is not None:
        tree['properties']['spring'] = {'$ref': '#/properties/flint'}
    tree['properties'] = dict(sorted(tree['properties'].items()))
    return {'$schema': 'https://json-schema.org/draft/2020-12/schema',
            '$id': 'https://github.com/flint-projects/flint-boot/configuration-metadata/application.schema.json',
            'title': 'Flint Boot application.yaml',
            'description': 'Flint Boot configuration properties (generated by boot/tools/configuration_properties.py). '
                           'Every flint.* key is also accepted as spring.*.',
            **tree}


def dfmt_path():
    """The pinned dfmt: `$FLINT_DFMT`, this checkout's `.tools/bin/dfmt`, or the main checkout's (from a worktree)."""
    candidates = [os.environ.get('FLINT_DFMT'), os.path.join(ROOT, '.tools/bin/dfmt')]
    marker = os.sep + '.claude' + os.sep + 'worktrees' + os.sep
    if marker in ROOT:
        candidates.append(os.path.join(ROOT.split(marker)[0], '.tools/bin/dfmt'))
    for candidate in candidates:
        if candidate and os.path.exists(candidate):
            return candidate
    raise SystemExit('configuration_properties.py: dfmt not found; set FLINT_DFMT or run tools/install_quality_tools.py')


def formatted(path, text):
    """D sources pass through dfmt with the repository's style, as tools/quality.py requires."""
    if not path.endswith('.d'):
        return text
    import subprocess

    result = subprocess.run([dfmt_path(), '--config', ROOT], input=text, capture_output=True, text=True, check=True)
    return result.stdout


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--write', action='store_true', help='regenerate every output')
    mode.add_argument('--check', action='store_true', help='fail when a committed output differs')
    arguments = parser.parse_args(argv)
    stale = []
    for path, text in sorted(outputs().items()):
        text = formatted(path, text)
        full = os.path.join(ROOT, path)
        current = open(full).read() if os.path.exists(full) else None
        if current == text:
            continue
        if arguments.check:
            stale.append(path)
        else:
            os.makedirs(os.path.dirname(full), exist_ok=True)
            open(full, 'w').write(text)
            print(f'wrote {path}')
    if stale:
        print('configuration_properties.py: out of date (run --write):\n  ' + '\n  '.join(stale), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
