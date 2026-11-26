# flint:expression probe

The fixture parses a SpEL string literal selected by argument count, evaluates the expression and prints its value. It prints `Spring's expression` with no arguments and `Flint's expression` with an extra argument.

The control declares both direct dependencies of the module, `flint:engine-aot` and `flint:java`. It selects and prints the corresponding value. The fixture exercises a D parser with no native provider.

`tools/measure_builds.py` reports the larger stripped O3 or Oz size difference. Template counts cover the D compiler invocations for the expression module and its probe.
