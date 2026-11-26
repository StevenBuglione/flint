# java-util probe

Generate a version 4 UUID and render it, then print the string length and
version nibble. The control reads the same 16 bytes from the same entropy
provider and prints the known length and version. Both builds have the same
`flint:java` and `flint:conc` dependencies.
