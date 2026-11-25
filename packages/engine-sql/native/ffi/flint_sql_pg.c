#define _POSIX_C_SOURCE 200809L
#include "flint_sql_private.h"

#if (defined(__linux__) || defined(__APPLE__) || defined(_WIN32)) && defined(FLINT_HAS_LIBPQ)

#include <errno.h>
#include <libpq-fe.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include "flint_port.h" /* pthread and strcasecmp on Win32 (ADR-026) */
#include "flint_wake.h"
#else
#include <pthread.h>
#include <strings.h>
#include <unistd.h>
#if defined(__APPLE__)
#include "flint_wake.h"
#else
#include <sys/eventfd.h>
#endif
#endif

enum { PG_UNSENT, PG_EVICTING, PG_PREPARING, PG_QUERY, PG_PIPE_PREAMBLE, PG_PIPE_SYNC };
/* operation->preamble_state: none (or done), waiting to be sent, running on its own, pipelined. */
enum { PREAMBLE_NONE, PREAMBLE_PENDING, PREAMBLE_ALONE, PREAMBLE_PIPELINED };
enum {
    OID_BOOL = 16, OID_BYTEA = 17, OID_CHAR = 18, OID_NAME = 19, OID_INT8 = 20, OID_OID = 26,
    OID_INT2 = 21, OID_INT4 = 23, OID_TEXT = 25, OID_FLOAT4 = 700,
    OID_FLOAT8 = 701, OID_BPCHAR = 1042, OID_VARCHAR = 1043, OID_DATE = 1082, OID_TIME = 1083,
    OID_TIMESTAMP = 1114
};

typedef struct {
    char *sql;
    uint64_t key; /* text_key(sql): the cache compares it before the text */
    Oid *types;
    size_t count;
    uint64_t touched;
} prepared_entry;

/* A cheap key for a statement text: its length and three 8-byte samples. Two texts with different keys differ;
   equal keys are confirmed with strcmp. */
static uint64_t text_key(const char *text)
{
    const size_t length = strlen(text);
    uint64_t key = (uint64_t)length * 0x9e3779b97f4a7c15u;
    if (length >= 8) {
        uint64_t sample;
        memcpy(&sample, text, 8);
        key ^= sample;
        memcpy(&sample, text + length / 2 - 4, 8);
        key ^= sample * 0xff51afd7ed558ccdu;
        memcpy(&sample, text + length - 8, 8);
        key ^= sample * 0xc4ceb9fe1a85ec53u;
    } else {
        for (size_t index = 0; index < length; ++index)
            key ^= (uint64_t)(unsigned char)text[index] << (8 * index);
    }
    return key;
}

struct flint_pg_connection {
    PGconn *database;
    PGcancelConn *cancellation;
    char *address;
    prepared_entry *prepared;
    pthread_mutex_t startup_lock;
    flint_sql_retirement retirement;
    unsigned capacity;
    uint64_t counter;
    int startup_event;
#if defined(__APPLE__) || defined(_WIN32)
    int startup_writer;
#endif
    int starter_active;
    int abandoned;
    int ready;
    int poll_started;
};

int flint_pg_available(void)
{
    return PQisthreadsafe() && PQlibVersion() == 180007;
}

static void clear_prepared(prepared_entry *entry)
{
    free(entry->types);
    free(entry->sql);
    memset(entry, 0, sizeof(*entry));
}

static void free_connection(flint_pg_connection *connection)
{
    if (connection->cancellation)
        PQcancelFinish(connection->cancellation);
    if (connection->database)
        PQfinish(connection->database);
    for (unsigned index = 0; index < connection->capacity; ++index)
        clear_prepared(&connection->prepared[index]);
    pthread_mutex_destroy(&connection->startup_lock);
#if defined(__APPLE__) || defined(_WIN32)
    flint_wake_close(connection->startup_event, connection->startup_writer);
#else
    close(connection->startup_event);
#endif
    free(connection->prepared);
    free(connection->address);
    const flint_sql_retirement receipt = connection->retirement;
    free(connection);
    flint_sql_retired(receipt);
}

static void *start_connection(void *input)
{
    flint_pg_connection *connection = input;
    PGconn *database = PQconnectStart(connection->address);
    pthread_mutex_lock(&connection->startup_lock);
    connection->database = database;
    connection->starter_active = 0;
    const int abandoned = connection->abandoned;
    if (!abandoned) {
#if defined(__APPLE__) || defined(_WIN32)
        flint_wake_signal(connection->startup_writer);
#else
        uint64_t ready = 1;
        while (write(connection->startup_event, &ready, sizeof(ready)) < 0 && errno == EINTR) {}
#endif
    }
    pthread_mutex_unlock(&connection->startup_lock);
    if (abandoned)
        free_connection(connection);
    return NULL;
}

flint_pg_connection *flint_pg_open(const flint_sql_backend_options *options)
{
    flint_pg_connection *connection = calloc(1, sizeof(*connection));
    if (!connection)
        return NULL;
    connection->address = strdup(options->address);
    connection->capacity = options->prepared;
    if (connection->capacity)
        connection->prepared = calloc(connection->capacity, sizeof(connection->prepared[0]));
    if (!connection->address || (connection->capacity && !connection->prepared))
        goto fail_allocations;

#if defined(__APPLE__) || defined(_WIN32)
    if (flint_wake_open(&connection->startup_event, &connection->startup_writer))
        goto fail_allocations;
#else
    connection->startup_event = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    if (connection->startup_event < 0)
        goto fail_allocations;
#endif
    if (pthread_mutex_init(&connection->startup_lock, NULL))
        goto fail_descriptor;
    pthread_attr_t attr;
    if (pthread_attr_init(&attr))
        goto fail_mutex;
    connection->starter_active = 1;
    int error = pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t thread;
    if (!error)
        error = pthread_create(&thread, &attr, start_connection, connection);
    pthread_attr_destroy(&attr);
    if (!error)
        return connection;
fail_mutex:
    pthread_mutex_destroy(&connection->startup_lock);
fail_descriptor:
#if defined(__APPLE__) || defined(_WIN32)
    flint_wake_close(connection->startup_event, connection->startup_writer);
#else
    close(connection->startup_event);
#endif
fail_allocations:
    free(connection->prepared);
    free(connection->address);
    free(connection);
    return NULL;
}

