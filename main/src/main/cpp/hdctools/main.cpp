#include "hdc.h"
#include "base.h"
#include <string>
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

int cmd(int argc, const char *argv[], const char *tempPath)
{
    HDCZ_LOG("cmd() start, argc=%{public}d", argc);
    mkdir(tempPath, 0755);
    uv_os_setenv("USERPROFILE", tempPath);
    Hdc::Base::SetTempDir(tempPath);
    Hdc::Base::SetLogLevel(Hdc::LOG_OFF);

    string outPath = string(tempPath) + "hdc.out";
    int outFd = open(outPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0666);
    int savedStdout = -1;
    if (outFd >= 0) {
        HDCZ_LOG("cmd() redirecting stdout to %{public}s fd=%{public}d", outPath.c_str(), outFd);
        savedStdout = dup(STDOUT_FILENO);
        dup2(outFd, STDOUT_FILENO);
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
    Hdc::RunClientMode(commands, addr, key, pull);
    HDCZ_LOG("cmd() done");

    if (outFd >= 0) {
        fflush(stdout);
        fsync(outFd);
        if (savedStdout >= 0) {
            dup2(savedStdout, STDOUT_FILENO);
            close(savedStdout);
        }
        close(outFd);
    }
    Hdc::Base::RemoveLogCache();
    return 0;
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


