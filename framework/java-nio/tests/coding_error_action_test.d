// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 CodingErrorAction API.
module coding_error_action_test;

import flint.java.nio.charset.codingerroraction : CodingErrorAction;

@safe:

static assert(!__traits(compiles, CodingErrorAction(cast(ubyte) 1)));
static assert(!__traits(compiles, CodingErrorAction("CUSTOM")));

private string actionName(CodingErrorAction action) pure nothrow @nogc
{
    return action.toString();
}

@("CodingErrorAction constants are distinct values that can be assigned")
unittest
{
    CodingErrorAction action = CodingErrorAction.REPORT;
    assert(actionName(action) == "REPORT");
    assert(CodingErrorAction.init == action);
    assert(CodingErrorAction.init.toString() == "REPORT");
    assert(action != CodingErrorAction.IGNORE);
    assert(action != CodingErrorAction.REPLACE);

    action = CodingErrorAction.IGNORE;
    assert(actionName(action) == "IGNORE");
    assert(action == CodingErrorAction.IGNORE);
    assert(action != CodingErrorAction.REPLACE);
    assert(action != CodingErrorAction.REPORT);

    action = CodingErrorAction.REPLACE;
    assert(actionName(action) == "REPLACE");
    assert(action == CodingErrorAction.REPLACE);
    assert(action != CodingErrorAction.IGNORE);
    assert(action != CodingErrorAction.REPORT);
}
