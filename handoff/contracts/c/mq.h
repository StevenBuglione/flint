/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_MQ_ABI_H
#define FLINT_MQ_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_kafka_client flint_kafka_client;
flint_kafka_client *flint_kafka_new(const char *brokers, const char *client_id);
int flint_kafka_produce(flint_kafka_client *client, const char *topic,
                        const uint8_t *key, size_t key_length,
                        const uint8_t *payload, size_t payload_length,
                        uint64_t token);
int flint_kafka_poll(flint_kafka_client *client, int timeout_ms);
int flint_kafka_commit(flint_kafka_client *client, const char *topic,
                       int32_t partition, int64_t next_offset);
int flint_kafka_flush(flint_kafka_client *client, int timeout_ms);
void flint_kafka_free(flint_kafka_client *client);
#ifdef __cplusplus
}
#endif
#endif
