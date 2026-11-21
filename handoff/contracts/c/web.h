/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_WEB_ABI_H
#define FLINT_WEB_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_http1_parser flint_http1_parser;
typedef struct flint_h2_session flint_h2_session;
typedef int (*flint_http_event_cb)(void *user, uint32_t event,
                                 const uint8_t *bytes, size_t length);
flint_http1_parser *flint_http1_new(flint_http_event_cb callback, void *user);
int flint_http1_feed(flint_http1_parser *parser, const uint8_t *data, size_t length);
void flint_http1_free(flint_http1_parser *parser);
flint_h2_session *flint_h2_new(uint32_t max_streams, flint_http_event_cb callback,
                             void *user);
int flint_h2_feed(flint_h2_session *session, const uint8_t *data, size_t length);
int flint_h2_send(flint_h2_session *session, uint8_t *output, size_t capacity,
                 size_t *written);
void flint_h2_free(flint_h2_session *session);
#ifdef __cplusplus
}
#endif
#endif
