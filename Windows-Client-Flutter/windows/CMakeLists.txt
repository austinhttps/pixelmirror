cmake_minimum_required(VERSION 3.14)
project(windows_client_flutter LANGUAGES CXX)

set(BINARY_NAME "pixel_mirror_client")

cmake_policy(SET CMP0079 NEW)

# Flutter Windows configuration
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# Include runner subdirectory
add_subdirectory("runner")
