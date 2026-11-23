module shop.greeting_test;

import shop.greeting : greet;
import flint.test : expect;

@safe:

@("greet joins the greeting and the name")
unittest
{
    expect(greet("Hello", "Ada")).toEqual("Hello, Ada!");
}

@("greet falls back to world for an empty name")
unittest
{
    expect(greet("Hi", "")).toEqual("Hi, world!");
}