flint_pg_connection *flint_pg_connect_start(const char *connection_string)
{
    if (!connection_string || !flint_pg_available())
        return NULL;
    const flint_sql_backend_options options = {connection_string, 0};
    return flint_pg_open(&options);
}

int flint_pg_connect_poll(flint_pg_connection *connection, intptr_t *socket)
{
    *socket = -1;
    if (!connection)
        return PGRES_POLLING_FAILED;
    pthread_mutex_lock(&connection->startup_lock);
    int starting = connection->starter_active;
    pthread_mutex_unlock(&connection->startup_lock);
    if (starting) {
        *socket = connection->startup_event;
        return PGRES_POLLING_READING;
    }

    PGconn *database = connection->database;
    if (!database || PQstatus(database) == CONNECTION_BAD)
        return PGRES_POLLING_FAILED;
    if (connection->ready) {
        *socket = PQsocket(database);
        return PGRES_POLLING_OK;
    }
    if (!connection->poll_started) {
        connection->poll_started = 1;
        *socket = PQsocket(database);
        return *socket == -1 ? PGRES_POLLING_FAILED : PGRES_POLLING_WRITING;
    }
    int status = PQconnectPoll(database);
    *socket = PQsocket(database);
    if (status == PGRES_POLLING_OK) {
        if (PQsetnonblocking(database, 1) || strcmp(PQparameterStatus(database, "client_encoding") ?
                PQparameterStatus(database, "client_encoding") : "", "UTF8"))
            return PGRES_POLLING_FAILED;
        connection->ready = 1;
    }
    return status;
}

int flint_pg_send(flint_pg_connection *connection, const char *query,
                  size_t count, const char *const *values,
                  const int *lengths, const int *formats)
{
    return connection && connection->ready && count <= 65535 &&
           PQsendQueryParams(connection->database, query, (int)count, NULL, values, lengths, formats, 0);
}

int flint_pg_consume(flint_pg_connection *connection)
{
    return connection && connection->ready && PQconsumeInput(connection->database);
}

int flint_pg_cancel_start(flint_pg_connection *connection)
{
    if (!connection || !connection->ready || connection->cancellation)
        return 0;
    connection->cancellation = PQcancelCreate(connection->database);
    return connection->cancellation && PQcancelStart(connection->cancellation);
}

int flint_pg_cancel_poll(flint_pg_connection *connection)
{
    if (!connection || !connection->cancellation)
        return PGRES_POLLING_FAILED;
    return PQcancelPoll(connection->cancellation);
}

void flint_pg_retire(flint_pg_connection *connection, flint_sql_retirement receipt)
{
    if (!connection)
        return;
    pthread_mutex_lock(&connection->startup_lock);
    int still_starting = connection->starter_active;
    connection->abandoned = still_starting;
    connection->retirement = receipt;
    pthread_mutex_unlock(&connection->startup_lock);
    if (!still_starting)
        free_connection(connection);
}

void flint_pg_close(flint_pg_connection *connection)
{
    flint_pg_retire(connection, (flint_sql_retirement){0});
}

static uint64_t network_load(const void *data, size_t length)
{
    const unsigned char *bytes = data;
    uint64_t result = 0;
    for (size_t index = 0; index < length; ++index)
        result = (result << 8) | bytes[index];
    return result;
}

static void network_store(unsigned char *bytes, uint64_t value)
{
    for (unsigned index = 8; index > 0; --index) {
        bytes[index - 1] = (unsigned char)value;
        value >>= 8;
    }
}

static Oid parameter_type(int kind)
{
    static const Oid types[] = {0, OID_BOOL, OID_INT8, OID_FLOAT8, OID_TEXT, OID_BYTEA, OID_DATE, OID_TIME,
                                OID_TIMESTAMP};
    return types[kind];
}

static int cacheable(const char *sql)
{
    while (*sql == ' ' || (*sql >= '\t' && *sql <= '\r'))
        ++sql;
    /* Transaction control is prepared too, as pgjdbc does: every transaction otherwise re-parses its BEGIN
       and COMMIT (owner decision 355068f5, the Java reference's statements). */
    const char *verbs[] = {"SELECT", "INSERT", "UPDATE", "DELETE", "VALUES", "WITH", "MERGE",
                           "BEGIN", "COMMIT", "ROLLBACK", "START"};
    for (size_t index = 0; index < sizeof(verbs) / sizeof(verbs[0]); ++index) {
        size_t length = strlen(verbs[index]);
        if (!strncasecmp(sql, verbs[index], length)) {
            char next = sql[length];
            if (next == '\0' || next == ' ' || (next >= '\t' && next <= '\r') || next == '(')
                return 1;
        }
    }
    return 0;
}

static int type_match(const prepared_entry *entry, const flint_sql_operation *operation)
{
    if (entry->count != operation->parameter_count)
        return 0;
    for (size_t index = 0; index < entry->count; ++index) {
        if (entry->types[index] != parameter_type(operation->params[index].cell.kind))
            return 0;
    }
    return 1;
}

