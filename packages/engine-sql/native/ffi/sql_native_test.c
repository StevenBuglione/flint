#include "flint_sql.h"

#undef NDEBUG
#include <assert.h>
#include <stdlib.h>
#include <string.h>

enum { leases = 16, waiters = 256 };

static void saturation(void)
{
    uint64_t slot, pool, ticket = 0;
    uint64_t held[leases], generations[leases];
    assert(flint_sql_pool_open(1, ":memory:", 8, leases, waiters, 0, &slot, &pool) == FLINT_SQL_OK);
    for (size_t index = 0; index < leases; ++index) {
        assert(flint_sql_pool_acquire(slot, pool, &ticket, &held[index], &generations[index]) == FLINT_SQL_OK);
        assert(ticket == 0);
    }

    uint64_t pending[waiters] = {0};
    uint64_t next_slot, next_generation;
    for (size_t index = 0; index < waiters; ++index) {
        assert(flint_sql_pool_acquire(slot, pool, &pending[index], &next_slot, &next_generation)
            == FLINT_SQL_CONFLICT);
        assert(pending[index] != 0);
    }
    assert(flint_sql_pool_acquire(slot, pool, &ticket, &next_slot, &next_generation) == FLINT_SQL_EXHAUSTED);
    assert(ticket == 0);
    flint_sql_pool_withdraw(slot, pool, pending[0]);
    flint_sql_pool_withdraw(slot, pool, pending[100]);

    assert(flint_sql_pool_release(slot, pool, held[0], generations[0]) == FLINT_SQL_OK);
    assert(flint_sql_pool_acquire(slot, pool, &pending[2], &next_slot, &next_generation) == FLINT_SQL_CONFLICT);
    assert(flint_sql_pool_acquire(slot, pool, &pending[1], &next_slot, &next_generation) == FLINT_SQL_OK);
    assert(next_slot == held[0] && next_generation != generations[0]);
    assert(flint_sql_pool_release(slot, pool, next_slot, generations[0]) == FLINT_SQL_NOT_FOUND);
    assert(flint_sql_pool_release(slot, pool, next_slot, next_generation) == FLINT_SQL_OK);

    for (size_t index = 1; index < leases; ++index)
        assert(flint_sql_pool_release(slot, pool, held[index], generations[index]) == FLINT_SQL_OK);
    for (size_t index = 2; index < waiters; ++index)
        flint_sql_pool_withdraw(slot, pool, pending[index]);
    assert(flint_sql_pool_close(slot, pool) == FLINT_SQL_OK);
    assert(flint_sql_pool_close(slot, pool) == FLINT_SQL_NOT_FOUND);
}

static void invalid_native_input(void)
{
    int status;
    assert(!flint_sql_operation_new("SELECT\0 1", 9, 0, 0, INT64_MAX, &status));
    assert(status == FLINT_SQL_INVALID);
    assert(!flint_sql_operation_new("SELECT 1", 8, 65536, 0, INT64_MAX, &status));
    assert(status == FLINT_SQL_INVALID);
    flint_sql_operation *operation = flint_sql_operation_new("SELECT ?", 8, 1, 1, INT64_MAX, &status);
    assert(operation && status == FLINT_SQL_OK);
    assert(flint_sql_operation_bind(operation, 1, 4, 0, 0.0, "", 0) == FLINT_SQL_INVALID);
    assert(flint_sql_operation_bind(operation, 0, 4, 0, 0.0, "\xc0\x80", 2) == FLINT_SQL_INVALID);
    assert(flint_sql_operation_bind(operation, 0, 1, 2, 0.0, NULL, 0) == FLINT_SQL_INVALID);
    assert(flint_sql_operation_start(operation, UINT64_MAX, 1) == FLINT_SQL_NOT_FOUND);
    flint_sql_operation_free(operation);
    flint_sql_cell cell;
    assert(flint_sql_row_info(1, 2, 0, &cell) == FLINT_SQL_NOT_FOUND);
    assert(flint_sql_row_copy(1, 2, 0, NULL, 0) == FLINT_SQL_NOT_FOUND);
}

/* UTF-8 checks read ASCII eight bytes at a time: a bad byte at any position of a run is still found, a valid
   two-byte sequence anywhere passes, and one cut at the end fails. Validation precedes the bind's own conflict
   check, so a valid text reads OK the first time and CONFLICT after. */
