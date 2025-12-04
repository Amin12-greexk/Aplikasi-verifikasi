cmake_minimum_required(VERSION 3.14)
project(verifikasi_service_wrapper)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add the executable
add_executable(verifikasi_service_wrapper windows_service.cpp)

# Link necessary Windows libraries
target_link_libraries(verifikasi_service_wrapper PRIVATE
    advapi32
    winsvc
)

# Windows-specific settings
target_compile_options(verifikasi_service_wrapper PRIVATE
    /W4           # Warning level 4
    /EHsc         # Exception handling
    /DUNICODE     # Unicode support
    /D_UNICODE
)

# Set output directory
set_target_properties(verifikasi_service_wrapper PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
