/++
spring-petclinic/spring-petclinic-rest (commit 220f4ba, the reference pinned in benchmarks/spring/apps.json):
`org.springframework.samples.petclinic.PetClinicApplication`, ported to Flint Boot.
Copyright 2016-2017 the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: `main` is `mixin FlintMain` (D-1), and the `SpringBootServletInitializer` superclass
is dropped, since a Flint application is never deployed as a WAR.
+/
module org.springframework.samples.petclinic;

import flint.boot : FlintMain;
import flint.boot.autoconfigure : FlintBootApplication;

@safe:

/// `@SpringBootApplication public class PetClinicApplication`.
@FlintBootApplication class PetClinicApplication
{
}

mixin FlintMain!PetClinicApplication;
