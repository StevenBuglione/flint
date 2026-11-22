/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_CACHE_ABI_H
#define FLINT_CACHE_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_redis_connection flint_redis_connection;
flint_redis_connection *flint_redis_new(const char *host, uint16_t port, int tls);
int flint_redis_command(flint_redis_connection *connection, size_t argc,
                        const char *const *argv, const size_t *lengths,
                        uint64_t *request_id);
int flint_redis_readable(flint_redis_connection *connection);
int flint_redis_writable(flint_redis_connection *connection);
void flint_redis_free(flint_redis_connection *connection);
#ifdef __cplusplus
}
#endif
#endif
