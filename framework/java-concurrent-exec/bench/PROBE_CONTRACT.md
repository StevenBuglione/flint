# flint:java-concurrent-exec probe

The fixture throws and catches a checked execution failure and checks its
cause and message. An argument supplies an explicit message. Without an
argument the constructor derives it from the cause. The baseline throws and
catches a native exception using the same provider dependency. Both programs
print zero when the message is available.