/* The cache slot of the operation's statement, *hit set when that slot holds it prepared with the same parameter
   types; otherwise the least recently used slot (to prepare it in), or -1 when it is not cached. */
static int cache_index(flint_pg_connection *connection, const flint_sql_operation *operation, int *hit)
{
    *hit = 0;
    if (!connection->capacity || !cacheable(operation->text))
        return -1;
    const uint64_t key = text_key(operation->text);
    unsigned oldest = 0;
    for (unsigned index = 0; index < connection->capacity; ++index) {
        prepared_entry *entry = &connection->prepared[index];
        if (entry->sql && entry->key == key && !strcmp(entry->sql, operation->text) && type_match(entry, operation)) {
            *hit = 1;
            return (int)index;
        }
        if (entry->touched < connection->prepared[oldest].touched)
            oldest = index;
    }
    return (int)oldest;
}

static void prepared_name(char name[32], unsigned index)
{
    snprintf(name, 32, "flint_sql_%u", index);
}

static int send_prepare(flint_pg_connection *connection, flint_sql_operation *operation)
{
    Oid *types = NULL;
    size_t count = operation->parameter_count;
    if (count) {
        types = malloc(count * sizeof(types[0]));
        if (!types)
            return FLINT_SQL_NOMEM;
        for (size_t index = 0; index < count; ++index)
            types[index] = parameter_type(operation->params[index].cell.kind);
    }
    char name[32];
    prepared_name(name, (unsigned) operation->cache);
    int sent = PQsendPrepare(connection->database, name, operation->text, (int)count, types);
    free(types);
    if (!sent)
        return FLINT_SQL_IO;
    operation->phase = PG_PREPARING;
    return FLINT_SQL_OK;
}

typedef struct {
    unsigned char scalar[8];
    /* ISO-8601 date and time text, NUL-terminated: libpq reads text-format parameters as C strings and ignores
       their lengths, and the caller's bytes are not terminated. The longest java.time form fits. */
    char text[48];
    const char *value;
    int length;
    int format;
    Oid type;
} wire_parameter;

static int write_parameter(wire_parameter *output, const flint_sql_parameter *input)
{
    const flint_sql_cell *cell = &input->cell;
    output->type = parameter_type(cell->kind);
    output->format = 1;
    switch (cell->kind) {
    case FLINT_SQL_NULL:
        break;
    case FLINT_SQL_BOOL:
        output->scalar[0] = (unsigned char)cell->integer;
        output->value = (const char *)output->scalar;
        output->length = 1;
        break;
    case FLINT_SQL_INT:
        network_store(output->scalar, (uint64_t)cell->integer);
        output->value = (const char *)output->scalar;
        output->length = 8;
        break;
    case FLINT_SQL_FLOAT: {
        uint64_t bits;
        memcpy(&bits, &cell->floating, sizeof(bits));
        network_store(output->scalar, bits);
        output->value = (const char *)output->scalar;
        output->length = 8;
        break;
    }
    case FLINT_SQL_DATE: case FLINT_SQL_TIME: case FLINT_SQL_TIMESTAMP:
        /* Text format: the binary forms are day and microsecond counts, not ISO-8601 text. */
        if (cell->length >= sizeof(output->text) || (cell->length && !input->data))
            return FLINT_SQL_INVALID;
        if (cell->length)
            memcpy(output->text, input->data, cell->length);
        output->text[cell->length] = '\0';
        output->format = 0;
        output->value = output->text;
        output->length = (int)cell->length;
        break;
    default:
        output->value = input->data;
        output->length = (int)cell->length;
        break;
    }
    return FLINT_SQL_OK;
}

enum { STACK_PARAMETERS = 16 };

/* Rows arrive in results of up to this many (libpq 17's chunked-rows mode) rather than one result per row: each
   result is one allocation and one PQclear, and the operation walks the rows of a result by row_index. */
enum { CHUNK_ROWS = 128 };

static int send_query(flint_pg_connection *connection, flint_sql_operation *operation)
{
    size_t count = operation->parameter_count;
    /* A statement's few parameters are laid out on the stack; libpq copies them before PQsendQuery* returns. */
    wire_parameter stack_items[STACK_PARAMETERS];
    const char *stack_values[STACK_PARAMETERS];
    int stack_sizes[STACK_PARAMETERS], stack_formats[STACK_PARAMETERS];
    Oid stack_types[STACK_PARAMETERS];
    const int heap = count > STACK_PARAMETERS;
    wire_parameter *items = !count ? NULL : heap ? calloc(count, sizeof(*items)) : stack_items;
    const char **values = !count ? NULL : heap ? malloc(count * sizeof(*values)) : stack_values;
    int *sizes = !count ? NULL : heap ? malloc(count * sizeof(*sizes)) : stack_sizes;
    int *formats = !count ? NULL : heap ? malloc(count * sizeof(*formats)) : stack_formats;
    Oid *types = !count ? NULL : heap ? malloc(count * sizeof(*types)) : stack_types;
    if (count && !heap)
        memset(stack_items, 0, count * sizeof(stack_items[0]));
    int status = FLINT_SQL_NOMEM;
    if (count && (!items || !values || !sizes || !formats || !types))
        goto release;
    for (size_t index = 0; index < count; ++index) {
        status = write_parameter(&items[index], &operation->params[index]);
        if (status != FLINT_SQL_OK)
            goto release;
        values[index] = items[index].value;
        sizes[index] = items[index].length;
        formats[index] = items[index].format;
        types[index] = items[index].type;
    }

    PGconn *database = connection->database;
    int sent;
    if (operation->cache >= 0) {
        char name[32];
        prepared_name(name, (unsigned) operation->cache);
        sent = PQsendQueryPrepared(database, name, (int)count, values, sizes, formats, 1);
    } else {
        sent = PQsendQueryParams(database, operation->text, (int)count, types, values, sizes, formats, 1);
    }

    if (sent && PQsetChunkedRowsMode(database, CHUNK_ROWS)) {
        operation->phase = PG_QUERY;
        status = FLINT_SQL_OK;
    } else
        status = FLINT_SQL_IO;
release:
    if (heap) {
        free(types);
        free(formats);
        free(sizes);
        free(values);
        free(items);
    }
    return status;
}

