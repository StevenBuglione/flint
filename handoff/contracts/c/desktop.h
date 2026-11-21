/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_DESKTOP_ABI_H
#define FLINT_DESKTOP_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_window flint_window;
typedef struct flint_window_event {
    uint32_t kind; int32_t x; int32_t y; uint32_t key_code;
} flint_window_event;
flint_window *flint_window_new(const char *title, uint32_t width,
                               uint32_t height, uint32_t flags);
int flint_window_poll(flint_window *window, flint_window_event *event);
int flint_window_submit(flint_window *window, const uint8_t *commands,
                        size_t command_bytes);
void flint_window_free(flint_window *window);
#ifdef __cplusplus
}
#endif
#endif
