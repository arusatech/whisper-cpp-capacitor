cmake_minimum_required(VERSION 3.16)
project(whisper-cap-wasm LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Paths passed from build-native-web.sh
if(NOT DEFINED WHISPER_ROOT)
  set(WHISPER_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../cpp/whisper.cpp)
endif()
if(NOT DEFINED CPP_DIR)
  set(CPP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../cpp)
endif()

if(NOT EXISTS ${WHISPER_ROOT}/CMakeLists.txt)
  message(FATAL_ERROR "whisper.cpp not found at ${WHISPER_ROOT}. Run: git submodule update --init")
endif()

option(WASM_SINGLE_FILE "Embed WASM binary in JS" ON)

# Configure whisper.cpp for WASM
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_STANDALONE OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_CUDA OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
set(GGML_OPENCL OFF CACHE BOOL "" FORCE)

add_subdirectory(${WHISPER_ROOT} ${CMAKE_BINARY_DIR}/whisper)

# Build the WASM binding
add_executable(whisper-cap
  ${CPP_DIR}/cap-whisper.cpp
  ${CPP_DIR}/cap-whisper-wasm.cpp
)

target_include_directories(whisper-cap PRIVATE
  ${WHISPER_ROOT}/include
  ${CPP_DIR}
)

target_link_libraries(whisper-cap PRIVATE whisper)

# Emscripten: pthreads compile flag + embind link flag
target_compile_options(whisper-cap PRIVATE "-pthread")
target_link_options(whisper-cap PRIVATE "-lembind")

# Emscripten link flags
set(WASM_LINK_FLAGS "\
  -s USE_PTHREADS=1 \
  -s PTHREAD_POOL_SIZE_STRICT=0 \
  -s INITIAL_MEMORY=256MB \
  -s MAXIMUM_MEMORY=2000MB \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s FORCE_FILESYSTEM=1 \
  -s MODULARIZE=1 \
  -s EXPORT_NAME='WhisperModule' \
  -s EXPORTED_RUNTIME_METHODS=\"['FS','HEAPU8','HEAPF32','ccall','cwrap']\" \
  -s ENVIRONMENT='web,worker' \
  -s STACK_SIZE=5MB \
")

if(WASM_SINGLE_FILE)
  set(WASM_LINK_FLAGS "${WASM_LINK_FLAGS} -s SINGLE_FILE=1")
  message(STATUS "WASM: embedding binary in JS (single-file mode)")
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Release")
  set(WASM_LINK_FLAGS "${WASM_LINK_FLAGS} -O3 --closure 0")
else()
  set(WASM_LINK_FLAGS "${WASM_LINK_FLAGS} -O0 -g -s ASSERTIONS=2")
endif()

set_target_properties(whisper-cap PROPERTIES
  SUFFIX ".js"
  LINK_FLAGS "${WASM_LINK_FLAGS}"
)
