# cap-whisper is the Capacitor wrapper around whisper.cpp.
# It is built as part of the iOS and Android native targets, which add
# whisper.cpp (and ggml) via add_subdirectory and link against it.
# This file documents the wrapper; the actual build is in ios/CMakeLists.txt
# and android/src/main/cpp/CMakeLists.txt.
#
# Required: whisper.cpp with include/whisper.h and built target "whisper".
# Set WHISPER_ROOT to cpp/whisper.cpp (git submodule) when building from plugin root.

cmake_minimum_required(VERSION 3.16)
# This is not a standalone project; included from ios/ or android/
message(STATUS "cap-whisper: wrapper sources in ${CMAKE_CURRENT_SOURCE_DIR}")
