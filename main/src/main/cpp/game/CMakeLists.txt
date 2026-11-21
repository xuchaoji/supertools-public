# game/CMakeLists.txt — 原生 GL 渲染层（XComponent + EGL + GLES2）
#
# 产物：libgame.so
# 职责：只负责把 ArkTS 送来的帧数据（归一化矩形列表）画到 XComponent 的 Surface 上；
#       三消规则、动画节奏、广告调度全部留在 ArkTS 侧，避免把业务逻辑塞进 native。

cmake_minimum_required(VERSION 3.5.0)

set(GAME_ROOT ${CMAKE_CURRENT_SOURCE_DIR})

add_library(game SHARED
    game_renderer.cpp
    napi_init.cpp
)

target_include_directories(game PRIVATE ${GAME_ROOT})

find_library(EGL-lib EGL)
find_library(GLES-lib GLESv3)
find_library(hilog-lib hilog_ndk.z)
find_library(ace-lib ace_ndk.z)
find_library(napi-lib ace_napi.z)
find_library(drawing-lib native_drawing)

target_link_libraries(game PUBLIC
    ${EGL-lib}
    ${GLES-lib}
    ${hilog-lib}
    ${ace-lib}
    ${napi-lib}
    ${drawing-lib}
    libnative_window.so
)
