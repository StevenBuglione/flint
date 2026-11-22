#ifndef FLINT_ABI_PROBE_H
#define FLINT_ABI_PROBE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct flint_abi_info {
    uint32_t abi_version, struct_bytes, pointer_bytes, size_t_bytes;
    uint32_t long_bytes, little_endian, llhttp_bytes, llhttp_alignment;
    uint32_t nghttp2_nv_bytes, nghttp2_nv_alignment, curl_off_t_bytes, sqlite_int64_bytes;
} flint_abi_info;
int flint_abi_probe(flint_abi_info *output, size_t output_bytes);
#ifdef __cplusplus
}
#endif
#endif
