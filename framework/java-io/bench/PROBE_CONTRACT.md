# flint:java-io probe

The fixture throws and catches an `UnsupportedEncodingException` with a
runtime message and uses the message length as its exit status. The baseline
returns the same length directly. The fixture imports the exception leaf.
