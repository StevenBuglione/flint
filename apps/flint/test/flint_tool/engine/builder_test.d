module flint_tool.engine.builder_test;

import flint_tool.engine.builder : withoutDebugInformation;
import flint.test : expect;

@safe:

@("debug = false removes only the flags that emit debug information")
unittest
{
    expect(withoutDebugInformation(["-preview=dip1000", "-debug", "-g", "-boundscheck=on"])).toEqual(
            ["-preview=dip1000", "-debug", "-boundscheck=on"]);
    expect(withoutDebugInformation(["-gf", "-gc", "-gline-tables-only", "-gdwarf=5", "-gs", "-O"])).toEqual([
        "-gs", "-O"
    ]);
}
