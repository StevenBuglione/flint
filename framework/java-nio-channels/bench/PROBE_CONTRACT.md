# Java NIO Channels package probe

The workload implements `SeekableByteChannel`, `InterruptibleChannel`, `ScatteringByteChannel`, and `GatheringByteChannel` over a single in-memory `ByteBuffer` and exercises channel open/close, single-buffer read/write, scatter/gather read/write, position, size, and truncate dispatch. The baseline links `Closeable` and `ByteBuffer` directly without `flint:java-nio-channels`.
