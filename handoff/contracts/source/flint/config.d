/// Public API contract; declarations are not runtime implementations.
module flint.config;
import flint.arena : Error, Result;

@safe:
struct ConfigurationProperties
{
    string prefix;
}

struct Required
{
}

struct Secret
{
}

struct Env
{
    string name;
}

struct Default
{
    string value;
}

struct ConfigOptions
{
    string directory = ".";
    string profile = "dev";
    string envPrefix = "FLINT_";
    string[] arguments;
    bool rejectUnknownKeys = true;
}

struct Diagnostic
{
    string key;
    string source;
    uint line;
    uint column;
    string message;
}

Result!T load(T)(scope const ref ConfigOptions options);
Error validateConfig(T)(scope const ref T configuration);
