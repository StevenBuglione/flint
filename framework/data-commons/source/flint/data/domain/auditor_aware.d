// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/domain/AuditorAware.java
// Copyright 2008-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.domain.auditor_aware;

import flint.java.util : Optional;

@safe:

/// Supplies the current auditor for a data operation.
interface AuditorAware(T)
{
    /// The current auditor, or empty if none is available.
    Optional!T getCurrentAuditor();
}
