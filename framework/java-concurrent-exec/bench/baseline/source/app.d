module app;

import core.stdc.stdio : printf;

void main(string[] args)
{
    auto cause = new Exception(args[0]);
    try
    {
        throw new Exception(args.length > 1 ? args[1] : args[0]);
    }
    catch (Exception failure)
    {
        const usable = cause !is null && failure.msg.length != 0;
        printf("%d\n", cast(int) !usable);
    }
}
