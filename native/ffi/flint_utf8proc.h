#ifndef FLINT_UTF8PROC_H
#define FLINT_UTF8PROC_H

#include <stdint.h>

enum flint_scalar_property {
    FLINT_SCALAR_WIDTH_MASK = 3,
    FLINT_SCALAR_MARK = 4,
    FLINT_SCALAR_PICTOGRAPH = 8
};

uint32_t flint_scalar_properties(uint32_t scalar);
int32_t flint_grapheme_break(uint32_t previous, uint32_t current, int32_t *state);
const char *flint_unicode_version(void);

#endif