static void utf8_positions(void)
{
    int status;
    char text[40];
    flint_sql_operation *operation = flint_sql_operation_new("SELECT ?", 8, 1, 1, INT64_MAX, &status);
    assert(operation && status == FLINT_SQL_OK);
    for (size_t length = 1; length <= sizeof(text); ++length) {
        for (size_t at = 0; at < length; ++at) {
            memset(text, 'a', length);
            text[at] = (char)0xff;
            assert(flint_sql_operation_bind(operation, 0, 4, 0, 0.0, text, length) == FLINT_SQL_INVALID);
            if (at + 2 > length)
                continue;
            text[at] = (char)0xc3;
            text[at + 1] = (char)0xa9;
            assert(flint_sql_operation_bind(operation, 0, 4, 0, 0.0, text, length) != FLINT_SQL_INVALID);
            assert(flint_sql_operation_bind(operation, 0, 4, 0, 0.0, text, at + 1) == FLINT_SQL_INVALID);
        }
    }
    flint_sql_operation_free(operation);
    /* The statement text goes through the same check. */
    assert(!flint_sql_operation_new("SELECT 'abcdefgh\xff'", 18, 0, 0, INT64_MAX, &status));
    assert(status == FLINT_SQL_INVALID);
}

static void boundary_value(size_t length)
{
    int status;
    unsigned char *value = malloc(length ? length : 1);
    assert(value);
    memset(value, 'a', length);
    flint_sql_operation *operation = flint_sql_operation_new("SELECT ?", 8, 1, 1, INT64_MAX, &status);
    assert(operation && status == FLINT_SQL_OK);
    assert(flint_sql_operation_bind(operation, 0, 4, 0, 0.0, value, length) == FLINT_SQL_OK);
    if (length)
        value[length - 1] = 0xff;
    flint_sql_operation_free(operation);

    operation = flint_sql_operation_new("SELECT ?", 8, 1, 1, INT64_MAX, &status);
    assert(operation && status == FLINT_SQL_OK);
    if (length)
        assert(flint_sql_operation_bind(operation, 0, 4, 0, 0.0, value, length) == FLINT_SQL_INVALID);
    assert(flint_sql_operation_bind(operation, 0, 5, 0, 0.0, value, length) == FLINT_SQL_OK);
    flint_sql_operation_free(operation);
    free(value);
}

static void boundary_values(void)
{
    for (size_t length = 0; length <= 256; ++length)
        boundary_value(length);
    const size_t lengths[] = {1023, 1024, 1025, 1048575, 1048576, 1048577};
    for (size_t index = 0; index < sizeof(lengths) / sizeof(lengths[0]); ++index)
        boundary_value(lengths[index]);
}

static void dropped_operations(void)
{
    uint64_t pool_slot, pool_generation, lease, generation;
    assert(flint_sql_pool_open(1, ":memory:", 8, 1, 1, 4, &pool_slot, &pool_generation) == FLINT_SQL_OK);
    uint64_t ticket = 0;
    for (unsigned index = 0; index < 128; ++index) {
        int acquired;
        while ((acquired = flint_sql_pool_acquire(pool_slot, pool_generation, &ticket, &lease, &generation))
                == FLINT_SQL_CONFLICT)
            assert(flint_sql_poll(-1, 0, 1) == FLINT_SQL_OK);
        assert(acquired == FLINT_SQL_OK);
        int status;
        const char sql[] = "SELECT 1";
        flint_sql_operation *operation = flint_sql_operation_new(sql, sizeof(sql) - 1, 0, 1, INT64_MAX, &status);
        assert(operation && status == FLINT_SQL_OK);
        assert(flint_sql_operation_start(operation, lease, generation) == FLINT_SQL_OK);
        flint_sql_operation_cancel(operation);
        flint_sql_operation_abort(operation);
        assert(flint_sql_pool_release(pool_slot, pool_generation, lease, generation) == FLINT_SQL_OK);
    }
    int closed;
    while ((closed = flint_sql_pool_close(pool_slot, pool_generation)) == FLINT_SQL_CONFLICT)
        assert(flint_sql_poll(-1, 0, 1) == FLINT_SQL_OK);
    assert(closed == FLINT_SQL_OK);
}

typedef void (*row_check)(uint64_t lease, uint64_t row);

static int run_statement(uint64_t lease, uint64_t generation, const char *sql, row_check check)
{
    int status;
    flint_sql_operation *operation = flint_sql_operation_new(sql, strlen(sql), 0, 1, INT64_MAX, &status);
    assert(operation && status == FLINT_SQL_OK);
    assert(flint_sql_operation_start(operation, lease, generation) == FLINT_SQL_OK);
    for (;;) {
        int fd;
        unsigned interest;
        const int progress = flint_sql_operation_drive(operation, &fd, &interest);
        if (progress == FLINT_SQL_COMPLETE)
            break;
        if (progress == FLINT_SQL_ROW) {
            const uint64_t row = flint_sql_operation_publish_row(operation);
            assert(row);
            if (check)
                check(lease, row);
            flint_sql_operation_next(operation);
            continue;
        }
        assert(flint_sql_poll(fd, interest, 10) == FLINT_SQL_OK);
    }
    uint64_t affected;
    const int result = flint_sql_operation_finish(operation, &affected);
    flint_sql_operation_free(operation);
    return result;
}