static int send_script(flint_pg_connection *connection, flint_sql_operation *operation)
{
    PGconn *database = connection->database;
    const char *standard = PQparameterStatus(database, "standard_conforming_strings");
    if (!flint_pg_script_allowed(operation->text, standard && !strcmp(standard, "off")))
        return FLINT_SQL_INVALID;
    if (!PQsendQuery(database, operation->text) || !PQsetChunkedRowsMode(database, CHUNK_ROWS))
        return FLINT_SQL_IO;
    operation->phase = PG_QUERY;
    return FLINT_SQL_OK;
}

/* The prepared statement for text with no parameters, or -1. */
static int prepared_plain(const flint_pg_connection *connection, const char *text)
{
    const uint64_t key = text_key(text);
    for (unsigned index = 0; index < connection->capacity; ++index) {
        const prepared_entry *entry = &connection->prepared[index];
        if (entry->sql && entry->key == key && entry->count == 0 && !strcmp(entry->sql, text))
            return (int)index;
    }
    return -1;
}

/* pgjdbc's way with BEGIN: the preamble and the statement in one pipeline with one Sync, so one round trip.
   Only when both are prepared on this connection (or the statement is not cacheable); otherwise -1 and the
   preamble runs on its own first, through the ordinary phases that prepare it. */
static int send_pipelined(flint_pg_connection *connection, flint_sql_operation *operation)
{
    const int preamble = prepared_plain(connection, operation->preamble);
    if (preamble < 0 || !operation->text[0])
        return -1;
    int hit;
    const int cache = cache_index(connection, operation, &hit);
    if (cache >= 0 && !hit)
        return -1;
    PGconn *database = connection->database;
    char name[32];
    prepared_name(name, (unsigned) preamble);
    connection->prepared[preamble].touched = ++connection->counter;
    if (!PQenterPipelineMode(database) || !PQsendQueryPrepared(database, name, 0, NULL, NULL, NULL, 1))
        return FLINT_SQL_IO;
    operation->cache = cache;
    if (cache >= 0)
        connection->prepared[cache].touched = ++connection->counter;
    const int sent = send_query(connection, operation);
    if (sent != FLINT_SQL_OK)
        return sent;
    if (!PQpipelineSync(database))
        return FLINT_SQL_IO;
    operation->phase = PG_PIPE_PREAMBLE;
    operation->preamble_state = PREAMBLE_PIPELINED;
    return FLINT_SQL_OK;
}

static int start_query(flint_pg_connection *connection, flint_sql_operation *operation)
{
    if (operation->script)
        return send_script(connection, operation);
    if (operation->preamble_state == PREAMBLE_PENDING) {
        const int pipelined = send_pipelined(connection, operation);
        if (pipelined >= 0)
            return pipelined;
        /* The preamble runs first as a statement of its own, then the operation's (resume_after_preamble). */
        operation->saved_text = operation->text;
        operation->saved_count = operation->parameter_count;
        operation->text = operation->preamble;
        operation->preamble = NULL;
        operation->parameter_count = 0;
        operation->preamble_state = PREAMBLE_ALONE;
    }
    /* pgjdbc sends an empty statement (its isValid) as a simple-protocol query; so does Flint, for the same
       messages on the wire and the same line in the server's log. */
    if (!operation->text[0] && !operation->parameter_count) {
        if (!PQsendQuery(connection->database, ""))
            return FLINT_SQL_IO;
        operation->phase = PG_QUERY;
        return FLINT_SQL_OK;
    }
    int hit;
    operation->cache = cache_index(connection, operation, &hit);
    if (operation->cache < 0)
        return send_query(connection, operation);
    prepared_entry *entry = &connection->prepared[operation->cache];
    if (!entry->sql)
        return send_prepare(connection, operation);
    if (hit) {
        entry->touched = ++connection->counter;
        return send_query(connection, operation);
    }
    char name[32];
    prepared_name(name, (unsigned) operation->cache);
    if (!PQsendClosePrepared(connection->database, name))
        return FLINT_SQL_IO;
    operation->phase = PG_EVICTING;
    return FLINT_SQL_OK;
}

static int save_prepared(flint_pg_connection *connection, flint_sql_operation *operation)
{
    prepared_entry *entry = &connection->prepared[operation->cache];
    entry->sql = strdup(operation->text);
    entry->key = entry->sql ? text_key(entry->sql) : 0;
    entry->count = operation->parameter_count;
    entry->types = entry->count ? malloc(entry->count * sizeof(entry->types[0])) : NULL;
    if (!entry->sql || (entry->count && !entry->types)) {
        clear_prepared(entry);
        return FLINT_SQL_NOMEM;
    }
    for (size_t index = 0; index < entry->count; ++index)
        entry->types[index] = parameter_type(operation->params[index].cell.kind);
    entry->touched = ++connection->counter;
    return FLINT_SQL_OK;
}

