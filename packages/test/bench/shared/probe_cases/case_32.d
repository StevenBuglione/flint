module probe_cases.case_32;

import probe_fixture : account;

@safe:

@("case 32")
unittest
{
    account(32);
}
