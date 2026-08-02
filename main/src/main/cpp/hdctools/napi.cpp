#include "napi/native_api.h"
#include "hdc.h"
#include <atomic>
#include <thread>
#include <cstdio>
#include <sstream>
#include <unistd.h>
#include <sys/stat.h>
#include <vector>
#include <string>

#ifdef HILOG
#include "hilog/log.h"
#define HDCZ_LOG(fmt, ...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "HDC_Z", fmt, ##__VA_ARGS__)
#define HDCZ_LOG_ERR(fmt, ...) OH_LOG_Print(LOG_APP, LOG_ERROR, 0x0000, "HDC_Z", fmt, ##__VA_ARGS__)
#else
#define HDCZ_LOG(fmt, ...)
#define HDCZ_LOG_ERR(fmt, ...)
#endif

static std::vector<std::string> parseCommandLine(const std::string& cmd) {
    std::vector<std::string> args;
    std::istringstream iss(cmd);
    std::string arg;
    bool inQuotes = false;
    char ch;
    while (iss >> std::noskipws >> ch) {
        if (ch == '"') { inQuotes = !inQuotes; }
        else if (ch == ' ' && !inQuotes) {
            if (!arg.empty()) { args.push_back(arg); arg.clear(); }
        } else { arg += ch; }
    }
    if (!arg.empty()) args.push_back(arg);
    return args;
}

static std::string napi_to_string(napi_env env, napi_value value) {
    size_t length = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &length);
    std::vector<char> buffer(length + 1);
    napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), nullptr);
    return std::string(buffer.data());
}

static const char** vector_to_const_argv(const std::vector<std::string>& vec) {
    const char** argv = new const char*[vec.size() + 1];
    for (size_t i = 0; i < vec.size(); ++i) argv[i] = vec[i].c_str();
    argv[vec.size()] = nullptr;
    return argv;
}

static napi_value HdcCmd(napi_env env, napi_callback_info info) {
    HDCZ_LOG("hdcCmd called");
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string cmdString = napi_to_string(env, args[0]);
    std::string tempDir = napi_to_string(env, args[1]);
    HDCZ_LOG("hdcCmd cmd=%{public}s tempDir=%{public}s", cmdString.c_str(), tempDir.c_str());
    std::vector<std::string> params = parseCommandLine(cmdString);

    napi_value rn;
    napi_create_string_latin1(env, "hdcCmd", NAPI_AUTO_LENGTH, &rn);
    napi_threadsafe_function tsfn;
    napi_create_threadsafe_function(env, args[2], nullptr, rn, 0, 1,
        nullptr, nullptr, nullptr,
        [](napi_env env, napi_value cb, void*, void* data) {
            auto* d = static_cast<int*>(data);
            napi_value p[1];
            napi_create_int32(env, *d, &p[0]);
            napi_call_function(env, nullptr, cb, 1, p, nullptr);
            delete d;
        }, &tsfn);

    std::thread t([](std::vector<std::string> p, std::string tdir, napi_threadsafe_function tsfn) {
        const char** argv = vector_to_const_argv(p);
        int ret = cmd(static_cast<int>(p.size()), argv, tdir.c_str());
        delete[] argv;
        HDCZ_LOG("hdcCmd worker: ret=%{public}d", ret);
        auto* cb = new int(ret);
        napi_call_threadsafe_function(tsfn, cb, napi_tsfn_blocking);
        napi_release_threadsafe_function(tsfn, napi_tsfn_release);
    }, params, tempDir, tsfn);
    t.detach();

    napi_value sum;
    napi_create_double(env, 0, &sum);
    return sum;
}

static std::atomic<bool> g_serverRunning{false};

static napi_value hdcServer(napi_env env, napi_callback_info info) {
    HDCZ_LOG("hdcServer called");
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string tempDir = napi_to_string(env, args[0]);
    HDCZ_LOG("hdcServer tempDir=%{public}s", tempDir.c_str());
    if (g_serverRunning.exchange(true)) {
        HDCZ_LOG("hdcServer already running");
        napi_value sum;
        napi_create_double(env, 0, &sum);
        return sum;
    }
    mkdir("/data/hdc/hdc_debug", 0755);
    mkdir(tempDir.c_str(), 0755);
    std::thread t([](std::string tdir) {
        HDCZ_LOG("hdcServer worker thread starting server()");
        server(tdir.c_str());
        HDCZ_LOG("hdcServer worker thread server() returned");
    }, tempDir);
    t.detach();
    HDCZ_LOG("hdcServer thread started, returning");
    napi_value sum;
    napi_create_double(env, 0, &sum);
    return sum;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "hdcServer", nullptr, hdcServer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "hdcCmd", nullptr, HdcCmd, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module HdcModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "hdc_z",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&HdcModule);
}
