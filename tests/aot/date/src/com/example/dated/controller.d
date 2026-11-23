/// Echoes an event: the request body and the response are read and written through their descriptors.
module com.example.dated.controller;

import com.example.dated.event : EventDto;
import flint.web.bind.annotation : PostMapping, RequestBody, RestController;

@safe:

/// POST /events echoes the event.
@RestController final class EventController
{
    /// The event as received.
    @PostMapping("/events") EventDto echo(@RequestBody EventDto event)
    {
        return event;
    }
}