static void check_names(uint64_t lease, uint64_t row)
{
    char name[16];
    size_t length = 0;
    assert(flint_sql_row_name(lease, row, 0, name, sizeof(name), &length) == FLINT_SQL_OK);
    assert(length == 2 && !memcmp(name, "id", 2));
    assert(flint_sql_row_name(lease, row, 1, name, sizeof(name), &length) == FLINT_SQL_OK);
    assert(length == 10 && !memcmp(name, "first_name", 10));
    /* Too small: nothing written past the span, and the full length reported. */
    memset(name, 'x', sizeof(name));
    assert(flint_sql_row_name(lease, row, 1, name, 4, &length) == FLINT_SQL_EXHAUSTED);
    assert(length == 10 && name[0] == 'x');
    assert(flint_sql_row_name(lease, row, 2, name, sizeof(name), &length) == FLINT_SQL_INVALID);
    assert(flint_sql_row_name(lease, row + 1, 0, name, sizeof(name), &length) == FLINT_SQL_NOT_FOUND);

    /* Every label in one call, each followed by a zero byte; a short span gets nothing past its end. */
    char names[32];
    size_t used = 0;
    assert(flint_sql_row_names(lease, row, names, sizeof(names), &used) == FLINT_SQL_OK);
    assert(used == 14 && !memcmp(names, "id\0first_name\0", 14));
    memset(names, 'x', sizeof(names));
    assert(flint_sql_row_names(lease, row, names, 5, &used) == FLINT_SQL_EXHAUSTED);
    assert(used == 14 && !memcmp(names, "id\0xx", 5));
    assert(flint_sql_row_names(lease, row, NULL, 0, &used) == FLINT_SQL_EXHAUSTED && used == 14);
    assert(flint_sql_row_names(lease, row + 1, names, sizeof(names), &used) == FLINT_SQL_NOT_FOUND && used == 0);

    /* Every cell in one call: the integer, and the text at its offset in the data span. The kinds are
       flint_sql_private.h's FLINT_SQL_INT and FLINT_SQL_TEXT. */
    enum { CELL_INT = 2, CELL_TEXT = 4 };
    flint_sql_cell cells[4];
    char data[16];
    uint32_t columns = 0;
    assert(flint_sql_row_read(lease, row, cells, 4, data, sizeof(data), &used, &columns) == FLINT_SQL_OK);
    assert(columns == 2 && cells[0].kind == CELL_INT && cells[0].integer == 1);
    assert(cells[1].kind == CELL_TEXT && cells[1].integer == 0 && cells[1].length == 4 && used == 4);
    assert(!memcmp(data, "Josh", 4));
    /* Too few cells for the row: nothing read. A short data span: the cells, and nothing past its end. */
    assert(flint_sql_row_read(lease, row, cells, 1, data, sizeof(data), &used, &columns) == FLINT_SQL_INVALID);
    assert(columns == 2);
    memset(data, 'x', sizeof(data));
    assert(flint_sql_row_read(lease, row, cells, 4, data, 3, &used, &columns) == FLINT_SQL_EXHAUSTED);
    assert(used == 4 && cells[1].length == 4 && data[0] == 'x' && cells[0].integer == 1);
    assert(flint_sql_row_read(lease, row, cells, 4, NULL, 0, &used, &columns) == FLINT_SQL_EXHAUSTED);
    assert(flint_sql_row_read(lease, row + 1, cells, 4, data, sizeof(data), &used, &columns)
           == FLINT_SQL_NOT_FOUND && used == 0 && columns == 0);
}

