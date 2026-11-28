# flint:java-nio-channels-spi probe

The fixture builds an `AbstractInterruptibleChannel` subclass, runs `begin`
and `end(true)`, reads `isOpen`, closes it and then observes the
`AsynchronousCloseException` that `end(false)` throws on the closed channel.
The baseline computes the same non-zero/zero result from the argument count
with no Java dependency. The fixture measures the abstract base class's linked
code.