static int finish_phase(flint_pg_connection *connection, flint_sql_operation *operation)
{
    if (operation->status != FLINT_SQL_OK || atomic_load(&operation->cancelled))
        return FLINT_SQL_COMPLETE;
    int status = FLINT_SQL_OK;
    if (operation->phase == PG_EVICTING) {
        clear_prepared(&connection->prepared[operation->cache]);
        status = send_prepare(connection, operation);
    } else if (operation->phase == PG_PREPARING) {
        status = save_prepared(connection, operation);
        if (status == FLINT_SQL_OK)
            status = send_query(connection, operation);
    } else
        return FLINT_SQL_COMPLETE;
    if (status != FLINT_SQL_OK) {
        operation->status = status;
        operation->reusable = 0;
        return FLINT_SQL_COMPLETE;
    }
    return FLINT_SQL_WAIT;
}

/* The preamble ran on its own and succeeded: put the operation's statement back and send it. */
static int resume_after_preamble(flint_pg_connection *connection, flint_sql_operation *operation)
{
    operation->preamble = operation->text;
    operation->text = operation->saved_text;
    operation->saved_text = NULL;
    operation->parameter_count = operation->saved_count;
    operation->preamble_state = PREAMBLE_NONE;
    operation->phase = PG_UNSENT;
    operation->cache = -1;
    operation->affected = 0;
    return start_query(connection, operation);
}

static int status_for_result(PGresult *result)
{
    const char *state = PQresultErrorField(result, PG_DIAG_SQLSTATE);
    if (!state)
        return FLINT_SQL_IO;
    if (!strcmp(state, "57014"))
        return FLINT_SQL_CANCELLED;
    if (!strncmp(state, "08", 2) || !strncmp(state, "57P", 3))
        return FLINT_SQL_UNAVAILABLE;
    if (!strncmp(state, "23", 2) || !strncmp(state, "40", 2) || !strcmp(state, "55P03"))
        return FLINT_SQL_CONFLICT;
    if (!strncmp(state, "28", 2) || !strcmp(state, "42501"))
        return FLINT_SQL_PERMISSION;
    if (!strncmp(state, "0A", 2))
        return FLINT_SQL_UNSUPPORTED;
    return FLINT_SQL_INVALID;
}

static void command_tuples(flint_sql_operation *operation, PGresult *result)
{
    const char *count = PQcmdTuples(result);
    uint64_t value = 0;
    for (; *count; ++count) {
        unsigned digit = (unsigned)(*count - '0');
        if (digit > 9 || value > (UINT64_MAX - digit) / 10) {
            operation->status = FLINT_SQL_EXHAUSTED;
            return;
        }
        value = value * 10 + digit;
    }
    operation->affected = value;
}

/* True when the statement's first keyword is COMMIT or END (which commit the open transaction). */
static int commits_transaction(const char *text)
{
    if (!text)
        return 0;
    while (*text == ' ' || *text == '\t' || *text == '\r' || *text == '\n')
        ++text;
    static const char *const words[] = {"COMMIT", "END"};
    for (size_t w = 0; w < sizeof words / sizeof words[0]; ++w) {
        size_t i = 0;
        while (words[w][i] && (text[i] & ~0x20) == words[w][i])
            ++i;
        if (!words[w][i] && !((text[i] >= 'A' && text[i] <= 'Z') || (text[i] >= 'a' && text[i] <= 'z')
                              || (text[i] >= '0' && text[i] <= '9') || text[i] == '_'))
            return 1;
    }
    return 0;
}

static int handle_result(flint_sql_operation *operation, PGresult *result)
{
    switch (PQresultStatus(result)) {
    case PGRES_EMPTY_QUERY:
        break;
    case PGRES_SINGLE_TUPLE:
    case PGRES_TUPLES_CHUNK:
    case PGRES_TUPLES_OK:
        if (operation->rows && PQntuples(result) > 0 && !atomic_load(&operation->cancelled)) {
            operation->row = result;
            operation->row_index = 0;
            return FLINT_SQL_ROW;
        }
        command_tuples(operation, result);
        break;
    case PGRES_COMMAND_OK:
        /* PostgreSQL answers COMMIT in an aborted transaction with a successful ROLLBACK. */
        if (commits_transaction(operation->text) && !strcmp(PQcmdStatus(result), "ROLLBACK")) {
            if (operation->status == FLINT_SQL_OK)
                operation->status = FLINT_SQL_CONFLICT;
            /* pgjdbc reports this as in_failed_sql_transaction. */
            flint_sql_note_failure(operation, "25P02", 0,
                                   "the transaction was aborted, so COMMIT rolled it back");
            break;
        }
        if (operation->phase == PG_QUERY)
            command_tuples(operation, result);
        break;
    case PGRES_COPY_IN: case PGRES_COPY_OUT: case PGRES_COPY_BOTH:
        operation->status = FLINT_SQL_UNSUPPORTED;
        operation->reusable = 0;
        break;
    default:
        if (operation->status == FLINT_SQL_OK)
            operation->status = status_for_result(result);
        flint_sql_note_failure(operation, PQresultErrorField(result, PG_DIAG_SQLSTATE), 0,
                               PQresultErrorField(result, PG_DIAG_MESSAGE_PRIMARY));
        if (operation->status == FLINT_SQL_UNAVAILABLE)
            operation->reusable = 0;
        break;
    }
    PQclear(result);
    return FLINT_SQL_WAIT;
}

