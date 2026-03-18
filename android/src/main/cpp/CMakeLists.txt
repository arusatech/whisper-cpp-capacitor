cmake_minimum_required(VERSION 3.22)
project(whisper-jni)

set(CMAKE_CXX_STANDARD 17)
set(WHISPER_ROOT ${CMAKE_SOURCE_DIR}/../../../../ref-code/whisper.cpp)
set(CPP_DIR ${CMAKE_SOURCE_DIR}/../../../../cpp)

if(NOT EXISTS ${WHISPER_ROOT}/CMakeLists.txt)
  message(FATAL_ERROR "whisper.cpp not found at ${WHISPER_ROOT}")
endif()

set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
add_subdirectory(${WHISPER_ROOT} ${CMAKE_BINARY_DIR}/whisper)

add_library(whisper-jni SHARED
  whisper-jni.cpp
  ${CPP_DIR}/cap-whisper.cpp
)
target_include_directories(whisper-jni PRIVATE
  ${WHISPER_ROOT}/include
  ${CPP_DIR}
)
target_link_libraries(whisper-jni whisper android log)
