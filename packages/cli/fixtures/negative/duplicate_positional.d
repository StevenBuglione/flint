module duplicate_positional;

import flint.cli : Command, parse, Arg;

@safe:

@Command("duplicate-positional", "Compile-time diagnostic fixture")
private struct Duplicate
{
    @Arg(0, "")
    int first;
    @Arg(0, "")
    int second;
}

/// Instantiate the invalid command and expose its field-local diagnostic.
void probe()
{
    parse!Duplicate([]);
}
