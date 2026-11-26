module app;

import flint.javax.sql : DataSource;

@safe:

int main(string[] args)
{
    return cast(int)(typeid(DataSource).tsize + args.length) & 127;
}
