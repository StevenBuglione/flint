/// Greeting rules: one business capability per module.
module shop.greeting;

@safe:

/// The greeting for `name`, as "<greeting>, <name>!".
string greet(string greeting, string name) pure
{
    return greeting ~ ", " ~ (name.length ? name : "world") ~ "!";
}
