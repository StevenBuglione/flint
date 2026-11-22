module duplicate_long;

import flint.cli : Command, parse, Option;

@safe:

@Command("duplicate-long", "Compile-time diagnostic fixture")
private struct Duplicate
{
    @Option("first", 'a', "") int first;
    @Option("first", 'b', "") int second;
}

/// Instantiate the invalid command and expose its field-local diagnostic.
void probe()
{
    parse!Duplicate([]);
}
