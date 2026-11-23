/++
Ported from spring-guides/gs-rest-service e15fec6: complete/src/main/java/com/example/restservice/Greeting.java
Copyright the original author or authors. Licensed under the Apache License, Version 2.0.
Modified by the Flint authors: Java → D syntax only (record → struct, R11).
+/
module com.example.restservice.greeting;

@safe:

/// `public record Greeting(long id, String content) { }`
struct Greeting
{
    long id; ///
    string content; ///
}
