# java-math probe

Construct one integer from signed bytes and one from a signed long. Add and
subtract the second operand and print the resulting minimal byte length and
low byte. Check the second operand's exact conversion back to long, its
floating-point conversions, and that its square is larger. Check the
leading digit and width of the result in hexadecimal. Check the legacy rounding
code, name lookup, and declaration order for a rounding mode at the same input.
Round-trip the context settings through Java text at the same rounding code.
The control prints
the same values from the input.
Both builds carry the same `flint:java` dependency.
