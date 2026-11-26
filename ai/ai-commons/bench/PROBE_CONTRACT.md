# Spring AI commons content probe

The fixture creates a Content implementation with a nullable text field and
metadata containing an erased string. It prints the text and the metadata
value. The first argument selects the text, or `--absent` for missing text.
The second argument sets the metadata value. The control performs the same
work through a concrete reference with the same fields and getters.
Both use the same metadata map and perform no network I/O.
