cmake_minimum_required(VERSION 3.20)
project(flint_ffi C)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
file(GLOB FLINT_SHIMS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/flint_*.c")
add_library(flint_ffi STATIC ${FLINT_SHIMS})
target_include_directories(flint_ffi PRIVATE "${CMAKE_INSTALL_PREFIX}/include")
# Wasmtime is a static archive in this profile; Windows headers must not emit DLL imports.
if(WIN32 AND EXISTS "${CMAKE_INSTALL_PREFIX}/include/wasmtime.h")
  target_compile_definitions(flint_ffi PRIVATE WASM_API_EXTERN= WASI_API_EXTERN=)
endif()
foreach(PAIR IN ITEMS "llhttp.h|LLHTTP" "nghttp2/nghttp2.h|NGHTTP2" "curl/curl.h|CURL" "openssl/ssl.h|OPENSSL"
    "sqlite3.h|SQLITE" "libpq-fe.h|LIBPQ" "hiredis/hiredis_ssl.h|HIREDIS" "sodium.h|LIBSODIUM"
    "librdkafka/rdkafka.h|LIBRDKAFKA" "protobuf-c/protobuf-c.h|PROTOBUF_C" "yaml.h|LIBYAML" "utf8proc.h|UTF8PROC"
    "zlib.h|ZLIB" "zstd.h|ZSTD" "brotli/decode.h|BROTLI" "archive.h|LIBARCHIVE")
  string(REPLACE "|" ";" FIELDS "${PAIR}")
  list(GET FIELDS 0 HEADER)
  list(GET FIELDS 1 SYMBOL)
  if(EXISTS "${CMAKE_INSTALL_PREFIX}/include/${HEADER}")
    target_compile_definitions(flint_ffi PRIVATE "FLINT_HAS_${SYMBOL}=1")
  endif()
endforeach()
add_executable(flint_abi_test probe_main.c)
target_link_libraries(flint_abi_test PRIVATE flint_ffi)
enable_testing()
add_test(NAME flint_abi_test COMMAND flint_abi_test)
install(TARGETS flint_ffi ARCHIVE DESTINATION lib)
install(FILES flint_abi_probe.h DESTINATION include)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_codec.h" AND
    (EXISTS "${CMAKE_INSTALL_PREFIX}/include/zlib.h" OR EXISTS "${CMAKE_INSTALL_PREFIX}/include/zstd.h" OR
     EXISTS "${CMAKE_INSTALL_PREFIX}/include/brotli/decode.h" OR EXISTS "${CMAKE_INSTALL_PREFIX}/include/archive.h"))
  install(FILES flint_codec.h DESTINATION include)
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_yaml.h" AND EXISTS "${CMAKE_INSTALL_PREFIX}/include/yaml.h")
  install(FILES flint_yaml.h DESTINATION include)
endif()
if(EXISTS "${CMAKE_INSTALL_PREFIX}/include/utf8proc.h")
  install(FILES flint_utf8proc.h DESTINATION include)
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_http.h" AND EXISTS "${CMAKE_INSTALL_PREFIX}/include/curl/curl.h")
  install(FILES flint_http.h DESTINATION include)
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_web.h" AND EXISTS "${CMAKE_INSTALL_PREFIX}/include/llhttp.h")
  install(FILES flint_web.h DESTINATION include)
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_sql.h" AND
    (EXISTS "${CMAKE_INSTALL_PREFIX}/include/sqlite3.h" OR EXISTS "${CMAKE_INSTALL_PREFIX}/include/libpq-fe.h"))
  install(FILES flint_sql.h DESTINATION include)
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_cache.h" AND
    EXISTS "${CMAKE_INSTALL_PREFIX}/include/hiredis/hiredis_ssl.h")
  install(FILES flint_cache.h DESTINATION include)
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_security.h" AND
    (EXISTS "${CMAKE_INSTALL_PREFIX}/include/openssl/evp.h" OR EXISTS "${CMAKE_INSTALL_PREFIX}/include/sodium.h"))
  install(FILES flint_security.h DESTINATION include)
endif()
if(EXISTS "${CMAKE_INSTALL_PREFIX}/include/librdkafka/rdkafka.h")
  install(FILES flint_mq.h flint_mq_socket.h DESTINATION include)
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_rpc.h" AND
    (EXISTS "${CMAKE_INSTALL_PREFIX}/include/openssl/evp.h" OR
     EXISTS "${CMAKE_INSTALL_PREFIX}/include/protobuf-c/protobuf-c.h"))
  install(FILES flint_rpc.h DESTINATION include)
