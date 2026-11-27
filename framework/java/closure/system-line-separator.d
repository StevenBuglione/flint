module app;

import flint.java.lang.system : System;

@safe:

int main(string[] args)
{
    return args.length > 1 && args[1] == System.lineSeparator() ? 0 : 1;
}
