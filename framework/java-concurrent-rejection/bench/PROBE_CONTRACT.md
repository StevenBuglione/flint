# flint:java-concurrent-rejection probe

The probe throws and catches a rejection, preserving the cause identity and
a detail message. An argument supplies the detail. Without one, the
constructor derives it from the cause. The provider baseline makes the
same checks with a Java RuntimeException. Both arms print zero on success.
