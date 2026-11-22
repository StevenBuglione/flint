module probe_cases.case_02;

import probe_fixture : account;

@safe:

@("case 02")
unittest
{
    account(2);
}
