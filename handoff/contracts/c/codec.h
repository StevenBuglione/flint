/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_CODEC_ABI_H
#define FLINT_CODEC_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_codec_state flint_codec_state;
flint_codec_state *flint_codec_new(int codec, int encode, int level);
int flint_codec_step(flint_codec_state *state, const uint8_t *input,
                     size_t input_length, size_t *consumed,
                     uint8_t *output, size_t output_capacity,
                     size_t *produced, int finish);
void flint_codec_free(flint_codec_state *state);
typedef struct flint_archive flint_archive;
typedef int (*flint_archive_read_cb)(void *user, uint8_t *output,
                                     size_t capacity, size_t *written);
typedef int (*flint_archive_write_cb)(void *user, const uint8_t *input,
                                      size_t length);
flint_archive *flint_archive_reader_new(int format, flint_archive_read_cb read,
                                        void *user, uint64_t max_output_bytes);
flint_archive *flint_archive_writer_new(int format, flint_archive_write_cb write,
                                        void *user);
int flint_archive_next(flint_archive *archive, uint8_t *path,
                        size_t path_capacity, size_t *path_length,
                        uint64_t *size, int *directory);
int flint_archive_read(flint_archive *archive, uint8_t *output,
                        size_t capacity, size_t *written);
int flint_archive_entry(flint_archive *archive, const char *path,
                         uint64_t size, int directory);
int flint_archive_write(flint_archive *archive, const uint8_t *input, size_t length);
int flint_archive_close(flint_archive *archive);
#ifdef __cplusplus
}
#endif
#endif
