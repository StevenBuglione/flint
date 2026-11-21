# Structured logging on Linux

The logger reserves normal producer shards and a separate 64 KiB error ring at startup. Producers copy validated message and field bytes into their slots with the supplied value context. Redaction matches the built-in sensitive keys case-insensitively and treats hyphens and underscores alike. `LogOptions.allowSensitiveKeys` opts specific built-in keys out of redaction. The maximum record size applies to the complete serialized line, including metadata and newline.

A dedicated consumer serializes each line with a UTC timestamp and a monotonically increasing sequence. JSON context keys are `requestId`, `traceId` and `spanId`. Trace and span identifiers are fixed-width lowercase hexadecimal strings. Console messages escape control bytes as well. Convenience calls can use a composition-provided context hook. Worker calls can pass `LogContext` explicitly to `write`.

Provide an append-only file path or a nonblocking sink callback at creation. The default opens independent nonblocking stdout and stderr descriptions through Linux procfs. An occupied producer slot or a contended shard returns `resourceExhausted`. A callback can return `unavailable` to retry the same complete line. Native short writes resume at the first unwritten byte.

Flush waits for the per-shard publication watermarks visible when it starts. Close stops admission and drains until its configured deadline. A sink still blocked in an OS call retains its worker and storage until that call returns. Final accepted and delivered totals show how many records remained at shutdown. Closing a copied logger handle closes the same shared sink.

The feature and direct-reference probes report producer latency and drop counts for disabled calls, accepted 128-byte and 4 KiB message payloads, and saturated admission. Their common sink validates the emitted payloads and computes an observable checksum. Set `FLINT_LOG_PROBE_SAMPLE_DIR` separately for each variant to retain native-endian 64-bit nanosecond samples in acquisition order.

The Linux standard-stream sink reopens stdout and stderr as nonblocking streams when procfs is available. In an empty deployment root it duplicates inherited streams with close-on-exec and preserves the original descriptor flags. Socket sends use per-call nonblocking I/O. Other inherited streams use readiness checks and bounded chunks.
