module app;

import core.stdc.stdio : fputc, stdout;

@safe:

void main(string[] args)
{
    const region = args.length > 1 ? args[1] : "west";
    auto text = "[tag(method=POST),tag(region=" ~ region ~ ")]";
    foreach (character; text)
        fputc(character, stdout);
    fputc('\n', stdout);
}
