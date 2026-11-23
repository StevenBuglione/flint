#include "flint_abi_probe.h"
#include <string.h>
#if defined(_MSC_VER)
#define FLINT_ALIGNOF(T) __alignof(T)
#else
#define FLINT_ALIGNOF(T) _Alignof(T)
#endif
#ifdef FLINT_HAS_LLHTTP
#include <llhttp.h>
#endif
#ifdef FLINT_HAS_NGHTTP2
#if defined(_MSC_VER) && !defined(__clang__)
#include <BaseTsd.h>
typedef SSIZE_T ssize_t; /* nghttp2.h's callbacks return ssize_t, which MSVC does not define (ADR-026) */
#endif
#include <nghttp2/nghttp2.h>
#endif
#ifdef FLINT_HAS_CURL
#include <curl/curl.h>
#endif
#ifdef FLINT_HAS_SQLITE
#include <sqlite3.h>
#endif
_Static_assert(sizeof(flint_abi_info) == 48, "Flint ABI record layout changed");
int flint_abi_probe(flint_abi_info *output, size_t output_bytes) {
    if (!output || output_bytes != sizeof(flint_abi_info)) return -1;
    flint_abi_info result = {0};
    const uint16_t endian = 1;
    result.abi_version = 1; result.struct_bytes = sizeof(result);
    result.pointer_bytes = sizeof(void *); result.size_t_bytes = sizeof(size_t);
    result.long_bytes = sizeof(long); result.little_endian = *((const unsigned char *)&endian) == 1;
#ifdef FLINT_HAS_LLHTTP
    result.llhttp_bytes = sizeof(llhttp_t); result.llhttp_alignment = FLINT_ALIGNOF(llhttp_t);
#endif
#ifdef FLINT_HAS_NGHTTP2
    result.nghttp2_nv_bytes = sizeof(nghttp2_nv); result.nghttp2_nv_alignment = FLINT_ALIGNOF(nghttp2_nv);
#endif
#ifdef FLINT_HAS_CURL
    result.curl_off_t_bytes = sizeof(curl_off_t);
#endif
#ifdef FLINT_HAS_SQLITE
    result.sqlite_int64_bytes = sizeof(sqlite3_int64);
#endif
    memcpy(output, &result, sizeof(result));
    return 0;
}
