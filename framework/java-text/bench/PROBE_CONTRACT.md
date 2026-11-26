# Flint Java Text probe

The fixture constructs a message formatter and a date formatter for two valid
input patterns and reads the original patterns back. The baseline depends on
the same providers and reads the lengths directly. Both return the sum of the
lengths modulo 128. The fallback patterns are `Hi {0}` and `yyyy-MM-dd`.

The moved link-closure fixtures exercise the two formatters independently.
They link the existing `Locale` implementation from `flint.java.util`. In the
date fixture LDC resolves a shared druntime array-append instantiation from
the package module's object. Only that module's metadata survives the link.
