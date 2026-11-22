module probe_cases.case_03;

import probe_fixture : account;

@safe:

@("case 03")
unittest
{
    account(3);
}