static void failures_and_names(void)
{
    uint64_t pool_slot, pool_generation, lease, generation, ticket = 0;
    assert(flint_sql_pool_open(1, ":memory:", 8, 1, 1, 4, &pool_slot, &pool_generation) == FLINT_SQL_OK);
    assert(flint_sql_pool_acquire(pool_slot, pool_generation, &ticket, &lease, &generation) == FLINT_SQL_OK);
    flint_sql_failure failure;
    assert(flint_sql_lease_failure(lease, generation + 1, &failure) == FLINT_SQL_NOT_FOUND);
    assert(flint_sql_lease_failure(UINT64_MAX, generation, &failure) == FLINT_SQL_NOT_FOUND);

    /* A CHECK constraint named with 300 two-byte characters makes a message longer than the record. */
    char create[1024] = "CREATE TABLE customers (id INTEGER PRIMARY KEY, first_name TEXT UNIQUE, CONSTRAINT \"";
    for (int index = 0; index < 300; ++index)
        strcat(create, "\xc3\xa9");
    strcat(create, "\" CHECK (id > 0))");
    assert(run_statement(lease, generation, create, NULL) == FLINT_SQL_OK);
    assert(flint_sql_lease_failure(lease, generation, &failure) == FLINT_SQL_OK && !failure.state[0]);
    assert(run_statement(lease, generation, "INSERT INTO customers VALUES (1, 'Josh')", NULL) == FLINT_SQL_OK);

    assert(run_statement(lease, generation, "INSERT INTO customers VALUES (2, 'Josh')", NULL) == FLINT_SQL_CONFLICT);
    assert(flint_sql_lease_failure(lease, generation, &failure) == FLINT_SQL_OK);
    assert(!strcmp(failure.state, "23505") && failure.vendor == 2067);
    assert(failure.length > 0 && failure.length == strlen(failure.message));

    assert(run_statement(lease, generation, "INSERT INTO customers VALUES (-1, 'Jeff')", NULL) == FLINT_SQL_CONFLICT);
    assert(flint_sql_lease_failure(lease, generation, &failure) == FLINT_SQL_OK);
    assert(!strcmp(failure.state, "23514"));
    assert(failure.length < FLINT_SQL_MESSAGE_CAPACITY && failure.message[failure.length] == 0);
    assert(failure.length > FLINT_SQL_MESSAGE_CAPACITY - 4);
    /* Cut on a character boundary: the last kept byte ends a two-byte sequence. */
    assert((unsigned char)failure.message[failure.length - 1] == 0xa9);

    assert(run_statement(lease, generation, "SELECT id, first_name FROM customers", check_names) == FLINT_SQL_OK);
    assert(flint_sql_lease_failure(lease, generation, &failure) == FLINT_SQL_OK && !failure.state[0]);
    assert(run_statement(lease, generation, "SELECT 1; SELECT 2", NULL) == FLINT_SQL_INVALID);
    assert(flint_sql_lease_failure(lease, generation, &failure) == FLINT_SQL_OK && !strcmp(failure.state, "42000"));

    assert(flint_sql_pool_release(pool_slot, pool_generation, lease, generation) == FLINT_SQL_OK);
    assert(flint_sql_lease_failure(lease, generation, &failure) == FLINT_SQL_NOT_FOUND);
    int closed;
    while ((closed = flint_sql_pool_close(pool_slot, pool_generation)) == FLINT_SQL_CONFLICT)
        assert(flint_sql_poll(-1, 0, 1) == FLINT_SQL_OK);
    assert(closed == FLINT_SQL_OK);
}

/* A driver is reachable only once enabled: before that, a pool for it does not open. */
static void driver_composition(void)
{
    uint64_t slot = 0, pool = 0;
    assert(!flint_sql_driver_enabled(0));
    assert(!flint_sql_driver_enabled(1));
    assert(!flint_sql_driver_enabled(-1));
    assert(!flint_sql_driver_enabled(2));
    assert(flint_sql_pool_open(1, ":memory:", 8, 1, 1, 0, &slot, &pool) == FLINT_SQL_UNSUPPORTED);
    assert(flint_sql_pool_open(0, "dbname=x", 8, 1, 1, 0, &slot, &pool) == FLINT_SQL_UNSUPPORTED);
    assert(flint_sql_enable_sqlite() == FLINT_SQL_OK);
    assert(flint_sql_enable_sqlite() == FLINT_SQL_OK);
    assert(flint_sql_driver_enabled(1));
    assert(!flint_sql_driver_enabled(0));
    assert(flint_sql_pool_open(0, "dbname=x", 8, 1, 1, 0, &slot, &pool) == FLINT_SQL_UNSUPPORTED);
    assert(flint_sql_pool_open(1, ":memory:", 8, 1, 1, 0, &slot, &pool) == FLINT_SQL_OK);
    assert(flint_sql_pool_close(slot, pool) == FLINT_SQL_OK);
    assert(flint_sql_enable_postgres() == FLINT_SQL_OK);
    assert(flint_sql_driver_enabled(0));
}

int main(void)
{
    driver_composition();
    saturation();
    invalid_native_input();
    utf8_positions();
    boundary_values();
    dropped_operations();
    failures_and_names();
    return 0;
}
