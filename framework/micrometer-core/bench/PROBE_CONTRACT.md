# Micrometer core size probe

The feature constructs a tag set, replaces its method tag, checks the
registry's default clock, registers a timer through its builder, and
records a sample using a mock clock. It checks the sample's elapsed time
and the timer's count, total time and maximum. It then times a retained
callback through the callable and supplier interfaces. It checks the region
result and updated count before invoking reusable callable, supplier and D
delegate wrappers. It checks each result and the final count. It merges
distribution configuration with the defaults and checks that the configured
maximum decays on schedule. It checks unit conversion and diagnostic text for
bucket and percentile values before writing the formatted set. The baseline
writes the same line directly. Both use the first
command-line argument as the region and default to `west`.
The control lists the feature package's direct dependencies.
