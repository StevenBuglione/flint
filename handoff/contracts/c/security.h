/* Versioned Flint shim contract; implementations must wrap pinned upstream libraries. */
#ifndef FLINT_SECURITY_ABI_H
#define FLINT_SECURITY_ABI_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int flint_sha256(const uint8_t *input, size_t input_length, uint8_t output[32]);
int flint_hmac_sha256(const uint8_t *key, size_t key_length,
                      const uint8_t *input, size_t input_length, uint8_t output[32]);
int flint_jws_verify(int algorithm, const uint8_t *key_der, size_t key_length,
                     const uint8_t *input, size_t input_length,
                     const uint8_t *signature, size_t signature_length);
int flint_password_hash(const uint8_t *password, size_t password_length,
                         char *output, size_t output_capacity,
                         uint64_t opslimit, size_t memlimit);
int flint_password_verify(const char *encoded, const uint8_t *password,
                           size_t password_length);
#ifdef __cplusplus
}
#endif
#endif
