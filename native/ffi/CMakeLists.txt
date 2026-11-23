cmake_minimum_required(VERSION 3.20)
project(flint_ffi C)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
# The flint repo's Flint C shims (plan section 7): flint_ffi_base wraps libyaml, utf8proc and the ABI probe, the
# closure of the flint repo's packages. The engines' shims live beside their packages and build into
# flint_ffi_framework from native/framework (flint-framework's native/ after the split). tools/native_build.py builds
# this project first, and FLINT_FFI_BASE_SHIMS must match its BASE_SHIMS.
set(FLINT_FFI_BASE_SHIMS flint_abi_probe.c flint_utf8proc.c flint_yaml.c)
add_library(flint_ffi_base STATIC ${FLINT_FFI_BASE_SHIMS})
set(flint_ffi flint_ffi_base)
target_include_directories(${flint_ffi} PRIVATE "${CMAKE_INSTALL_PREFIX}/include")
# One section per function and object, so a linked program keeps only the shim entry points it reaches
# (and the providers behind them) rather than every function that shares a translation unit with one.
if(NOT MSVC)
  target_compile_options(${flint_ffi} PRIVATE -ffunction-sections -fdata-sections)
else()
  # MSVC: C11 atomics are opt-in, and /Gy is its per-function sectioning.
  target_compile_options(${flint_ffi} PRIVATE /experimental:c11atomics /Gy)
  # _NO_CRT_STDIO_INLINE: the UCRT headers otherwise define snprintf, vsnprintf and their helpers as external
  # inline COMDATs in every shim that prints. druntime references snprintf too, and link.exe would then load
  # whichever shim object it meets first, with that shim's provider, into a program that never calls it
  # (engine-wasi pulled in libpq and SQLite). With it, those calls bind to legacy_stdio_definitions.lib (ADR-026).
  target_compile_definitions(${flint_ffi} PRIVATE _NO_CRT_STDIO_INLINE)
endif()
# The providers are static archives. Their Windows headers declare DLL imports unless told otherwise.
if(WIN32)
  target_compile_definitions(${flint_ffi} PRIVATE UTF8PROC_STATIC CURL_STATICLIB NGHTTP2_STATICLIB YAML_DECLARE_STATIC
    LIBARCHIVE_STATIC SODIUM_STATIC)
endif()
# The shims request POSIX.1-2008, which hides Darwin's own declarations (SO_NOSIGPIPE, F_SETNOSIGPIPE,
# statfs's f_fstypename). Darwin keeps them visible alongside the POSIX set (ADR-024).
if(APPLE)
  target_compile_definitions(${flint_ffi} PRIVATE _DARWIN_C_SOURCE)
endif()
# Wasmtime is a static archive in this profile; Windows headers must not emit DLL imports.
if(WIN32 AND EXISTS "${CMAKE_INSTALL_PREFIX}/include/wasmtime.h")
  target_compile_definitions(${flint_ffi} PRIVATE WASM_API_EXTERN= WASI_API_EXTERN=)
endif()
foreach(PAIR IN ITEMS "llhttp.h|LLHTTP" "nghttp2/nghttp2.h|NGHTTP2" "curl/curl.h|CURL" "openssl/ssl.h|OPENSSL"
    "sqlite3.h|SQLITE" "libpq-fe.h|LIBPQ" "hiredis/hiredis_ssl.h|HIREDIS" "sodium.h|LIBSODIUM"
    "librdkafka/rdkafka.h|LIBRDKAFKA" "protobuf-c/protobuf-c.h|PROTOBUF_C" "yaml.h|LIBYAML" "utf8proc.h|UTF8PROC"
    "zlib.h|ZLIB" "zstd.h|ZSTD" "brotli/decode.h|BROTLI" "archive.h|LIBARCHIVE")
  string(REPLACE "|" ";" FIELDS "${PAIR}")
  list(GET FIELDS 0 HEADER)
  list(GET FIELDS 1 SYMBOL)
  if(EXISTS "${CMAKE_INSTALL_PREFIX}/include/${HEADER}")
    target_compile_definitions(${flint_ffi} PRIVATE "FLINT_HAS_${SYMBOL}=1")
  endif()
endforeach()
add_executable(flint_abi_test probe_main.c)
target_link_libraries(flint_abi_test PRIVATE flint_ffi_base)
enable_testing()
add_test(NAME flint_abi_test COMMAND flint_abi_test)
install(TARGETS flint_ffi_base ARCHIVE DESTINATION lib)
install(FILES flint_abi_probe.h DESTINATION include)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_yaml.h" AND EXISTS "${CMAKE_INSTALL_PREFIX}/include/yaml.h")
  install(FILES flint_yaml.h DESTINATION include)
endif()
if(EXISTS "${CMAKE_INSTALL_PREFIX}/include/utf8proc.h")
  install(FILES flint_utf8proc.h DESTINATION include)
endif()
