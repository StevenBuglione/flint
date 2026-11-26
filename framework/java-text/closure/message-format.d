module app;

import flint.java.text : MessageFormat;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "Hi {0}";
    return cast(int)((new MessageFormat(arg)).toPattern().length) & 127;
}
