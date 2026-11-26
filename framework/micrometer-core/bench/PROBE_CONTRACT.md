# Micrometer core size probe

The feature constructs a tag set, replaces its method tag, registers a
timer with those tags, and checks the timer's count, total time and maximum
after one recording. It then writes the formatted set. The baseline
writes the same line directly. Both use the first command-line argument
as the region and default to `west`.
The control lists the feature package's direct dependencies.
