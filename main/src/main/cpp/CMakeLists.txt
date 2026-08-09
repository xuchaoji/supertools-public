# CMakeLists.txt — supertools HDC native library
cmake_minimum_required(VERSION 3.5.0)
project(hdc_native)

set(CMAKE_CXX_STANDARD 17)

set(HDC_SRC_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/hdctools_src/source)
set(THIRD_PARTY_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

# Skip cJSON tests (needs OHOS test framework headers)
set(ENABLE_CJSON_TEST OFF CACHE BOOL "" FORCE)

# Prebuilt OpenSSL for OHOS
set(OPENSSL_ROOT ${THIRD_PARTY_ROOT}/openssl)
add_library(libssl STATIC IMPORTED)
set_target_properties(libssl PROPERTIES
    IMPORTED_LOCATION ${OPENSSL_ROOT}/ohos/${CMAKE_OHOS_ARCH_ABI}/libssl.a)
set_target_properties(libssl PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${OPENSSL_ROOT}/include)
add_library(libcrypto STATIC IMPORTED)
set_target_properties(libcrypto PROPERTIES
    IMPORTED_LOCATION ${OPENSSL_ROOT}/ohos/${CMAKE_OHOS_ARCH_ABI}/libcrypto.a)
set_target_properties(libcrypto PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES ${OPENSSL_ROOT}/include)

add_subdirectory(${THIRD_PARTY_ROOT}/bounds_checking_function)
add_subdirectory(${THIRD_PARTY_ROOT}/cJSON/source)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/hdctools
    ${OPENSSL_ROOT}/include
    ${HDC_SRC_ROOT}/src/common
    ${HDC_SRC_ROOT}/src/host
    ${THIRD_PARTY_ROOT}/bounds_checking_function/source/include
    ${THIRD_PARTY_ROOT}/cJSON/source
)

add_subdirectory(hdctools)
