/++
Sleep on a 32-bit word until another thread changes it, and wake its sleepers: the futex on Linux,
`os_sync_wait_on_address` on macOS, `WaitOnAddress` on Windows, a bounded sleep elsewhere. For plain threads that
wait on state a reactor fiber updates; a reactor fiber itself yields instead.

The usual loop: read the word, re-check the condition, then `park(word, seen, timeout)`. The call returns when the
word no longer holds `seen`, when woken, on timeout or spuriously, so the caller always re-checks.
+/
module flint.conc.park;

@safe:

static import flint.conc.sys.park;

/// Sleep while `word` holds `expected`, at most `timeoutNanos`. It may also return early; re-check after it.
alias park = flint.conc.sys.park.park;

/// Wake one thread parked on `word`.
alias wakeOne = flint.conc.sys.park.wakeOne;

/// Wake every thread parked on `word`.
alias wakeAll = flint.conc.sys.park.wakeAll;
