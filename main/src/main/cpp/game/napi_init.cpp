/*
 * napi_init.cpp — libgame.so 的 NAPI 入口。
 *
 * ArkTS 侧通过 `import nativeGame from 'libgame.so'` 调用：
 *  - setFrame(Float32Array)    棋盘层矩形
 *  - setUiRects(Float32Array)  UI 层矩形
 *  - setUiTexts(string[], Float32Array) UI 层文本
 *  - pollTouch()               原生触摸轮询
 *  - attach(context)           onLoad 兜底注册
 *
 * XComponent 通过 libraryname: 'game' 加载同一个 so 时，ArkUI 会把
 * NativeXComponent 实例塞进 exports 的 __NATIVE_XCOMPONENT_OBJ__，
 * 两种加载顺序都兼容（谁先到谁注册）。
 */

#include <cstddef>
#include <cstring>
#include <string>
#include <vector>

#include <ace/xcomponent/native_interface_xcomponent.h>
#include <hilog/log.h>
#include <napi/native_api.h>

#include "game_renderer.h"

namespace {
constexpr uint32_t GAME_LOG_DOMAIN = 0x3200;
constexpr const char *GAME_LOG_TAG = "GameGL";

const float *ReadFloat32Array(napi_env env, napi_value value, size_t &length) {
    napi_typedarray_type type;
    length = 0;
    void *data = nullptr;
    napi_value arrayBuffer = nullptr;
    size_t byteOffset = 0;
    if (napi_get_typedarray_info(env, value, &type, &length, &data, &arrayBuffer, &byteOffset) != napi_ok) {
        return nullptr;
    }
    if (type != napi_float32_array || data == nullptr) {
        return nullptr;
    }
    return static_cast<const float *>(data);
}

napi_value SetFrame(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 1) {
        return nullptr;
    }
    size_t length = 0;
    const float *data = ReadFloat32Array(env, args[0], length);
    if (data == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "setFrame: expect Float32Array");
        return nullptr;
    }
    GameRenderer::GetInstance().SetFrame(data, length);
    return nullptr;
}

napi_value SetUiRects(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 1) {
        return nullptr;
    }
    size_t length = 0;
    const float *data = ReadFloat32Array(env, args[0], length);
    if (data == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "setUiRects: expect Float32Array");
        return nullptr;
    }
    GameRenderer::GetInstance().SetUiRects(data, length);
    return nullptr;
}

napi_value SetUiTexts(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 2) {
        return nullptr;
    }
    uint32_t textCount = 0;
    if (napi_get_array_length(env, args[0], &textCount) != napi_ok) {
        return nullptr;
    }
    std::vector<std::string> texts;
    texts.reserve(textCount);
    for (uint32_t i = 0; i < textCount; ++i) {
        napi_value item = nullptr;
        if (napi_get_element(env, args[0], i, &item) != napi_ok) {
            texts.emplace_back();
            continue;
        }
        size_t strLength = 0;
        napi_get_value_string_utf8(env, item, nullptr, 0, &strLength);
        std::vector<char> buffer(strLength + 1, '\0');
        napi_get_value_string_utf8(env, item, buffer.data(), buffer.size(), &strLength);
        texts.emplace_back(buffer.data(), strLength);
    }
    size_t paramCount = 0;
    const float *params = ReadFloat32Array(env, args[1], paramCount);
    if (params == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, GAME_LOG_DOMAIN, GAME_LOG_TAG, "setUiTexts: expect Float32Array params");
        return nullptr;
    }
    GameRenderer::GetInstance().SetUiTexts(texts, params, paramCount);
    return nullptr;
}

/** 取走原生触摸事件（SURFACE 类型下 ArkTS 的 .onTouch 收不到，必须走这里）。 */
napi_value PollTouch(napi_env env, napi_callback_info info) {
    float values[8] = {0.0f};
    GameRenderer::GetInstance().PollTouch(values);
    napi_value arrayBuffer = nullptr;
    void *data = nullptr;
    if (napi_create_arraybuffer(env, sizeof(values), &data, &arrayBuffer) != napi_ok || data == nullptr) {
        return nullptr;
    }
    std::memcpy(data, values, sizeof(values));
    napi_value typedArray = nullptr;
    if (napi_create_typedarray(env, napi_float32_array, 8, arrayBuffer, 0, &typedArray) != napi_ok) {
        return nullptr;
    }
    return typedArray;
}

/** onLoad(context) 兜底路径：把 XComponent 的 NativeXComponent 对象传给 native 注册回调。 */
napi_value Attach(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 1) {
        return nullptr;
    }
    OH_NativeXComponent *component = nullptr;
    if (napi_unwrap(env, args[0], reinterpret_cast<void **>(&component)) != napi_ok || component == nullptr) {
        // onLoad 的 context 在不同 API 版本上可能是模块 exports 而非 NativeXComponent；
        // 真正的注册在 Init 的 __NATIVE_XCOMPONENT_OBJ__ 分支完成，这里只做兜底。
        OH_LOG_Print(LOG_APP, LOG_DEBUG, GAME_LOG_DOMAIN, GAME_LOG_TAG,
                     "attach: context is not NativeXComponent (ignored)");
        return nullptr;
    }
    GameRenderer::GetInstance().AttachXComponent(component);
    return nullptr;
}

napi_value GetSurfaceSize(napi_env env, napi_callback_info info) {
    float values[2] = {0.0f, 0.0f};
    GameRenderer::GetInstance().GetSurfaceSize(values);
    napi_value arrayBuffer = nullptr;
    void *data = nullptr;
    if (napi_create_arraybuffer(env, sizeof(values), &data, &arrayBuffer) != napi_ok || data == nullptr) {
        return nullptr;
    }
    std::memcpy(data, values, sizeof(values));
    napi_value typedArray = nullptr;
    if (napi_create_typedarray(env, napi_float32_array, 2, arrayBuffer, 0, &typedArray) != napi_ok) {
        return nullptr;
    }
    return typedArray;
}
napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"setFrame", nullptr, SetFrame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setUiRects", nullptr, SetUiRects, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setUiTexts", nullptr, SetUiTexts, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"attach", nullptr, Attach, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pollTouch", nullptr, PollTouch, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getSurfaceSize", nullptr, GetSurfaceSize, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

    // XComponent 绑定 so 时触发的 Init：exports 上会带 NativeXComponent 实例
    napi_value exportInstance = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) == napi_ok) {
        OH_NativeXComponent *component = nullptr;
        if (napi_unwrap(env, exportInstance, reinterpret_cast<void **>(&component)) == napi_ok &&
            component != nullptr) {
            GameRenderer::GetInstance().AttachXComponent(component);
        }
    }
    return exports;
}
} // namespace

extern "C" __attribute__((constructor)) void RegisterGameModule(void) {
    static napi_module module = {};
    module.nm_version = 1;
    module.nm_register_func = Init;
    module.nm_modname = "game";
    napi_module_register(&module);
}
