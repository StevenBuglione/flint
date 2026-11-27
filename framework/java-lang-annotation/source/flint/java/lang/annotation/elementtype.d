/// Java SE 21 `java.lang.annotation.ElementType` (R1).
module flint.java.lang.annotation.elementtype;

@safe:

/// Syntactic locations where an annotation may appear in a Java program.
enum ElementType
{
    /// Class, interface (including annotation interface), enum, or record declaration.
    TYPE,
    /// Field declaration (includes enum constants).
    FIELD,
    /// Method declaration.
    METHOD,
    /// Formal parameter declaration.
    PARAMETER,
    /// Constructor declaration.
    CONSTRUCTOR,
    /// Local variable declaration.
    LOCAL_VARIABLE,
    /// Annotation interface declaration.
    ANNOTATION_TYPE,
    /// Package declaration.
    PACKAGE,
    /// Type parameter declaration.
    TYPE_PARAMETER,
    /// Use of a type.
    TYPE_USE,
    /// Module declaration.
    MODULE,
    /// Record component.
    RECORD_COMPONENT
}
