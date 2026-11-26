module app;

import core.stdc.stdio : fputc, stdout;

@safe:

void main(string[] args)
{
    string region = args.length > 1 ? args[1] : "west";
    foreach (character; "[keyValue(method=POST),keyValue(region=")
        fputc(character, stdout);
    foreach (character; region)
        fputc(character, stdout);
    foreach (character; ")]\n")
        fputc(character, stdout);
}
