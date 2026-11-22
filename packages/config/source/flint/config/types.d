module flint.config.types;

@safe:

/// Prefix for the root of a configuration struct.
struct ConfigurationProperties
{
    /// Dotted key prefix used by files and CLI overrides.
    string prefix;
}

/// Require an explicit value or a configured default.
struct Required
{
}

/// Identify a value that must stay out of diagnostics.
struct Secret
{
}

/// Override the generated environment variable name.
struct Env
{
    /// Environment variable to read.
    string name;
}

/// Supply default text using the same coercion as a CLI override.
struct Default
{
    /// Text to coerce before applying higher-priority sources.
    string value;
}

/// Startup configuration source options.
struct ConfigOptions
{
    /// Directory containing the application files and .env.
    string directory = ".";
    /// Fallback profile name.
    string profile = "dev";
    /// Prefix used to generate environment variable names.
    string envPrefix = "FLINT_";
    /// Optional CLI profile and key/value overrides.
    string[] arguments;
    /// Reject keys outside the typed schema.
    bool rejectUnknownKeys = true;
    /// File stem of the base and profile files: `<baseName>.toml` and `<baseName>-<profile>.toml`.
    string baseName = "application";
    /// Read `.env`, the process environment and `FLINT_PROFILE`. Checked-in policy files turn this off
    /// so that nothing outside the files and explicit arguments can change them.
    bool readEnvironment = true;
}

/// Location and category of a configuration failure.
struct Diagnostic
{
    /// Resolved dotted key.
    string key;
    /// Source name or layer.
    string source;
    /// One-based source line, or zero for non-file inputs.
    uint line;
    /// One-based byte column, or zero for non-file inputs.
    uint column;
    /// Reason without the supplied value.
    string message;
}
