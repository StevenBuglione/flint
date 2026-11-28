# flint:java-concurrent-copyonwrite probe

The fixture builds a `CopyOnWriteArrayList` of a class element, appends two
elements and iterates it through a snapshot iterator, summing their values.
The baseline computes the same non-zero/zero result from the argument count
with no Java dependency. The fixture measures the copy-on-write list's linked
code.
