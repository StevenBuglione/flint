#include "flint_yaml.h"

#ifdef FLINT_HAS_LIBYAML

#ifndef YAML_DECLARE_STATIC
#define YAML_DECLARE_STATIC
#endif
#include <yaml.h>
#include <stdlib.h>
#include <string.h>

struct flint_yaml {
    yaml_parser_t parser;
    yaml_event_t event;
    const uint8_t *input;
    size_t length;
    size_t character;
    size_t byte;
    size_t initial_byte;
    int active;
};

int flint_yaml_open(const uint8_t *input, size_t length, void **out)
{
    static const uint8_t empty_input = 0;
    if (out == NULL || (length != 0 && input == NULL))
        return FLINT_YAML_INVALID;
    *out = NULL;

    struct flint_yaml *owner = calloc(1, sizeof(*owner));
    if (owner == NULL)
        return FLINT_YAML_NO_MEMORY;
    if (!yaml_parser_initialize(&owner->parser)) {
        free(owner);
        return FLINT_YAML_NO_MEMORY;
    }

    owner->input = input == NULL ? &empty_input : input;
    owner->length = length;
    if (length >= 3 && input[0] == 0xef && input[1] == 0xbb && input[2] == 0xbf)
        owner->initial_byte = 3;
    owner->byte = owner->initial_byte;
    yaml_parser_set_encoding(&owner->parser, YAML_UTF8_ENCODING);
    yaml_parser_set_input_string(&owner->parser, owner->input, length);
    *out = owner;
    return FLINT_YAML_OK;
}

void flint_yaml_close(void *opaque)
{
    struct flint_yaml *owner = opaque;
    if (owner == NULL)
        return;
    if (owner->active)
        yaml_event_delete(&owner->event);
    yaml_parser_delete(&owner->parser);
    free(owner);
}

static size_t byte_offset(struct flint_yaml *owner, size_t mark)
{
    if (mark < owner->character) {
        owner->character = 0;
        owner->byte = owner->initial_byte;
    }

    while (owner->byte < owner->length && owner->character < mark) {
        ++owner->byte;
        while (owner->byte < owner->length && (owner->input[owner->byte] & 0xc0) == 0x80)
            ++owner->byte;
        ++owner->character;
    }
    return owner->byte;
}

static int resolve_tag(const yaml_char_t *tag, uint32_t *kind)
{
    if (tag == NULL || strcmp((const char *) tag, "!") == 0) {
        *kind = FLINT_YAML_INFER;
        return FLINT_YAML_OK;
    }

    const char *known[] = {
        "", YAML_STR_TAG, YAML_BOOL_TAG, YAML_INT_TAG, YAML_FLOAT_TAG,
        YAML_NULL_TAG, YAML_SEQ_TAG, YAML_MAP_TAG
    };
    for (uint32_t index = FLINT_YAML_STRING; index <= FLINT_YAML_MAPPING; ++index) {
        if (strcmp((const char *) tag, known[index]) == 0) {
            *kind = index;
            return FLINT_YAML_OK;
        }
    }
    return FLINT_YAML_INVALID;
}

static int scalar_event(yaml_event_t *event, struct flint_yaml_event *out)
{
    if (event->data.scalar.anchor != NULL
            || resolve_tag(event->data.scalar.tag, &out->tag) != FLINT_YAML_OK
            || out->tag > FLINT_YAML_NULL)
        return FLINT_YAML_INVALID;
    if (out->tag == FLINT_YAML_INFER && event->data.scalar.style != YAML_PLAIN_SCALAR_STYLE)
        out->tag = FLINT_YAML_STRING;
    out->kind = FLINT_YAML_SCALAR;
    out->bytes = event->data.scalar.value;
    out->length = event->data.scalar.length;
    return FLINT_YAML_OK;
}

static int container_event(uint32_t kind, const yaml_char_t *anchor, const yaml_char_t *tag,
                           struct flint_yaml_event *out)
{
    const uint32_t expected = kind == FLINT_YAML_MAPPING_START ? FLINT_YAML_MAPPING : FLINT_YAML_SEQUENCE;
    if (anchor != NULL || resolve_tag(tag, &out->tag) != FLINT_YAML_OK
            || (out->tag != FLINT_YAML_INFER && out->tag != expected))
        return FLINT_YAML_INVALID;
    out->kind = kind;
    return FLINT_YAML_OK;
}

int flint_yaml_next(void *opaque, struct flint_yaml_event *out)
{
    struct flint_yaml *owner = opaque;
    if (owner == NULL || out == NULL)
        return FLINT_YAML_INVALID;

    memset(out, 0, sizeof(*out));
    if (owner->active) {
        yaml_event_delete(&owner->event);
        owner->active = 0;
    }
    if (!yaml_parser_parse(&owner->parser, &owner->event)) {
        out->offset = byte_offset(owner, owner->parser.problem_mark.index);
        return owner->parser.error == YAML_MEMORY_ERROR ? FLINT_YAML_NO_MEMORY : FLINT_YAML_INVALID;
    }

    owner->active = 1;
    yaml_event_t *event = &owner->event;
    out->offset = byte_offset(owner, event->start_mark.index);
    switch (event->type) {
    case YAML_STREAM_START_EVENT:
        out->kind = FLINT_YAML_STREAM_START;
        break;
    case YAML_STREAM_END_EVENT:
        out->kind = FLINT_YAML_STREAM_END;
        break;
    case YAML_DOCUMENT_START_EVENT:
        out->kind = FLINT_YAML_DOCUMENT_START;
        break;
    case YAML_DOCUMENT_END_EVENT:
        out->kind = FLINT_YAML_DOCUMENT_END;
        break;
    case YAML_SCALAR_EVENT:
        return scalar_event(event, out);
    case YAML_SEQUENCE_START_EVENT:
        return container_event(FLINT_YAML_SEQUENCE_START, event->data.sequence_start.anchor,
                               event->data.sequence_start.tag, out);
    case YAML_SEQUENCE_END_EVENT:
        out->kind = FLINT_YAML_SEQUENCE_END;
        break;
    case YAML_MAPPING_START_EVENT:
        return container_event(FLINT_YAML_MAPPING_START, event->data.mapping_start.anchor,
                               event->data.mapping_start.tag, out);
    case YAML_MAPPING_END_EVENT:
        out->kind = FLINT_YAML_MAPPING_END;
        break;
    default:
        return FLINT_YAML_INVALID;
    }
    return FLINT_YAML_OK;
}

#endif
