/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_HTTP_ABI_H
#define FLINT_HTTP_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_curl_loop flint_curl_loop;
typedef int (*flint_curl_data_cb)(void *user, const uint8_t *data, size_t length);
flint_curl_loop *flint_curl_new(void);
int flint_curl_start(flint_curl_loop *loop, const char *url, const char *method,
                    flint_curl_data_cb callback, void *user, uint64_t *request_id);
int flint_curl_socket(flint_curl_loop *loop, intptr_t socket, int events);
int flint_curl_timeout(flint_curl_loop *loop);
int flint_curl_cancel(flint_curl_loop *loop, uint64_t request_id);
void flint_curl_free(flint_curl_loop *loop);
#ifdef __cplusplus
}
#endif
#endif
