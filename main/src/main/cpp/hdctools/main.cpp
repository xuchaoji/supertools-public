#include "hdc.h"
#include "base.h"
#include <string>
#include <cstdlib>
#include <sys/stat.h>
#include <cstdio>
#include <unistd.h>
#include <fcntl.h>

#ifdef HILOG
#include "hilog/log.h"
#define HDCZ_LOG(fmt, ...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0000, "HDC_Z", fmt, ##__VA_ARGS__)
#define HDCZ_LOG_ERR(fmt, ...) OH_LOG_Print(LOG_APP, LOG_ERROR, 0x0000, "HDC_Z", fmt, ##__VA_ARGS__)
#else
#define HDCZ_LOG(fmt, ...)
#define HDCZ_LOG_ERR(fmt, ...)
#endif

using namespace std;

namespace Hdc {
int SplitOptionAndCommand(int argc, const char **argv, string &outOption, string &outCommand);
int RunServerMode(string &serverListenString);
int RunClientMode(string &commands, string &serverListenString, string &connectKey, bool isPullServer);
bool GetCommandlineOptions(int optArgc, const char *optArgv[]);
}

extern bool g_show;

static string pathOr(const char *value, const string &def)
{
    return (value != nullptr && *value != '\0') ? string(value) : def;
}

// hdc 协议的客户端路径没有退出码通道（RunClientMode 恒返回 0），
// 失败只体现为 "[Fail]..." 文本。为了不让 ArkTS 侧永远看到 exitCode=0，
// 这里把 hdc 自己的失败标记翻译成非零退出码。
// 注意：这是基于文本的保守判断，仅匹配行首的 "[Fail]"。
static bool outputHasFailureMarker(const string &path)
{
    FILE *fp = fopen(path.c_str(), "r");
    if (fp == nullptr) {
        return false;
    }
    bool failed = false;
    char line[512];
    while (fgets(line, sizeof(line), fp) != nullptr) {
        if (strncmp(line, "[Fail]", 6) == 0) {
            failed = true;
            break;
        }
    }
    fclose(fp);
    return failed;
}

int cmd(int argc, const char *argv[], const char *tempPath,
    const char *outPathArg, const char *errPathArg)
{
    HDCZ_LOG("cmd() start, argc=%{public}d", argc);
    mkdir(tempPath, 0755);
    uv_os_setenv("USERPROFILE", tempPath);
    Hdc::Base::SetTempDir(tempPath);
    Hdc::Base::SetLogLevel(Hdc::LOG_OFF);

    // Output files are per-command (see napi.cpp) so that a cancelled/timed-out
    // command never clobbers the next command's output.
    string outPath = pathOr(outPathArg, string(tempPath) + "hdc.out");
    string errPath = pathOr(errPathArg, string(tempPath) + "hdc.err");
    int outFd = open(outPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0666);
    int savedStdout = -1;
    if (outFd >= 0) {
        HDCZ_LOG("cmd() redirecting stdout to %{public}s fd=%{public}d", outPath.c_str(), outFd);
        savedStdout = dup(STDOUT_FILENO);
        dup2(outFd, STDOUT_FILENO);
    }
    int errFd = open(errPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0666);
    int savedStderr = -1;
    if (errFd >= 0) {
        HDCZ_LOG("cmd() redirecting stderr to %{public}s fd=%{public}d", errPath.c_str(), errFd);
        savedStderr = dup(STDERR_FILENO);
        dup2(errFd, STDERR_FILENO);
    }

    string options, commands;
    Hdc::SplitOptionAndCommand(argc, argv, options, commands);
    HDCZ_LOG("cmd() commands=%{public}s", commands.c_str());
    uv_setup_args(argc, const_cast<char**>(argv));
    int optArgc = 0;
    char** optArgv = Hdc::Base::SplitCommandToArgs(options.c_str(), &optArgc);
    Hdc::GetCommandlineOptions(optArgc, const_cast<const char**>(optArgv));
    delete[] reinterpret_cast<char*>(optArgv);
    string addr = "127.0.0.1:18710";
    string key = "";
    bool pull = false;
    g_show = true;
    HDCZ_LOG("cmd() RunClientMode(addr=%{public}s)", addr.c_str());
    // 真实退出码必须回传，否则 ArkTS 侧永远看到 0，无法区分成功与失败。
    // 注意：hdc 协议层目前只区分 0 / -1（无 shell 退出码通道），
    // 因此这里能区分的是“客户端执行成功”与“连接或命令失败”。
    int ret = Hdc::RunClientMode(commands, addr, key, pull);
    HDCZ_LOG("cmd() done ret=%{public}d", ret);

    if (outFd >= 0) {
        fflush(stdout);
        // 不用 fsync：后台子进程（如 hilog）可能仍持有 fd 持续写入，
        // fsync 会等待文件全部落盘导致 cmd() 卡死；ArkTS 侧只读 page cache 即可。
        if (savedStdout >= 0) {
            dup2(savedStdout, STDOUT_FILENO);
            close(savedStdout);
        }
        close(outFd);
    }
    if (errFd >= 0) {
        fflush(stderr);
        if (savedStderr >= 0) {
            dup2(savedStderr, STDERR_FILENO);
            close(savedStderr);
        }
        close(errFd);
    }
    Hdc::Base::RemoveLogCache();
    if (ret == 0 && (outputHasFailureMarker(outPath) || outputHasFailureMarker(errPath))) {
        ret = 1;
    }
    return ret;
}
int server(const char *tempPath)
{
    HDCZ_LOG("server() start");
    mkdir("/data/hdc/hdc_debug", 0755);
    mkdir(tempPath, 0755);
    uv_os_setenv("USERPROFILE", tempPath);
    Hdc::Base::SetTempDir(tempPath);
    Hdc::Base::SetLogLevel(Hdc::LOG_OFF);
    string listenStr = "::ffff:127.0.0.1:18710";
    HDCZ_LOG("server() calling RunServerMode(%{public}s)", listenStr.c_str());
    Hdc::RunServerMode(listenStr);
    return 0;
}


