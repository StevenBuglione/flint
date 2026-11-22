module app;

import config_workload : Layer, runWorkload;
import flint.arena : Result;
import flint.config : ConfigOptions, load;

@safe:

private Result!(Layer!levels) bindFixture(uint levels)(string directory)
{
    ConfigOptions options;
    options.directory = directory;
    options.envPrefix = "FLINT_CONFIG_PROBE_";
    options.arguments = ["--flint.profile=bench"];
    return load!(Layer!levels)(options);
}

int main(string[] args)
{
    return runWorkload!bindFixture(args.length > 1 && args[1] == "--measure");
}
