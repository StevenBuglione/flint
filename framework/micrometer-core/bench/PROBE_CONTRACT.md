# Micrometer core size probe

The feature constructs a tag set, replaces its method tag, registers a
timer with those tags through its builder, and records a sample using a
mock clock. It checks the sample's elapsed time and the timer's count,
total time and maximum before writing the formatted set. The baseline
writes the same line directly. Both use the first command-line argument
as the region and default to `west`.
The control lists the feature package's direct dependencies.
