module app;

import config_workload : Layer, runWorkload;
import flint.arena : Result;
import flint.serde.owned : deserialize;
import std.file : readText;
import std.path : buildPath;

@safe:

private Result!(Layer!levels) bindFixture(uint levels)(string directory)
{
    return deserialize!(Layer!levels)(readText(buildPath(directory, "application.json")));
}

int main(string[] args)
{
    return runWorkload!bindFixture(args.length > 1 && args[1] == "--measure");
}