static int poll_cancellation(flint_pg_connection *connection, flint_sql_operation *operation,
                             int *fd, unsigned *interest)
{
    if (!operation->cancel_started) {
        operation->cancel_started = 1;
        if (!flint_pg_cancel_start(connection))
            return PGRES_POLLING_FAILED;
        *fd = PQcancelSocket(connection->cancellation);
        *interest = FLINT_SQL_WRITE;
        return PGRES_POLLING_WRITING;
    }
    if (operation->cancel_done)
        return PGRES_POLLING_OK;
    int state = flint_pg_cancel_poll(connection);
    if (state == PGRES_POLLING_OK) {
        PQcancelFinish(connection->cancellation);
        connection->cancellation = NULL;
        operation->cancel_done = 1;
    } else {
        *fd = PQcancelSocket(connection->cancellation);
        *interest = state == PGRES_POLLING_READING ? FLINT_SQL_READ : FLINT_SQL_WRITE;
    }
    return state;
}

static int finish(flint_pg_connection *connection, flint_sql_operation *operation, int status)
{
    if (status != FLINT_SQL_OK)
        operation->status = status;
    if (connection->ready) {
        PGTransactionStatusType transaction = PQtransactionStatus(connection->database);
        operation->dirty = transaction == PQTRANS_INTRANS || transaction == PQTRANS_INERROR;
        if (transaction == PQTRANS_UNKNOWN || transaction == PQTRANS_ACTIVE)
            operation->reusable = 0;
    } else
        operation->reusable = 0;
    return FLINT_SQL_COMPLETE;
}

static int step_connect(flint_pg_connection *connection, flint_sql_operation *operation,
                        int *fd, unsigned *interest)
{
    intptr_t socket = -1;
    int status = flint_pg_connect_poll(connection, &socket);
    *fd = (int)socket;
    *interest = status == PGRES_POLLING_READING ? FLINT_SQL_READ : FLINT_SQL_WRITE;
    if (status == PGRES_POLLING_FAILED) {
        /* 08001: sqlclient_unable_to_establish_sqlconnection. */
        flint_sql_note_failure(operation, "08001", 0, connection->database
                ? PQerrorMessage(connection->database) : "could not start the PostgreSQL connection");
        return finish(connection, operation, FLINT_SQL_UNAVAILABLE);
    }
    return FLINT_SQL_WAIT;
}

int flint_pg_drive(flint_pg_connection *connection, flint_sql_operation *operation,
                  int *fd, unsigned *interest)
{
    if (operation->row)
        return FLINT_SQL_ROW;
    if (atomic_load(&operation->cancelled)) {
        if (operation->phase == PG_UNSENT)
            return finish(connection, operation, FLINT_SQL_CANCELLED);
        const int cancellation = poll_cancellation(connection, operation, fd, interest);
        if (cancellation == PGRES_POLLING_FAILED) {
            operation->reusable = 0;
            return finish(connection, operation, FLINT_SQL_CANCELLED);
        }
        if (cancellation != PGRES_POLLING_OK)
            return FLINT_SQL_WAIT;
    }
    if (!connection->ready)
        return step_connect(connection, operation, fd, interest);
    /* The socket is read only when libpq needs more input, at most once per call: not in the call that sent
       the statement (no answer can be there yet; readiness brings the next call), and not while libpq holds
       unread results (one read can hold several of them). */
    int read = 0;
    if (operation->phase == PG_UNSENT) {
        const int state = start_query(connection, operation);
        if (state != FLINT_SQL_OK) {
            if (state == FLINT_SQL_IO)
                operation->reusable = 0;
            return finish(connection, operation, state);
        }
        read = 1;
    }

    PGconn *database = connection->database;
    *fd = PQsocket(database);
    *interest = FLINT_SQL_READ;
    const int flushed = PQflush(database);
    if (flushed < 0) {
        operation->reusable = 0;
        return finish(connection, operation, FLINT_SQL_UNAVAILABLE);
    }
    if (flushed > 0) {
        /* libpq: while output is pending, input is consumed too, so a server blocked on its own writes drains. */
        if (!flint_pg_consume(connection)) {
            operation->reusable = 0;
            return finish(connection, operation, FLINT_SQL_UNAVAILABLE);
        }
        *interest |= FLINT_SQL_WRITE;
        return FLINT_SQL_WAIT;
    }
    for (unsigned results = 0; results < 32; ++results) {
        if (PQisBusy(database)) {
            if (read)
                return FLINT_SQL_WAIT;
            read = 1;
            if (!flint_pg_consume(connection)) {
                operation->reusable = 0;
                return finish(connection, operation, FLINT_SQL_UNAVAILABLE);
            }
            if (PQisBusy(database))
                return FLINT_SQL_WAIT;
        }
        PGresult *result = PQgetResult(database);
        if (operation->preamble_state == PREAMBLE_PIPELINED) {
            /* Preamble's result, NULL, the statement's results, NULL, then the Sync's result. */
            if (result && PQresultStatus(result) == PGRES_PIPELINE_SYNC) {
                PQclear(result);
                operation->preamble_state = PREAMBLE_NONE;
                if (!PQexitPipelineMode(database))
                    operation->reusable = 0;
                return finish(connection, operation, FLINT_SQL_OK);
            }
            if (!result) {
                if (operation->phase == PG_PIPE_PREAMBLE)
                    operation->phase = PG_QUERY;
                else
                    operation->phase = PG_PIPE_SYNC;
                if (atomic_load(&operation->cancelled))
                    operation->reusable = 0;
                continue;
            }
            if (operation->phase == PG_PIPE_PREAMBLE && PQresultStatus(result) == PGRES_COMMAND_OK) {
                PQclear(result);
                continue;
            }
        }
        if (!result) {
            if (atomic_load(&operation->cancelled) && operation->phase != PG_QUERY)
                operation->reusable = 0;
            if (operation->preamble_state == PREAMBLE_ALONE && operation->status == FLINT_SQL_OK &&
                !atomic_load(&operation->cancelled) && operation->phase == PG_QUERY) {
                const int resumed = resume_after_preamble(connection, operation);
                if (resumed != FLINT_SQL_OK) {
                    if (resumed == FLINT_SQL_IO)
                        operation->reusable = 0;
                    return finish(connection, operation, resumed);
                }
                *interest = FLINT_SQL_READ | FLINT_SQL_WRITE;
                return FLINT_SQL_WAIT;
            }
            const int transition = finish_phase(connection, operation);
            if (transition == FLINT_SQL_WAIT)
                *interest = FLINT_SQL_READ | FLINT_SQL_WRITE;
            return transition == FLINT_SQL_COMPLETE ? finish(connection, operation, FLINT_SQL_OK) : transition;
        }
        const int progress = handle_result(operation, result);
        if (progress == FLINT_SQL_ROW)
            return progress;
        if (!operation->reusable)
            return finish(connection, operation, FLINT_SQL_OK);
    }
    *fd = -1;
    *interest = 0;
    return FLINT_SQL_WAIT;
}

