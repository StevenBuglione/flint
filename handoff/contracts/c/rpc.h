/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_RPC_ABI_H
#define FLINT_RPC_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_proto_descriptor flint_proto_descriptor;
int flint_proto_pack(const flint_proto_descriptor *descriptor, const void *message,
                     uint8_t *output, size_t capacity, size_t *written);
int flint_proto_unpack(const flint_proto_descriptor *descriptor,
                       const uint8_t *input, size_t input_length,
                       void *arena_context, void **message);
void flint_proto_release(const flint_proto_descriptor *descriptor,
                        void *message, void *arena_context);
#ifdef __cplusplus
}
#endif
#endif
