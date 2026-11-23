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

@("the receipt's phases come from the Flint DUB's trace, and the trace stays out of the shown output")
unittest
{
    import flint_tool.engine.builder : dubPhases, withoutTrace;
    import flint_tool.engine.receipt : PhasesRecord;

    enum output = "    Building demo\n[flint-dub    0.0ms] runDubCommandLine\n[flint-dub   12.4ms] pipeline planned\n"
        ~ "[flint-dub   15.6ms] pipeline 3 compile jobs\n[flint-dub  157.3ms] pipeline compiled\n"
        ~ "[flint-dub  158.3ms] link begin\n[flint-dub  397.0ms] link end\n     Linking demo\n";
    PhasesRecord phases;
    dubPhases(output, 420, phases);
    expect(phases.compile).toEqual(141);
    expect(phases.link).toEqual(238);
    expect(phases.plan).toEqual(41);
    expect(withoutTrace(output)).toEqual("    Building demo\n     Linking demo\n");

    PhasesRecord untraced;
    dubPhases("    Building demo\n", 90, untraced);
    expect(untraced.compile).toEqual(-1);
    expect(untraced.link).toEqual(-1);
    expect(untraced.plan).toEqual(90);
}
