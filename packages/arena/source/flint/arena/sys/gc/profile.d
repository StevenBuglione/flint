/// Scalar, cumulative collection measurements shared with the public GC adapter.
module flint.arena.sys.gc.profile;

@safe:

struct PauseProfile
{
    /// Synchronous full marks completed. Subtract snapshots to isolate a workload.
    ulong collections;
    /// Monotonic nanoseconds. Resume includes invalidation of the threads' allocation caches.
    ulong suspendNs, markNs, resumeNs, sweepNs, lockNs;
    /// Diagnostic full marks and the times of the additional root and live-heap passes.
    ulong predictions, rootScanNs, oldScanNs;
    /// Successful census intervals, pagemap read/enumeration time and clear_refs time.
    ulong censuses, censusNs, clearNs;
    /// Totals across successful intervals. A spanning object counts once, at its full block size.
    ulong scannablePages, scannableObjects, scannableBytes;
    ulong dirtyPages, dirtyObjects, dirtyBytes;
    /// Bytes a page-filtered scanner would visit, including only dirty parts of large blocks.
    ulong dirtyScanBytes;
}
