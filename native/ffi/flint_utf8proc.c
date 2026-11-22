#include "flint_utf8proc.h"

#ifdef FLINT_HAS_UTF8PROC
#include <utf8proc.h>

uint32_t flint_scalar_properties(uint32_t scalar)
{
    const utf8proc_property_t *property = utf8proc_get_property((utf8proc_int32_t)scalar);
    const int width = utf8proc_charwidth((utf8proc_int32_t)scalar);
    uint32_t result = width < 0 ? 0 : (uint32_t)width;
    if (property->category == UTF8PROC_CATEGORY_MN || property->category == UTF8PROC_CATEGORY_MC
        || property->category == UTF8PROC_CATEGORY_ME)
        result |= FLINT_SCALAR_MARK;
    if (property->boundclass == UTF8PROC_BOUNDCLASS_EXTENDED_PICTOGRAPHIC)
        result |= FLINT_SCALAR_PICTOGRAPH;
    return result;
}

int32_t flint_grapheme_break(uint32_t previous, uint32_t current, int32_t *state)
{
    return utf8proc_grapheme_break_stateful((utf8proc_int32_t)previous, (utf8proc_int32_t)current, state);
}

const char *flint_unicode_version(void)
{
    return utf8proc_unicode_version();
}
#endif
