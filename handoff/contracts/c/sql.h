/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_SQL_ABI_H
#define FLINT_SQL_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_pg_connection flint_pg_connection;
typedef struct flint_sqlite_connection flint_sqlite_connection;
flint_pg_connection *flint_pg_connect_start(const char *connection_string);
int flint_pg_connect_poll(flint_pg_connection *connection, intptr_t *socket);
int flint_pg_send(flint_pg_connection *connection, const char *query,
                  size_t parameter_count, const char *const *values,
                  const int *lengths, const int *formats);
int flint_pg_consume(flint_pg_connection *connection);
int flint_pg_cancel_start(flint_pg_connection *connection);
int flint_pg_cancel_poll(flint_pg_connection *connection);
void flint_pg_close(flint_pg_connection *connection);
flint_sqlite_connection *flint_sqlite_open(const char *path, int flags);
void flint_sqlite_interrupt(flint_sqlite_connection *connection);
int flint_sqlite_close(flint_sqlite_connection *connection);
#ifdef __cplusplus
}
#endif
#endif
