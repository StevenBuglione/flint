# flint:java-concurrent-copyonwrite-set probe

The fixture builds a `CopyOnWriteArraySet` of a class element, adds three
elements (one equal to another) and iterates it through a snapshot iterator,
summing their values. The baseline computes the same non-zero/zero result from
the argument count with no Java dependency. The fixture measures the
copy-on-write set's linked code.
