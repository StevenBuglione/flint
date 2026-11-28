# flint:java-filetime probe

The fixture builds a `FileTime` from a millisecond count and asks for the same
value and its ISO-8601 text. The baseline computes the same non-zero/zero
result from the argument count with no Java dependency. The fixture measures
the file-time value type's linked code.
