/// A DTO holding a java.util.Date, so Jackson's JavaUtilDateModule must be registered for the erased read path.
module com.example.dated.event;

import flint.java.util.date : Date;

@safe:

/// An event and when it happened.
class EventDto
{
    /// What happened.
    string name;
    /// When.
    Date at;
}
