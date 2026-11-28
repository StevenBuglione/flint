# Spring AI document probe

The fixture creates a `Document` with a nullable text field and metadata
containing an erased string, then prints the generated ID, the text and the
metadata value. The first argument selects the text; the second sets the
metadata value. The control performs the same work through a concrete
reference with the same fields and getters. Both use the same metadata map and
perform no network I/O.
