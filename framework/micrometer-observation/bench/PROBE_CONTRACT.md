# Micrometer Observation size probe

The feature adds three low-cardinality keys, removes one, and overrides the
method key with a high-cardinality value. It writes the combined snapshot in
key order. The control writes the same line. Both use the first argument for
the region and default to `west`. Both declare the Commons and Java providers.
