# Linux process, glob and interrupt support

`run` executes the supplied argv directly and returns owned stdout and stderr byte arrays. The arrays retain at most `maxCaptureBytes` bytes combined, including when the result reports a capture-limit error. `stream` drains both pipes with a reusable buffer, delivers bytes in order within each stream, and returns empty capture arrays. Child stdin reads EOF. The selected environment determines PATH resolution, and a relative PATH entry is resolved after the child changes to its requested directory.

The supervisor exclusively waits for the subprocess. While the leader remains waitable, its PID identifies the owned Linux process group. Cancellation signals the group with SIGTERM, escalates after `terminateGraceNanos`, and reaps the leader. Reserve the supervised child for Flint when an application manages other subprocesses. A Context deadline produces a successful result with `ExitStatus.timedOut` set. An explicit Context cancellation reports `Status.cancelled`. A normal nonzero child exit is a successful result containing the child's code.

A streaming sink can block the caller. The independent supervisor terminates and reaps the group if that invocation exceeds the positive `sinkStallNanos` limit, measured from callback entry by the monotonic clock. `stream` returns after the borrowed callback returns and reports the stall in `Result.error`. If the callback throws, its original exception propagates after cleanup.

A glob emits sorted paths relative to the opened root. It bounds directory depth, output count and scanned entries. At each descent the Linux kernel checks that resolution remains beneath the root. With symlink following enabled, ancestor device/inode identities stop cycles. Components support `*`, `?`, bracket ranges and negated classes, and a whole `**` component matches across directory levels.

The native SIGINT action writes to an eventfd. Application callbacks run on a D coordinator thread. Subscriptions preserve the existing default or ignored action and decline an existing application handler. Serialize application-wide signal ownership changes during setup, including switching between a terminal session and an OS subscription. Close waits for an active callback when called outside the coordinator and restores the saved disposition when the last subscription closes.

The probes exercise 1,000 empty commands, 100 MiB per streaming trial and 100,000 entries per glob trial. Both variants consume and validate the same work and emit a checksum.
