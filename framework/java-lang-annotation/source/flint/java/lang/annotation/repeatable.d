/// Java SE 21 `java.lang.annotation.Repeatable` meta-annotation (R2, R4).
module flint.java.lang.annotation.repeatable;

import flint.java.classref : ClassRef;

@safe:

/// Indicates that the annotated annotation interface is repeatable via the named container annotation.
struct Repeatable
{
    /// The containing annotation interface (`Class<? extends Annotation>`, R4 `ClassRef`).
    ClassRef value;
}
