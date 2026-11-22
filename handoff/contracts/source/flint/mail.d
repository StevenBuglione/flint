// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.mail;
import flint.arena : Buffer, Error, RequestArena, Result;
import flint.conc : Context;

@safe:
enum MailBackend : ubyte
{
    smtp,
    ses,
    resend,
    postmark
}

struct MailAddress
{
    string address;
    string displayName;
}

struct Attachment
{
    string fileName;
    string contentType;
    Buffer content;
}

struct MailMessage
{
    MailAddress from;
    MailAddress[] to;
    MailAddress[] cc;
    MailAddress[] bcc;
    string subject;
    Buffer text;
    Buffer html;
    Attachment[] attachments;
    string idempotencyKey;
}

struct MailOptions
{
    MailBackend backend = MailBackend.smtp;
    string endpoint;
    string username;
    string password;
    bool requireTls = true;
    size_t maxMessageBytes = 10 * 1024 * 1024;
}

struct DeliveryReceipt
{
    Buffer providerId;
    bool accepted;
}

struct MailSender
{
    private ulong slot;
    private ulong generation;
    Error open(MailOptions options);
    Result!DeliveryReceipt send(scope const ref MailMessage message, ref scope RequestArena arena, ref Context context) nothrow @nogc;
    Error close() nothrow @nogc;
}
