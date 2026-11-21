#ifndef FLINT_YAML_H
#define FLINT_YAML_H

#include <stddef.h>
#include <stdint.h>

enum flint_yaml_kind {
    FLINT_YAML_STREAM_START = 1,
    FLINT_YAML_STREAM_END,
    FLINT_YAML_DOCUMENT_START,
    FLINT_YAML_DOCUMENT_END,
    FLINT_YAML_SCALAR,
    FLINT_YAML_SEQUENCE_START,
    FLINT_YAML_SEQUENCE_END,
    FLINT_YAML_MAPPING_START,
    FLINT_YAML_MAPPING_END
};

enum flint_yaml_tag {
    FLINT_YAML_INFER = 0,
    FLINT_YAML_STRING,
    FLINT_YAML_BOOLEAN,
    FLINT_YAML_INTEGER,
    FLINT_YAML_NUMBER,
    FLINT_YAML_NULL,
    FLINT_YAML_SEQUENCE,
    FLINT_YAML_MAPPING
};

enum flint_yaml_status {
    FLINT_YAML_OK = 0,
    FLINT_YAML_INVALID = 1,
    FLINT_YAML_NO_MEMORY = 2
};

struct flint_yaml_event {
    const uint8_t *bytes;
    size_t length;
    size_t offset;
    uint32_t kind;
    uint32_t tag;
};

/* The source remains caller-owned and valid until close. */
int flint_yaml_open(const uint8_t *input, size_t length, void **out);
/* View valid until the next call to next or close. */
int flint_yaml_next(void *owner, struct flint_yaml_event *out);
void flint_yaml_close(void *owner);

#endif
