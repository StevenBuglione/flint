/// gs-rest-service's response record.
module com.example.restservice.greeting;

@safe:

/// `public record Greeting(long id, String content)`.
struct Greeting
{
    /// Sequence number.
    long id;
    /// Greeting text.
    string content;
}