uint32_t flint_pg_columns(const flint_sql_operation *operation)
{
    return operation->row ? (uint32_t)PQnfields(operation->row) : 0;
}

const char *flint_pg_name(const flint_sql_operation *operation, uint32_t index)
{
    PGresult *row = operation->row;
    return row && index < (uint32_t)PQnfields(row) ? PQfname(row, (int)index) : NULL;
}

static int decode_integer(flint_sql_cell *cell, Oid type, const void *data, size_t length)
{
    const size_t expected = type == OID_INT8 ? 8 : type == OID_INT4 ? 4 : 2;
    if (length != expected)
        return FLINT_SQL_IO;
    uint64_t unsigned_value = network_load(data, length);
    if (expected < 8 && (unsigned_value & (UINT64_C(1) << (expected * 8 - 1))))
        unsigned_value |= UINT64_MAX << (expected * 8);
    int64_t value;
    memcpy(&value, &unsigned_value, sizeof(value));
    *cell = (flint_sql_cell){.kind = FLINT_SQL_INT, .integer = value};
    return FLINT_SQL_OK;
}

static int decode_float(flint_sql_cell *cell, Oid type, const void *data, size_t length)
{
    double value;
    if (type == OID_FLOAT8 && length == 8) {
        const uint64_t bits = network_load(data, length);
        memcpy(&value, &bits, sizeof(value));
    } else if (type == OID_FLOAT4 && length == 4) {
        const uint32_t bits = (uint32_t)network_load(data, length);
        float smaller;
        memcpy(&smaller, &bits, sizeof(smaller));
        value = smaller;
    } else
        return FLINT_SQL_IO;
    if (!isfinite(value))
        return FLINT_SQL_INVALID;
    *cell = (flint_sql_cell){.kind = FLINT_SQL_FLOAT, .floating = value};
    return FLINT_SQL_OK;
}

/* The proleptic Gregorian date of a day count from 1970-01-01 (H. Hinnant's civil_from_days). */
static void civil_from_days(int64_t z, int64_t *year, unsigned *month, unsigned *day)
{
    z += 719468;
    const int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    const unsigned doe = (unsigned)(z - era * 146097);
    const unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const unsigned mp = (5 * doy + 2) / 153;
    *day = doy - (153 * mp + 2) / 5 + 1;
    *month = mp < 10 ? mp + 3 : mp - 9;
    *year = (int64_t)yoe + era * 400 + (*month <= 2);
}

/* PostgreSQL's epoch, 2000-01-01, in days from 1970-01-01. */
enum { PG_EPOCH_DAYS = 10957 };
static const int64_t MICROS_PER_DAY = INT64_C(86400000000);

/*
 * Binary date, time and timestamp cells as ISO-8601 text, as java.time parses them. The text lives in a
 * thread-local buffer: every cell read copies its bytes out under the gate before the next read.
 */
static int decode_temporal(flint_sql_cell *cell, Oid type, const void *bytes, size_t length, const void **data)
{
    static _Thread_local char text[48];
    int64_t year;
    unsigned month, day;
    int written;
    if (type == OID_DATE && length == 4) {
        const int32_t days = (int32_t)(uint32_t)network_load(bytes, length);
        if (days == INT32_MAX || days == INT32_MIN)
            return FLINT_SQL_UNSUPPORTED; /* infinity */
        civil_from_days((int64_t)days + PG_EPOCH_DAYS, &year, &month, &day);
        if (year < 0 || year > 9999)
            return FLINT_SQL_UNSUPPORTED;
        written = snprintf(text, sizeof(text), "%04lld-%02u-%02u", (long long)year, month, day);
    } else if ((type == OID_TIME || type == OID_TIMESTAMP) && length == 8) {
        int64_t micros = (int64_t)network_load(bytes, length);
        if (micros == INT64_MAX || micros == INT64_MIN)
            return FLINT_SQL_UNSUPPORTED; /* infinity */
        int64_t days = micros / MICROS_PER_DAY;
        micros %= MICROS_PER_DAY;
        if (micros < 0) {
            micros += MICROS_PER_DAY;
            days -= 1;
        }
        const unsigned seconds = (unsigned)(micros / 1000000);
        const unsigned fraction = (unsigned)(micros % 1000000);
        int offset = 0;
        if (type == OID_TIMESTAMP) {
            civil_from_days(days + PG_EPOCH_DAYS, &year, &month, &day);
            if (year < 0 || year > 9999)
                return FLINT_SQL_UNSUPPORTED;
            offset = snprintf(text, sizeof(text), "%04lld-%02u-%02uT", (long long)year, month, day);
        }
        written = offset + snprintf(text + offset, sizeof(text) - (size_t)offset, "%02u:%02u:%02u",
                                    seconds / 3600, seconds / 60 % 60, seconds % 60);
        if (fraction)
            written += snprintf(text + written, sizeof(text) - (size_t)written, ".%06u", fraction);
    } else
        return FLINT_SQL_IO;
    if (written <= 0 || (size_t)written >= sizeof(text))
        return FLINT_SQL_IO;
    *data = text;
    *cell = (flint_sql_cell){.kind = FLINT_SQL_TEXT, .length = (size_t)written};
    return FLINT_SQL_OK;
}

