module probe_cases.case_01;

import probe_fixture : account;

@safe:

@("case 01")
unittest
{
    account(1);
}
