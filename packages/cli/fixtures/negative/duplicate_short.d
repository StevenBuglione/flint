module duplicate_short;

import flint.cli : Command, parse, Option;

@safe:

@Command("duplicate-short", "Compile-time diagnostic fixture")
private struct Duplicate
{
    @Option("first", 'a', "")
    int first;
    @Option("second", 'a', "")
    int second;
}

/// Instantiate the invalid command and expose its field-local diagnostic.
void probe()
{
    parse!Duplicate([]);
}
