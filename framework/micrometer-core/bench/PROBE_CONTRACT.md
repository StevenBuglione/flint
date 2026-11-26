# Micrometer core size probe

The feature constructs a tag set, replaces its method tag, checks the
registry's default clock, registers a timer through its builder, and
records a sample using a mock clock. It checks the sample's elapsed time
and the timer's count, total time and maximum. It then times a retained
callback through the callable and supplier interfaces. It checks the region
result and updated count after each invocation before writing the formatted
set. The baseline writes the same line directly. Both use the first
command-line argument as the region and default to `west`.
The control lists the feature package's direct dependencies.
