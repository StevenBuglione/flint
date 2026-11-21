module probe_cases.case_42;

import probe_fixture : account;

@safe:

@("case 42")
unittest
{
    account(42);
}
