cmake_minimum_required(VERSION 3.20)
project(flint-port-spring LANGUAGES C)

include(FetchContent)
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()
FetchContent_Declare(tree_sitter
    URL https://codeload.github.com/tree-sitter/tree-sitter/tar.gz/refs/tags/v0.26.13
    URL_HASH SHA256=ece24c3c5e2a76384075e830c7139b59fce8fb01e4ef8436fab08bbe10444c89
    SOURCE_SUBDIR lib/src)
FetchContent_Declare(tree_sitter_java
    URL https://codeload.github.com/tree-sitter/tree-sitter-java/tar.gz/refs/tags/v0.23.5
    URL_HASH SHA256=cb199e0faae4b2c08425f88cbb51c1a9319612e7b96315a174a624db9bf3d9f0
    SOURCE_SUBDIR src)
FetchContent_MakeAvailable(tree_sitter tree_sitter_java)

# Compile the pinned grammar source without regenerating it or building the tree-sitter CLI.
add_library(port-spring-parser STATIC
    "${tree_sitter_SOURCE_DIR}/lib/src/lib.c"
    "${tree_sitter_java_SOURCE_DIR}/src/parser.c")
target_include_directories(port-spring-parser PUBLIC "${tree_sitter_SOURCE_DIR}/lib/include"
    PRIVATE "${tree_sitter_SOURCE_DIR}/lib/src" "${tree_sitter_java_SOURCE_DIR}/src")
target_compile_definitions(port-spring-parser PRIVATE
    _POSIX_C_SOURCE=200112L _DEFAULT_SOURCE _BSD_SOURCE _DARWIN_C_SOURCE)

add_executable(flint-port-spring translate.c)
target_link_libraries(flint-port-spring PRIVATE port-spring-parser)
set_target_properties(port-spring-parser flint-port-spring PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED YES C_EXTENSIONS NO)
if(MSVC)
    target_compile_options(flint-port-spring PRIVATE /W4)
else()
    target_compile_options(flint-port-spring PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()
