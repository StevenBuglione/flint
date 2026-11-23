/++
Ported from spring-guides/gs-rest-service e15fec6: complete/src/main/java/com/example/restservice/RestServiceApplication.java
Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: Java → D syntax only (`@SpringBootApplication` → `@FlintBootApplication`, names;
`public static void main` → `mixin FlintMain`, which D needs for a free entry point).
+/
module com.example.restservice.rest_service_application;

import flint.boot : FlintApplication, FlintMain;
import flint.boot.autoconfigure : FlintBootApplication;

@safe:

/// The guide's application class.
@FlintBootApplication final class RestServiceApplication
{
    ///
    static int main(string[] args)
    {
        FlintApplication.run!RestServiceApplication(args);
        return 0;
    }
}

mixin FlintMain!RestServiceApplication;
