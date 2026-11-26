/// `flint budget`: what each endpoint of the Phase 1 apps costs per request (instructions, GC allocations and bytes),
/// against the budgets committed with each app (owner decision 087f28a3; coordination/notes/flint-budget.md). The
/// measurement is tools/flint_budget.py's; this command runs it with the repository's tools and streams its report.
module flint_tool.commands.budget;

import flint_tool.commands.args : BudgetArgs;
import flint_tool.engine.session : Session;

@safe:

/// The arguments tools/flint_budget.py receives for `args`.
string[] budgetArguments(string root, const ref BudgetArgs args)
{
    import std.conv : to;
    import std.path : buildPath;

    string[] argv = ["python3", buildPath(root, "tools", "flint_budget.py")];
    foreach (app; args.apps)
        argv ~= ["--app", app];
    if (args.update)
        argv ~= "--update";
    if (args.allowRaise.length)
        argv ~= ["--allow-raise", args.allowRaise];
    if (args.repeat > 1)
        argv ~= ["--repeat", args.repeat.to!string];
    if (args.binaries.length)
        argv ~= ["--binaries", args.binaries];
    if (args.report.length)
        argv ~= ["--json", args.report];
    return argv;
}

/// `flint budget`: 0 within budget, 1 a regression or a missing or stale budget, 2 the measurement failed.
int commandBudget(ref Session session, BudgetArgs args)
{
    import flint_tool.support.process : Launch, streamed;
    import flint_tool.sys.posix : writeError, writeOutput;

    Launch launch;
    launch.directory = session.home.root;
    const outcome = streamed(budgetArguments(session.home.root, args), launch, (scope const(char)[] text) @safe {
        writeOutput(text);
    }, (scope const(char)[] text) @safe { writeError(text); });
    if (!outcome.started || outcome.signalled)
        return 2;
    return outcome.code;
}

@("flint budget passes its options through to tools/flint_budget.py")
unittest
{
    BudgetArgs args;
    args.apps = ["gs-rest-service"];
    args.update = true;
    args.allowRaise = "087f28a3";
    args.repeat = 5;
    assert(budgetArguments("/r", args) == [
        "python3", "/r/tools/flint_budget.py", "--app", "gs-rest-service", "--update",
        "--allow-raise", "087f28a3", "--repeat", "5"
    ]);
}
