/// Java SE 21 `java.lang.annotation.RetentionPolicy` (R1).
module flint.java.lang.annotation.retentionpolicy;

@safe:

/// Annotation retention policies.
enum RetentionPolicy
{
    /// Annotations are discarded by the compiler.
    SOURCE,
    /// Annotations are recorded in the class file but need not be retained at run time.
    CLASS,
    /// Annotations are recorded in the class file and retained at run time.
    RUNTIME
}
