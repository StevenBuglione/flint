/// Java SE 21 `java.lang.annotation.Retention` meta-annotation (R2).
module flint.java.lang.annotation.retention;

import flint.java.lang.annotation.retentionpolicy : RetentionPolicy;

@safe:

/// Indicates how long annotations with the annotated interface are to be retained.
struct Retention
{
    /// The retention policy.
    RetentionPolicy value;
}
