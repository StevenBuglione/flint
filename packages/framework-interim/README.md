# framework-interim

Stand-ins for names that belong to other Phase 1 sessions, so the web stack can build before those land:

| Module | Owner | Replaced by |
| --- | --- | --- |
| `flint.java.lang`, `flint.java.net`, `flint.java.nio.charset`, `flint.java.io` | framework-core | `flint:java` |
| `flint.core`, `flint.core.annotation`, `flint.util` (MimeType) | framework-core | `flint:core` |
| `flint.stereotype` | framework-core | `flint:context` |
| `flint.engine.aot.any`, `.descriptor`, `.mapping` | framework-core (contract by flint-aot) | `flint:engine-aot` |

Each module implements only what the web packages need, with the upstream names and signatures. None of it is a design for the owning package. `flint.util`'s `MimeType` is a full port and is offered to framework-core as is.
