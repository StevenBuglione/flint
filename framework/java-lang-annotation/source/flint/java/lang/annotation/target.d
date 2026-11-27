/// Java SE 21 `java.lang.annotation.Target` meta-annotation (R2).
module flint.java.lang.annotation.target;

import flint.java.lang.annotation.elementtype : ElementType;

@safe:

/// Indicates the contexts in which an annotation interface is applicable.
struct Target
{
    /// The kinds of program element to which an annotation interface is applicable.
    ElementType[] value;
}
