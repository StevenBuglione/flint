// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.mq;
import flint.arena : Buffer, Error, RequestArena, Result, Text;
import flint.conc : Context;

@safe:
struct KafkaListener
{
    string topic;
    string group;
}

struct StreamListener
{
    string stream;
    string consumer;
}

enum Broker : ubyte
{
    kafka,
    natsJetStream
}

enum AckAction : ubyte
{
    ack,
    retry,
    reject
}

struct Message
{
    Text topic;
    Buffer key;
    Buffer payload;
    long offset;
    int partition;
    ulong deliveryToken;
}

struct QueueOptions
{
    Broker broker;
    string endpoints;
    string clientId;
    uint maxInFlight = 1024;
    size_t maxQueuedBytes = 16 * 1024 * 1024;
    long deliveryTimeoutNanos = 30_000_000_000L;
}

struct PublishReceipt
{
    int partition;
    long offset;
    ulong sequence;
}

alias MessageHandler = AckAction delegate(ref Message message, ref scope RequestArena arena, ref Context context) @safe nothrow @nogc;
struct QueueClient
{
    private ulong slot;
    private ulong generation;
    Error open(QueueOptions options);
    Result!PublishReceipt publish(string topic, scope const(ubyte)[] key, scope const(ubyte)[] payload,
            string deduplicationId, ref Context context) nothrow @nogc;
    Error subscribe(string topic, string consumer, MessageHandler handler);
    Error poll(ref Context context) nothrow @nogc;
    Error drain(ref Context context) nothrow @nogc;
    Error close() nothrow @nogc;
}

Error registerListeners(T)(ref QueueClient client, ref T component);
