# flint:java-concurrent-sync probe

The fixture selects a read or write lock from a stateful test double, tries
timed acquisition, signals its condition, and releases the acquisition. It
prints `0` with no arguments and `1` with one or more. The baseline computes
the same result from the argument count and time unit with the same provider
dependency. The fixture measures the linked interface dispatch contract.
