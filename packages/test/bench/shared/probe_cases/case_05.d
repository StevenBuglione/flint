module probe_cases.case_05;

import probe_fixture : account;

@safe:

@("case 05")
unittest
{
    account(5);
}
