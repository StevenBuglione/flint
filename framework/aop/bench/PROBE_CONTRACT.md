# AOP pointcut probe

Both programs construct the same target and method descriptors and box a single
argument. The fixture checks a dynamic pointcut through the Spring API. The
control checks the same predicates directly, with the same static short-circuit.
Both report a match only for the `rename` method on `OwnerService` with a
nonempty string argument. With no arguments, both report a match for
`rename("Ada")`.
