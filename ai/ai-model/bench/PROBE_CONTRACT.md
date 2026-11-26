# Spring AI model size probe

The probe constructs an `OpaquePayload` from configurable provider, kind, and
data strings. It emits the three fields verbatim. The control accepts the same
inputs, calls the same Spring assertions through `flint:core`, and emits the
same fields without constructing the record. Neither binary invokes a model or
performs network I/O.
