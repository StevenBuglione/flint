# Java NIO package probe

The argument count selects a byte order, a relative read at the buffer limit, or a relative write at the limit. The byte order branch returns the name length and the control selects the same name. The exception branches throw BufferUnderflowException or BufferOverflowException and use a shared RuntimeException handler to report whether the exception has a detail message. The control exercises both cases with the canonical RuntimeException. The closure probes exercise each leaf independently.
