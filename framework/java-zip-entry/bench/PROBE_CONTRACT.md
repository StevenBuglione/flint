# flint:java-zip-entry probe

The fixture builds a `ZipEntry`, sets its time, size, CRC and method, and asks
for the DOS and local-date forms plus the entry's name hash. The baseline
computes the same non-zero/zero result from the argument count with no Java
dependency. The fixture measures the entry type's linked code.