int flint_pg_cell(const flint_sql_operation *operation, uint32_t index, flint_sql_cell *cell,
                  const void **data)
{
    PGresult *row = operation->row;
    int position = (int)operation->row_index;
    if (!row || index >= (uint32_t)PQnfields(row))
        return FLINT_SQL_INVALID;
    if (PQgetisnull(row, position, (int)index)) {
        *cell = (flint_sql_cell){.kind = FLINT_SQL_NULL};
        return FLINT_SQL_OK;
    }
    const void *bytes = PQgetvalue(row, position, (int)index);
    size_t length = (size_t)PQgetlength(row, position, (int)index);
    Oid type = PQftype(row, (int)index);
    switch (type) {
    case OID_BOOL:
        if (length != 1 || *(const unsigned char *)bytes > 1)
            return FLINT_SQL_IO;
        *cell = (flint_sql_cell){.kind = FLINT_SQL_BOOL, .integer = *(const unsigned char *)bytes};
        return FLINT_SQL_OK;
    case OID_INT2: case OID_INT4: case OID_INT8:
        return decode_integer(cell, type, bytes, length);
    case OID_FLOAT4: case OID_FLOAT8:
        return decode_float(cell, type, bytes, length);
    case OID_TEXT: case OID_NAME: case OID_BPCHAR: case OID_VARCHAR:
        if (!flint_sql_utf8(bytes, length))
            return FLINT_SQL_INVALID;
        *data = bytes;
        *cell = (flint_sql_cell){.kind = FLINT_SQL_TEXT, .length = length};
        return FLINT_SQL_OK;
    case OID_BYTEA:
        *data = bytes;
        *cell = (flint_sql_cell){.kind = FLINT_SQL_BYTES, .length = length};
        return FLINT_SQL_OK;
    case OID_OID:
        /* An object identifier: unsigned 32 bits (pg_catalog's atttypid, typbasetype). */
        if (length != 4)
            return FLINT_SQL_IO;
        *cell = (flint_sql_cell){.kind = FLINT_SQL_INT, .integer = (int64_t)network_load(bytes, 4)};
        return FLINT_SQL_OK;
    case OID_CHAR:
        /* The one-byte "char" (pg_catalog's typtype, attidentity): text; its zero byte is the empty string, as
           PostgreSQL prints it. */
        if (length != 1)
            return FLINT_SQL_IO;
        length = *(const unsigned char *)bytes ? 1 : 0;
        if (!flint_sql_utf8(bytes, length))
            return FLINT_SQL_INVALID;
        *data = bytes;
        *cell = (flint_sql_cell){.kind = FLINT_SQL_TEXT, .length = length};
        return FLINT_SQL_OK;
    case OID_DATE: case OID_TIME: case OID_TIMESTAMP:
        return decode_temporal(cell, type, bytes, length, data);
    default:
        return FLINT_SQL_UNSUPPORTED;
    }
}

void flint_pg_discard(flint_sql_operation *operation)
{
    if (operation->row)
        PQclear(operation->row);
    operation->row = NULL;
}

void flint_pg_next(flint_sql_operation *operation)
{
    if (operation->row && ++operation->row_index >= (uint32_t)PQntuples(operation->row))
        flint_pg_discard(operation);
}

/* The driver table: the core reaches libpq only through it, and only flint_sql_enable_postgres refers to it. */
static void *driver_open(const flint_sql_backend_options *options)
{
    return flint_pg_open(options);
}

static int driver_drive(void *connection, flint_sql_operation *operation, int *fd, unsigned *interest)
{
    return flint_pg_drive(connection, operation, fd, interest);
}

static void driver_next(void *connection, flint_sql_operation *operation)
{
    (void)connection;
    flint_pg_next(operation);
}

static void driver_retire(void *connection, flint_sql_retirement receipt)
{
    flint_pg_retire(connection, receipt);
}

static const flint_sql_driver postgres_driver = {
    .open = driver_open,
    .begin = NULL,
    .drive = driver_drive,
    .preambles = 1,
    .interrupt = NULL,
    .abandon = NULL,
    .discard = flint_pg_discard,
    .columns = flint_pg_columns,
    .cell = flint_pg_cell,
    .name = flint_pg_name,
    .next = driver_next,
    .retire = driver_retire,
};

int flint_sql_enable_postgres(void)
{
    if (!flint_pg_available())
        return FLINT_SQL_UNSUPPORTED;
    return flint_sql_register_driver(FLINT_SQL_DRIVER_POSTGRES, &postgres_driver);
}

#else

int flint_sql_enable_postgres(void)
{
    return FLINT_SQL_UNSUPPORTED;
}

#endif
