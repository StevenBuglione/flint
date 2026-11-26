/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/samples/standalone/ResponseBodyTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use a struct for the JSON body and the direct equality matchers.
+/
module standalone_response_body_tests;

import flint.http : MediaType;
import flint.jakarta.servlet.http : HttpServletResponse;
import flint.java.nio.charset : StandardCharsets;
import flint.test.web.servlet.request : MockMvcRequestBuilders;
import flint.test.web.servlet.result : MockMvcResultMatchers;
import flint.test.web.servlet.setup : MockMvcBuilders;
import flint.web.bind.annotation : GetMapping, PathVariable, RestController;
import std.algorithm.searching : canFind;

@safe:

private struct Person
{
    string name;
    int age;
}

@RestController
private final class PersonController
{
    @GetMapping("/person/{name}")
    Person get(@PathVariable("name") string name)
    {
        return Person(name, 42);
    }

    @GetMapping("/plain")
    void plain(HttpServletResponse response)
    {
        response.setContentType("text/plain");
        response.getOutputStream().write(cast(const(ubyte)[]) "Jürgen");
    }
}

@("json")
unittest
{
    auto mvc = MockMvcBuilders.standaloneSetup(new PersonController)
        .defaultResponseCharacterEncoding(StandardCharsets.UTF_8).build();
    auto result = mvc.perform(MockMvcRequestBuilders.get("/person/Jürgen").characterEncoding(StandardCharsets.UTF_8)
            .accept(MediaType.APPLICATION_JSON)).andExpect(MockMvcResultMatchers.status().isOk())
        .andExpect(MockMvcResultMatchers.content()
                .contentType("application/json")).andExpect(MockMvcResultMatchers.content()
            .encoding(StandardCharsets.UTF_8))
        .andExpect(MockMvcResultMatchers.jsonPath("$.name").value("Jürgen")).andExpect(
            MockMvcResultMatchers.jsonPath("$.age")
            .value(42)).andExpect(MockMvcResultMatchers.jsonPath("$.age").value(42.0f)).andReturn();
    assert(result.getResponse().getContentAsString().canFind("Jürgen"));
}

@("The MockMvc fallback decodes plain responses without adding a charset parameter")
unittest
{
    auto mvc = MockMvcBuilders.standaloneSetup(new PersonController)
        .defaultResponseCharacterEncoding(StandardCharsets.UTF_8).build();
    mvc.perform(MockMvcRequestBuilders.get("/plain")).andExpect(MockMvcResultMatchers.status()
            .isOk()).andExpect(MockMvcResultMatchers.content().contentType("text/plain"))
        .andExpect(MockMvcResultMatchers.content().encoding(StandardCharsets.UTF_8)).andExpect(
            MockMvcResultMatchers.content().string("Jürgen"));
}
