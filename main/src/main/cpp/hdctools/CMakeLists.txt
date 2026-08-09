# hdctools/CMakeLists.txt — compiles HDC from hdctools_src sources
# Adapter files (main.cpp, napi.cpp, server.cpp, auth.cpp, server_for_client.cpp) are local;
# base.cpp from hdctools_src is used directly (no local override needed).

set(HDC_SRC_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../hdctools_src/source)
set(HDC_THIRD  ${CMAKE_CURRENT_SOURCE_DIR}/../hdctools_src/third_party)
set(STUB_ROOT  ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libusb/include)

include_directories(
    ${HDC_SRC_ROOT}/src/common
    ${HDC_SRC_ROOT}/src/host
    ${HDC_THIRD}/lz4/lib
    ${HDC_THIRD}/libuv/source/include
)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17 -Wall")

add_subdirectory(${HDC_THIRD}/lz4 ${CMAKE_CURRENT_BINARY_DIR}/lz4)

if(OHOS)
    add_definitions(-DHILOG -DHOST_OHOS -DHDC_SUPPORT_UART -DHDC_SUPPORT_ENCRYPT_TCP)
    include_directories(BEFORE ${STUB_ROOT})
else()
    add_subdirectory(${HDC_THIRD}/libuv ${CMAKE_CURRENT_BINARY_DIR}/libuv)
    add_subdirectory(${HDC_THIRD}/libusb ${CMAKE_CURRENT_BINARY_DIR}/libusb)
endif()

add_definitions(-DUSE_CONFIG_UV_THREADS -DSIZE_THREAD_POOL=128 -DHDC_HOST -DHARMONY_PROJECT -DTEST_HASH -DHDC_MSG_HASH="TEST")

AUX_SOURCE_DIRECTORY(${HDC_SRC_ROOT}/src/host HOST_SRCS)
AUX_SOURCE_DIRECTORY(${HDC_SRC_ROOT}/src/common COMMON_SRCS)

# Remove files we override locally or don't need
list(REMOVE_ITEM HOST_SRCS "${HDC_SRC_ROOT}/src/host/server.cpp")
list(REMOVE_ITEM HOST_SRCS "${HDC_SRC_ROOT}/src/host/server_for_client.cpp")

list(REMOVE_ITEM COMMON_SRCS "${HDC_SRC_ROOT}/src/common/base.cpp")
list(REMOVE_ITEM COMMON_SRCS "${HDC_SRC_ROOT}/src/common/auth.cpp")
list(REMOVE_ITEM COMMON_SRCS "${HDC_SRC_ROOT}/src/common/hdc_huks.cpp")
list(REMOVE_ITEM COMMON_SRCS "${HDC_SRC_ROOT}/src/common/password.cpp")


# Override hdctools_src's base.h with our adapter version (adds HDC_HILOG macros)
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/base.h
    ${HDC_SRC_ROOT}/src/common/base.h
    COPYONLY
)

set(FixSource
    ${CMAKE_CURRENT_SOURCE_DIR}/base.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/main.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/server.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/server_for_client.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/auth.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/hdc.h
)

if(OHOS)
    list(APPEND FixSource ${CMAKE_CURRENT_SOURCE_DIR}/napi.cpp)
    list(APPEND FixSource ${CMAKE_CURRENT_SOURCE_DIR}/libusb_stubs.cpp)
endif()

add_library(hdc_z SHARED ${FixSource} ${COMMON_SRCS} ${HOST_SRCS})

target_link_libraries(hdc_z libcrypto libssl lz4 boundscheck uv)

if(OHOS)
    target_link_libraries(hdc_z hilog_ndk.z libace_napi.z.so)
endif()