endif()

# Generated test codecs are deliberately separate from the production FFI archive.
if(EXISTS "${CMAKE_INSTALL_PREFIX}/include/protobuf-c/protobuf-c.h")
  set(FLINT_RPC_TEST_CODECS "${CMAKE_CURRENT_SOURCE_DIR}/../../packages/rpc/tests/generated")
  add_library(flint_rpc_fixture STATIC
    "${FLINT_RPC_TEST_CODECS}/echo.pb-c.c"
    "${FLINT_RPC_TEST_CODECS}/echo_flint.c")
  target_include_directories(flint_rpc_fixture PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_INSTALL_PREFIX}/include")
  install(TARGETS flint_rpc_fixture ARCHIVE DESTINATION lib)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND EXISTS "${CMAKE_INSTALL_PREFIX}/include/liburing.h")
  target_compile_definitions(flint_ffi PRIVATE FLINT_HAS_LIBURING=1)
  install(FILES flint_reactor_uring.h DESTINATION include)
  find_library(FLINT_URING NAMES liburing.a PATHS "${CMAKE_INSTALL_PREFIX}/lib" NO_DEFAULT_PATH REQUIRED)
  add_executable(flint_reactor_uring_test reactor_uring_test.c)
  target_link_libraries(flint_reactor_uring_test PRIVATE flint_ffi "${FLINT_URING}")
  add_test(NAME flint_reactor_uring_test COMMAND flint_reactor_uring_test)
  set_tests_properties(flint_reactor_uring_test PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 10)
  add_test(NAME flint_reactor_uring_denied COMMAND flint_reactor_uring_test --deny-setup)
  set_tests_properties(flint_reactor_uring_denied PROPERTIES TIMEOUT 10)
endif()

if(EXISTS "${CMAKE_INSTALL_PREFIX}/include/llhttp.h" AND EXISTS "${CMAKE_INSTALL_PREFIX}/include/zlib.h")
  find_library(FLINT_LLHTTP NAMES llhttp llhttp_static PATHS "${CMAKE_INSTALL_PREFIX}/lib" "${CMAKE_INSTALL_PREFIX}/lib64" NO_DEFAULT_PATH REQUIRED)
  find_library(FLINT_ZLIB NAMES z zlibstatic zlib PATHS "${CMAKE_INSTALL_PREFIX}/lib" "${CMAKE_INSTALL_PREFIX}/lib64" NO_DEFAULT_PATH REQUIRED)
  add_executable(flint_native_library_test native_library_test.c)
  target_compile_definitions(flint_native_library_test PRIVATE FLINT_SMOKE_MAIN=1)
  target_include_directories(flint_native_library_test PRIVATE "${CMAKE_INSTALL_PREFIX}/include")
  target_link_libraries(flint_native_library_test PRIVATE flint_ffi "${FLINT_LLHTTP}" "${FLINT_ZLIB}")
  add_test(NAME flint_native_library_test COMMAND flint_native_library_test)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND EXISTS "${CMAKE_INSTALL_PREFIX}/include/wasmtime.h" AND
    EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_wasi.h")
  target_compile_definitions(flint_ffi PRIVATE FLINT_HAS_WASMTIME=1)
  if(EXISTS "${CMAKE_INSTALL_PREFIX}/include/flint_wasmtime_extensions.h")
    target_compile_definitions(flint_ffi PRIVATE FLINT_HAS_WASMTIME_EXTENSIONS=1)
  endif()
  install(FILES flint_wasi.h DESTINATION include)
endif()

if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flint_mail.h" AND
    EXISTS "${CMAKE_INSTALL_PREFIX}/include/curl/curl.h")
  install(FILES flint_mail.h DESTINATION include)
  # Isolated pinned-ABI control. Static linking retains it only in the reference executable.
  add_library(flint_mail_reference STATIC "../../packages/mail/bench/baseline/native/direct.c")
  target_include_directories(flint_mail_reference PRIVATE "${CMAKE_INSTALL_PREFIX}/include")
  install(TARGETS flint_mail_reference ARCHIVE DESTINATION lib)
endif()
