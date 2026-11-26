module app;

import flint.java.sql : SQLException;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "someValue";
    return cast(int)((new SQLException(arg, "HY000", cast(int) arg.length)).getErrorCode()) & 127;
}
