// Ported from spring-data-commons 4.2.0: src/main/java/org/springframework/data/domain/{DomainEvents,AfterDomainEventPublication}.java
// Copyright 2016-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
module flint.data.domain.events;

@safe:

/// The aggregate method that supplies application events to a repository.
struct DomainEvents
{
}

/// The aggregate callback after its domain events have been published.
struct AfterDomainEventPublication
{
}
