# Flint Java Text Decimal probe

The fixture compiles a `DecimalFormat` for a valid pattern, reads the pattern
back, reads one symbol string from its `DecimalFormatSymbols` and formats a
long. It returns the sum of the three lengths modulo 128. The baseline depends
on the same providers and reads the lengths directly. The fallback pattern is
`#,##0.00`.

The link-closure fixtures exercise `DecimalFormat` and `DecimalFormatSymbols`
independently. They link the `Locale` implementation and the pinned symbol data
from `flint.java.util` and `flint.java.text.internal`; those modules are leaves
of `flint:java-text`, which this package depends on.
