import { HMRouter, HMRouterMgr } from "@hadss/hmrouter";
import hilog from "@ohos.hilog";
import { AppUtil, PreferencesUtil } from "@pura/harmony-utils";
import { HdcService, HdcShellResult } from "../utils/HdcService";
import { SpKeys } from "../constant/SpKeys";
import { connection } from "@kit.NetworkKit";
import { KeyCode } from "@kit.InputKit";
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction, mediaquery } from '@kit.ArkUI';
import fs from '@ohos.file.fs';
import { picker } from '@kit.CoreFileKit';
import { WallpaperHost } from '../components/WallpaperHost';
import { ImmersiveStyles } from '../utils/ImmersiveStyles';

type EntryType = "input" | "output" | "error" | "system" | "meta";

interface TerminalEntry {
  type: EntryType;
  text: string;
  timestamp: number;
  uid: number;
}

interface QuickCmd {
  label: string;
  cmd: string;
}

interface QuickGroup {
  title: string;
  commands: QuickCmd[];
}

interface LogFileInfo {
  name: string;
  sizeKB: number;
  mtime: number;
}

const MAX_ENTRIES: number = 800;
const DEFAULT_TIMEOUT_MS: number = 30000;
const HISTORY_KEY: string = 'hdc_history';
const MAX_HISTORY: number = 20;
/** 抓取日志的保存目录（应用沙箱内） */
const LOG_DIR: string = '/data/storage/el2/base/hdcz/logs/';

@HMRouter({ pageUrl: "hdcDebugPage" })
@Entry
@ComponentV2
export struct HdcDebugPage {
  @Local entries: TerminalEntry[] = [];
  @Local inputText: string = "";
  @Local isRunning: boolean = false;
  @Local serverStatus: string = "starting"; // starting | ready | failed
  @Local connectIp: string = "";
  @Local connectPort: string = "";
  @Local isConnected: boolean = false;
  @Local quickCategory: string = "常用";
  @Local cmdHistory: string[] = [];
  @Local historyIndex: number = -1;
  @Local followOutput: boolean = true;
  @Local debugLogOn: boolean = false;
  @Local capturedLogs: string[] = [];
  @Local capturing: boolean = false;
  @Local logFiles: LogFileInfo[] = [];
  @Local showLogManager: boolean = false;
  private lastCaptureEnd: number = 0;
  private scroller: Scroller = new Scroller();
  private hdcService: HdcService = new HdcService();
  private entrySeq: number = 0;
  /** 沉浸光感：跟随系统深/浅色模式，驱动文字阴影保证任意壁纸背景可读 */
  @Local isDark: boolean = false;
  private themeMq: mediaquery.MediaQueryListener | null = null;

  private readonly quickGroups: QuickGroup[] = [
    {
      title: '常用',
      commands: [
        { label: 'targets', cmd: 'list targets -v' },
        { label: 'version', cmd: 'version' },
        { label: 'checkserver', cmd: 'checkserver' },
        { label: 'help', cmd: 'help' },
      ]
    },
    {
      title: '系统',
      commands: [
        { label: 'uname', cmd: 'shell uname -a' },
        { label: 'getprop', cmd: 'shell getprop' },
        { label: 'uptime', cmd: 'shell uptime' },
        { label: 'meminfo', cmd: 'shell cat /proc/meminfo' },
        { label: 'cpuinfo', cmd: 'shell cat /proc/cpuinfo' },
      ]
    },
    {
      title: '进程',
      commands: [
        { label: 'ps', cmd: 'shell ps -ef' },
        { label: 'ps-A', cmd: 'shell ps -A' },
        { label: 'top', cmd: 'shell top -n 1' },
        { label: '线程', cmd: 'shell ps -T -p 1' },
      ]
    },
    {
      title: '网络',
      commands: [
        { label: 'netstat', cmd: 'shell netstat -tln' },
        { label: 'ifconfig', cmd: 'shell ifconfig' },
        { label: 'ip addr', cmd: 'shell ip addr' },
        { label: 'ping 本机', cmd: 'shell ping -c 3 127.0.0.1' },
      ]
    },
    {
      title: '存储',
      commands: [
        { label: 'df', cmd: 'shell df -h' },
        { label: '根目录', cmd: 'shell ls -l /' },
        { label: 'sdcard', cmd: 'shell ls -l /sdcard' },
        { label: 'data', cmd: 'shell ls -l /data' },
      ]
    },
    {
      title: '日志',
      commands: [
        { label: 'hilog', cmd: 'shell hilog -n 50' },
        { label: 'crash', cmd: 'shell hilog -b crash -n 20' },
        { label: 'main 30', cmd: 'shell hilog -b main -n 30' },
        { label: 'dmesg', cmd: 'shell dmesg | tail -20' },
      ]
    }
  ];

  aboutToAppear(): void {
    hilog.info(0x0000, "HDC_Z", "HdcDebugPage aboutToAppear");
    this.initThemeListener();
    this.addSystem("=== SuperTools HDC ===");
    this.addSystem("Starting HDC server...");
    this.hdcService.startServer();
    this.loadHistory();
    PreferencesUtil.get("hdc_port", "").then((v) => {
      if (v) { this.connectPort = v as string; }
    });
    this.getLocalIp();

    // Real readiness probe replaces the old hard-coded 1.5s delay.
    this.hdcService.waitForServerReady(6000, 250).then((ready: boolean) => {
      if (!ready) {
        this.serverStatus = "failed";
        this.addError("HDC server failed to start");
        return;
      }
      this.serverStatus = "ready";
      this.addSystem("Server ready");
      // 自动探测命令不写入历史，避免顶掉用户自己的命令
      this.executeQuick("list targets -v", false);
    });
  }

  aboutToDisappear(): void {
    this.themeMq?.off('change');
    this.themeMq = null;
    this.hdcService.destroy();
  }

  /** 订阅系统深/浅色模式变化，驱动文字阴影参数切换 */
  private initThemeListener(): void {
    try {
      this.themeMq = this.getUIContext().getMediaQuery().matchMediaSync('(display-mode: dark)');
      this.isDark = this.themeMq.matches;
      this.themeMq.on('change', (event: mediaquery.MediaQueryResult) => {
        this.isDark = event.matches;
      });
    } catch (e) {
      this.isDark = false;
    }
  }

  private getLocalIp(): void {
    try {
      let nh = connection.getDefaultNetSync();
      if (!nh) { return; }
      let props = connection.getConnectionPropertiesSync(nh);
      let addrs = props.linkAddresses || [];
      for (let la of addrs) {
        let na = la.address;
        let ip: string = na.address as string || "";
        if (!ip) { continue; }
        if (ip.startsWith("192.168.") || (!ip.startsWith("127.") && ip.includes("10.")) || ip.includes("172.")) {
          this.connectIp = ip;
          return;
        }
      }
    } catch (e) {
      hilog.info(0x0000, "HDC_Z", "getLocalIp: %{public}s", JSON.stringify(e));
    }
  }

  // ------------------------------------------------------------------
  // Command execution
  // ------------------------------------------------------------------

  private async connectDevice(): Promise<void> {
    let ip = this.connectIp.trim();
    let port = this.connectPort.trim() || "8710";
    if (!ip) return;
    PreferencesUtil.put("hdc_port", port);
    let cmd = "tconn " + ip + ":" + port;
    this.addSystem("Connecting " + ip + ":" + port + "...");
    this.isRunning = true;
    let r = await this.hdcService.execCommand(cmd, DEFAULT_TIMEOUT_MS);
    this.printResult(r);
    this.isRunning = false;

    if (r.stdout.indexOf("Connect OK") >= 0) {
      this.isConnected = true;
      this.addSystem("Connected. Listing targets...");
      // 连接成功后查询/刷新日志级别开关
      this.refreshDebugLogState();
      setTimeout(() => { this.executeQuick("list targets -v"); }, 500);
    }
  }

  private async executeCommand(): Promise<void> {
    const cmd = this.inputText.trim();
    if (!cmd) return;
    hilog.info(0x0000, "HDC_Z", "executeCommand: %{public}s", cmd);
    this.pushHistory(cmd);
    this.addInput(cmd);
    this.inputText = "";
    this.historyIndex = -1;
    this.isRunning = true;
    const r = await this.hdcService.execCommand(cmd, DEFAULT_TIMEOUT_MS);
    this.printResult(r);
    this.isRunning = false;
  }

  private async executeQuick(cmd: string, recordHistory: boolean = true): Promise<void> {
    if (this.isRunning) return;
    hilog.info(0x0000, "HDC_Z", "executeQuick: %{public}s", cmd);
    if (recordHistory) { this.pushHistory(cmd); }
    this.addInput(cmd);
    this.isRunning = true;
    const r = await this.hdcService.execCommand(cmd, DEFAULT_TIMEOUT_MS);
    this.printResult(r);
    this.isRunning = false;
  }

  private cancelCommand(): void {
    this.hdcService.cancel();
  }

  private printResult(r: HdcShellResult): void {
    if (r.error) {
      this.addError(r.error);
    } else if (r.timedOut) {
      this.addError(r.stderr || "command timed out");
    } else if (r.cancelled) {
      this.addSystem("(cancelled)");
    } else {
      const out = (r.stdout || "").trim();
      const err = (r.stderr || "").trim();
      if (out) { out.split("\n").filter(l => l).forEach(l => this.addOutput(l)); }
      if (err) { err.split("\n").filter(l => l).forEach(l => this.addError(l)); }
      if (!out && !err) { this.addSystem("(no output)"); }
    }
    const suffix: string = (r.exitCode !== 0 && !r.timedOut && !r.cancelled) ? "  exit: " + r.exitCode : "";
    this.addMeta("⏱ " + this.formatDuration(r.durationMs) + suffix);
  }

  private formatDuration(ms: number): string {
    if (ms < 0) { return "-"; }
    if (ms < 1000) { return ms + "ms"; }
    return (ms / 1000).toFixed(2) + "s";
  }

  // ------------------------------------------------------------------
  // Command history
  // ------------------------------------------------------------------

  private loadHistory(): void {
    try {
      const raw = PreferencesUtil.getSync(HISTORY_KEY, "") as string;
      if (raw) {
        const arr = JSON.parse(raw) as string[];
        if (Array.isArray(arr)) {
          const unique: string[] = [];
          for (const s of arr) {
            if (typeof s === 'string' && s.length > 0 && unique.indexOf(s) < 0) {
              unique.push(s);
            }
          }
          this.cmdHistory = unique;
        }
      }
    } catch (e) {
      hilog.info(0x0000, "HDC_Z", "loadHistory failed");
    }
  }

  private pushHistory(cmd: string): void {
    // 不可变重建数组（新命令置顶 + 去重 + 截断），确保 @Local 响应式更新
    const next: string[] = [cmd, ...this.cmdHistory.filter((c: string) => c !== cmd)].slice(0, MAX_HISTORY);
    this.cmdHistory = next;
    this.historyIndex = -1;
    try { PreferencesUtil.putSync(HISTORY_KEY, JSON.stringify(next)); } catch (e) { /* ignore */ }
  }

  private historyPrev(): void {
    if (this.cmdHistory.length === 0) { return; }
    // ↑：从最新一条开始往前翻（cmdHistory[0] 为最近执行）
    this.historyIndex = this.historyIndex < 0 ? 0 : Math.min(this.cmdHistory.length - 1, this.historyIndex + 1);
    this.inputText = this.cmdHistory[this.historyIndex];
  }

  private historyNext(): void {
    if (this.historyIndex < 0) { return; }
    // ↓：往回翻到更新的命令，到最新之后再按回到空白
    this.historyIndex--;
    if (this.historyIndex < 0) {
      this.historyIndex = -1;
      this.inputText = "";
    } else {
      this.inputText = this.cmdHistory[this.historyIndex];
    }
  }

  // ------------------------------------------------------------------
  // Terminal entries
  // ------------------------------------------------------------------

  private addEntry(type: EntryType, text: string): void {
    let e: TerminalEntry = { type: type, text: text, timestamp: Date.now(), uid: this.entrySeq++ };
    this.entries.push(e);
    if (this.entries.length > MAX_ENTRIES) { this.entries.shift(); }
    if (this.followOutput) {
      setTimeout(() => { this.scroller.scrollEdge(Edge.Bottom); }, 30);
    }
  }
  private addSystem(t: string): void { this.addEntry("system", t); }
  private addMeta(t: string): void { this.addEntry("meta", t); }
  private addInput(t: string): void { this.addEntry("input", "$ " + t); }
  private addOutput(t: string): void { this.addEntry("output", t); }
  private addError(t: string): void { this.addEntry("error", t); }

  private clearTerminal(): void {
    this.entries = [];
    this.addSystem("=== cleared ===");
  }

  // ------------------------------------------------------------------
  // 日志工具：debug 开关 / 抓取 / 导出
  // ------------------------------------------------------------------

  private async toggleDebugLog(isOn: boolean): Promise<void> {
    this.debugLogOn = isOn;
    PreferencesUtil.putSync(SpKeys.HDC_DEBUG_LOG, isOn);
    // 通过 hilog -b 设置设备全局日志级别（D=含 Debug，I=不含 Debug）
    const cmd: string = isOn ? 'shell hilog -b D' : 'shell hilog -b I';
    this.addSystem((isOn ? '启用' : '关闭') + ' Debug 日志（设置全局日志级别 ' + (isOn ? 'D' : 'I') + '）');
    this.isRunning = true;
    const r = await this.hdcService.execCommand(cmd, DEFAULT_TIMEOUT_MS);
    this.isRunning = false;
    this.printResult(r);
  }

  /**
   * 连接后刷新 Debug 开关：
   * 1) 恢复本地持久化的开关状态；
   * 2) 探测设备日志中是否存在 D 级——探测不到则确认当前全局级别高于 D（debug 关闭），强制刷新开关。
   */
  private async refreshDebugLogState(): Promise<void> {
    this.debugLogOn = PreferencesUtil.getBooleanSync(SpKeys.HDC_DEBUG_LOG, false);
    if (this.capturing) { return; }
    const r = await this.hdcService.execCommand('shell hilog -x -L D | head -n 1', 8000);
    if (!r.timedOut && !r.cancelled && (r.stdout || '').trim().length === 0) {
      // 探测不到 D 级日志 → 当前全局级别不含 Debug
      if (this.debugLogOn) {
        this.debugLogOn = false;
        PreferencesUtil.putSync(SpKeys.HDC_DEBUG_LOG, false);
        this.addSystem('检测到设备日志级别不含 Debug，已刷新开关为关闭');
      }
    }
  }

  private async captureLog(): Promise<void> {
    if (this.capturing) { return; }
    const now: number = Date.now();
    // 防双击/状态切换竞态：停止后 1.5s 内不允许重新开始抓取
    if (now - this.lastCaptureEnd < 1500) { return; }
    // 持续抓取：hilog 不带 -x 是阻塞模式（持续打印新日志，不自动退出），
    // 直到用户点击「停止」才保存已抓取部分；10 分钟超时仅为最后兜底
    const cmd: string = this.debugLogOn
      ? 'shell hilog'
      : 'shell hilog -L I,W,E,F';
    this.addSystem('抓取中... 点击「停止」保存已抓取的日志');
    this.capturing = true;
    this.isRunning = true;
    // 长超时（10 分钟）防挂起，主要靠手动停止
    const r = await this.hdcService.execCommand(cmd, 600000);
    this.isRunning = false;
    this.capturing = false;
    this.lastCaptureEnd = Date.now();
    if (r.cancelled) {
      // 用户主动停止：r.stdout 为已抓取的部分内容
      this.saveLogContent(r.stdout, '已停止，保存抓取到的部分日志');
    } else if (r.timedOut) {
      this.addError('抓取超时（10 分钟）');
    } else {
      this.saveLogContent(r.stdout, '');
    }
  }

  private stopCapture(): void {
    this.hdcService.cancel();
  }

  private async saveLogContent(content: string, note: string): Promise<void> {
    const text: string = content || '';
    if (text.length === 0) {
      this.addSystem('抓取内容为空');
      return;
    }
    // 只检查开头 256 字符判断是否未连接（避免大字符串 indexOf 卡顿）
    const head: string = text.substring(0, 256);
    if (head.indexOf('need connect-key') >= 0 || head.indexOf('ExecuteCommand') >= 0) {
      this.addError('未连接设备，请先点击「Conn」连接后再抓取');
      return;
    }
    const sizeKB: number = Math.ceil(text.length / 1024);
    const fileName: string = 'hilog_' + this.formatLogTs() + '.log';
    try {
      try { fs.mkdirSync(LOG_DIR, true); } catch (e) { /* 目录已存在 */ }
      const file = fs.openSync(LOG_DIR + fileName, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        // 异步写，避免大 IO 阻塞 UI 线程
        await fs.write(file.fd, text);
      } finally {
        fs.closeSync(file);
      }
      this.capturedLogs.unshift(fileName);
      this.addSystem((note ? note + '，' : '') + '已保存 ' + sizeKB + ' KB → ' + LOG_DIR + fileName);
      hilog.info(0x0000, "HDC_Z", "captureLog: saved %{public}d KB to %{public}s", sizeKB, fileName);
    } catch (e) {
      hilog.info(0x0000, "HDC_Z", "captureLog: save failed %{public}s", JSON.stringify(e));
      this.addError('保存日志失败: ' + JSON.stringify(e));
    }
  }

  private formatLogTs(): string {
    const d = new Date();
    const p = (n: number): string => (n < 10 ? '0' : '') + n;
    return d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '_' +
      p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
  }

  /** 扫描日志目录，返回全部已抓取日志（最新在前） */
  private listLogFiles(): LogFileInfo[] {
    const files: LogFileInfo[] = [];
    try {
      const names: string[] = fs.listFileSync(LOG_DIR);
      for (const n of names) {
        if (!n.endsWith('.log')) { continue; }
        try {
          const stat = fs.statSync(LOG_DIR + n);
          const info: LogFileInfo = {
            name: n,
            sizeKB: Math.ceil(stat.size / 1024),
            mtime: stat.mtime
          };
          files.push(info);
        } catch (e) { /* 忽略单个文件异常 */ }
      }
    } catch (e) { /* 目录不存在 */ }
    files.sort((a: LogFileInfo, b: LogFileInfo): number => b.mtime - a.mtime);
    return files;
  }

  /** 打开日志管理面板 */
  private openLogManager(): void {
    this.logFiles = this.listLogFiles();
    this.showLogManager = true;
  }

  /** 导出指定日志文件（picker 选择位置） */
  private async exportFiles(names: string[]): Promise<void> {
    if (!names || names.length === 0) {
      this.addSystem('没有可导出的日志文件');
      return;
    }
    const srcPaths: string[] = names.map((n: string): string => LOG_DIR + n);
    try {
      const documentPicker = new picker.DocumentViewPicker(this.getUIContext().getHostContext() as Context);
      const opt = new picker.DocumentSaveOptions();
      opt.newFileNames = names;
      const uris: string[] = await documentPicker.save(opt);
      if (uris && uris.length > 0) {
        for (let i = 0; i < uris.length && i < srcPaths.length; i++) {
          const destFile = fs.openSync(uris[i], fs.OpenMode.READ_WRITE);
          try {
            fs.copyFileSync(srcPaths[i], destFile.fd);
          } finally {
            fs.closeSync(destFile);
          }
        }
        this.addSystem('已导出 ' + uris.length + ' 个日志文件');
        this.logFiles = this.listLogFiles();
      }
    } catch (e) {
      this.addSystem('导出已取消');
    }
  }

  /** 导出全部已抓取日志 */
  private async exportAllLogs(): Promise<void> {
    const names: string[] = this.logFiles.map((f: LogFileInfo) => f.name);
    await this.exportFiles(names);
  }

  /** 删除单个日志文件 */
  private deleteLogFile(name: string): void {
    try {
      fs.unlinkSync(LOG_DIR + name);
      this.addSystem('已删除: ' + name);
    } catch (e) {
      this.addError('删除失败: ' + JSON.stringify(e));
    }
    this.logFiles = this.listLogFiles();
  }

  /** 清空全部日志文件 */
  private clearAllLogs(): void {
    let removed: number = 0;
    for (const f of this.logFiles) {
      try {
        fs.unlinkSync(LOG_DIR + f.name);
        removed++;
      } catch (e) { /* 忽略 */ }
    }
    this.logFiles = this.listLogFiles();
    this.addSystem('已清空 ' + removed + ' 个日志文件');
  }

  private copyAll(): void {
    const text = this.entries.map(e => e.text).join("\n");
    if (!text) { return; }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: '已复制 ' + this.entries.length + ' 行', duration: 1500 });
    }).catch((e: Object) => {
      hilog.info(0x0000, "HDC_Z", "copyAll failed: %{public}s", JSON.stringify(e));
    });
  }

  private entryColor(type: EntryType): ResourceColor {
    if (type === "error") { return "#F44336"; }
    if (type === "system") { return "#FF9800"; }
    if (type === "input") { return "#4CAF50"; }
    if (type === "meta") { return "#888888"; }
    return "sys.color.font_primary";
  }

  // ------------------------------------------------------------------
  // UI builders
  // ------------------------------------------------------------------

  @Builder
  headerRow() {
    Row({ space: 10 }) {
      Image("app.media.back_arrow").width(24).height(24).fillColor("sys.color.font_primary")
        .onClick(() => { HMRouterMgr.pop(); })
      Text("HDC Debug").fontSize(20).fontWeight(FontWeight.Bold).fontColor("sys.color.font_emphasize")
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
      Blank()
      Text(this.serverStatus === "ready" ? "● Server" : this.serverStatus === "failed" ? "● Failed" : "● Starting")
        .fontSize(11).fontColor(
          this.serverStatus === "ready" ? "#28A745" : this.serverStatus === "failed" ? "#F44336" : "#FF9800"
        ).fontWeight(FontWeight.Medium)
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
      Text("Copy").fontSize(12).fontColor("sys.color.font_secondary")
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor("sys.color.comp_background_gray").borderRadius(6)
        .onClick(() => { this.copyAll(); })
      Text("Clear").fontSize(12).fontColor("sys.color.font_secondary")
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor("sys.color.comp_background_gray").borderRadius(6)
        .onClick(() => { this.clearTerminal(); })
    }
    .width("100%").padding({ left: 16, right: 16, top: 12, bottom: 4 })
  }

  @Builder
  statusLine() {
    Row({ space: 8 }) {
      Text(this.isConnected
        ? "已连接 " + this.connectIp + ":" + (this.connectPort.trim() || "8710")
        : "未连接远程设备 · 可执行 list targets / version 等主机命令")
        .fontSize(11).fontColor("sys.color.font_secondary").maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
      Blank()
      Text(this.isConnected ? "●" : "○").fontSize(12)
        .fontColor(this.isConnected ? "#28A745" : "sys.color.font_secondary")
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
    }.width("100%").padding({ left: 16, right: 16, top: 2, bottom: 4 })
  }

  @Builder
  terminalColumns() {
    Column() {
      Row({ space: 8 }) {
        Text("Terminal").fontSize(13).fontWeight(FontWeight.Bold).fontColor("sys.color.font_emphasize")
          .textShadow(ImmersiveStyles.textShadow(this.isDark))
        Text(this.entries.length + " 行").fontSize(10).fontColor("sys.color.font_secondary")
          .textShadow(ImmersiveStyles.textShadow(this.isDark))
        Blank()
        Text(this.followOutput ? "⤓ 跟随" : "⤒ 暂停")
          .fontSize(11).fontColor(this.followOutput ? "#007AFF" : "sys.color.font_secondary")
          .textShadow(ImmersiveStyles.textShadow(this.isDark))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor("sys.color.comp_background_gray").borderRadius(4)
          .onClick(() => { this.followOutput = !this.followOutput; })
      }
      .width("100%").padding({ left: 12, right: 12, top: 8, bottom: 4 })

      Divider().color("sys.color.comp_background_emphasize").strokeWidth(0.5)

      List({ scroller: this.scroller }) {
        ForEach(this.entries, (e: TerminalEntry) => {
          ListItem() {
            Text(e.text).fontSize(13).fontFamily("monospace").fontColor(this.entryColor(e.type))
              .textShadow(ImmersiveStyles.textShadow(this.isDark))
              .copyOption(CopyOptions.LocalDevice)
              .width("100%").padding({ top: 2, bottom: 2, left: 12, right: 12 })
          }
        }, (e: TerminalEntry): string => e.uid.toString())

        if (this.isRunning) {
          ListItem() {
            Row() {
              LoadingProgress().width(12).height(12).margin({ right: 6 })
              Text("running...").fontSize(12).fontColor("sys.color.font_secondary").fontFamily("monospace")
                .textShadow(ImmersiveStyles.textShadow(this.isDark))
            }.padding({ left: 12, right: 12, top: 4, bottom: 4 })
          }
        }
      }
      .scrollBar(BarState.Auto).layoutWeight(1).width("100%")
    }
  }

  @Builder
  connectBar() {
    Column() {
      Row({ space: 6 }) {
        TextInput({ placeholder: "IP address (本机调试填 127.0.0.1)", text: this.connectIp })
          .onChange((v: string) => { this.connectIp = v; })
          .fontSize(12).fontFamily("monospace").layoutWeight(3).height(36)
          .backgroundColor("sys.color.background_primary").borderRadius(6)
          .border({ width: 1, color: "sys.color.comp_background_emphasize" })
          .padding({ left: 8, right: 8 })

        TextInput({ placeholder: "Port", text: this.connectPort })
          .onChange((v: string) => { this.connectPort = v; })
          .fontSize(12).fontFamily("monospace").layoutWeight(1).height(36)
          .backgroundColor("sys.color.background_primary").borderRadius(6)
          .border({ width: 1, color: "sys.color.comp_background_emphasize" })
          .type(InputType.Number)
          .padding({ left: 6, right: 6 })

        Button(this.isConnected ? "Recon" : "Conn")
          .fontSize(12).fontColor(Color.White)
          .backgroundColor(!this.isRunning ? "#28A745" : "#CCCCCC")
          .borderRadius(6).height(36).padding({ left: 8, right: 8 })
          .enabled(!this.isRunning)
          .onClick(() => { this.connectDevice(); })
      }.width("100%").padding({ top: 6, bottom: 4 })
    }
  }

  private formatLogTime(sec: number): string {
    // stat.mtime 是秒级时间戳
    const d = new Date(sec * 1000);
    const p = (n: number): string => (n < 10 ? '0' : '') + n;
    return p(d.getMonth() + 1) + '-' + p(d.getDate()) + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
  }

  @Builder
  logManagerSheet() {
    Column() {
      Row({ space: 8 }) {
        Text("已抓取日志").fontSize(16).fontWeight(FontWeight.Bold)
          .textShadow(ImmersiveStyles.textShadow(this.isDark))
        Text(this.logFiles.length + ' 个').fontSize(11).fontColor("sys.color.font_secondary")
          .textShadow(ImmersiveStyles.textShadow(this.isDark))
        Blank()
        Text("关闭").fontSize(13).fontColor("#007AFF")
          .textShadow(ImmersiveStyles.textShadow(this.isDark))
          .onClick(() => { this.showLogManager = false; })
      }.width("100%").padding({ left: 16, right: 16, top: 14, bottom: 8 })

      Divider().color("sys.color.comp_background_emphasize").strokeWidth(0.5)

      if (this.logFiles.length === 0) {
        Column() {
          Text("暂无已抓取日志").fontSize(13).fontColor("sys.color.font_secondary")
            .textShadow(ImmersiveStyles.textShadow(this.isDark))
        }
        .layoutWeight(1).width("100%").justifyContent(FlexAlign.Center)
      } else {
        List({ space: 4 }) {
          ForEach(this.logFiles, (f: LogFileInfo) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(f.name).fontSize(12).fontFamily("monospace")
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))
                    .maxLines(1).ellipsisMode(EllipsisMode.END)
                  Text(f.sizeKB + ' KB · ' + this.formatLogTime(f.mtime))
                    .fontSize(10).fontColor("sys.color.font_secondary")
                    .textShadow(ImmersiveStyles.textShadow(this.isDark))
                }
                .layoutWeight(1).alignItems(HorizontalAlign.Start)

                Text("导出").fontSize(11).fontColor("#007AFF")
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
                  .padding({ top: 3, bottom: 3, left: 8, right: 8 })
                  .backgroundColor("sys.color.comp_background_gray").borderRadius(4)
                  .onClick(() => { this.exportFiles([f.name]); })

                Text("删除").fontSize(11).fontColor("#F44336")
                  .textShadow(ImmersiveStyles.textShadow(this.isDark))
                  .padding({ top: 3, bottom: 3, left: 8, right: 8 })
                  .backgroundColor("sys.color.comp_background_gray").borderRadius(4)
                  .onClick(() => { this.deleteLogFile(f.name); })
              }
              .width("100%").padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor("sys.color.background_primary").borderRadius(8)
            }
          }, (f: LogFileInfo): string => f.name)
        }
        .layoutWeight(1).width("100%").scrollBar(BarState.Auto)
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      }

      Divider().color("sys.color.comp_background_emphasize").strokeWidth(0.5)

      Row({ space: 12 }) {
        Text("导出全部").fontSize(13).fontColor("#007AFF")
          .textShadow(ImmersiveStyles.textShadow(this.isDark))
          .padding({ top: 8, bottom: 8, left: 12, right: 12 })
          .onClick(() => { this.exportAllLogs(); })
        Blank()
        Text("清空全部").fontSize(13).fontColor("#F44336")
          .textShadow(ImmersiveStyles.textShadow(this.isDark))
          .padding({ top: 8, bottom: 8, left: 12, right: 12 })
          .onClick(() => { this.clearAllLogs(); })
      }.width("100%").padding({ left: 16, right: 16, top: 6, bottom: 12 })
    }
    .width("100%").height("100%")
    .backgroundColor("sys.color.background_secondary")
  }

  @Builder
  logToolsRow() {
    Row({ space: 8 }) {
      Text("Debug日志").fontSize(11).fontColor("sys.color.font_secondary")
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
      // 自定义开关：Toggle 的 onChange 在部分设备上不可靠，用 Text 点击切换
      Text(this.debugLogOn ? "ON" : "OFF")
        .fontSize(10).fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(44).height(22)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.debugLogOn ? "#007AFF" : "#B0B0B0")
        .borderRadius(11)
        .onClick(() => { this.toggleDebugLog(!this.debugLogOn); })

      Blank()
      Text(this.capturing ? "停止" : "抓取")
        .fontSize(12)
        .fontColor(this.capturing ? Color.White : "sys.color.font_secondary")
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
        .padding({ top: 4, bottom: 4, left: 10, right: 10 })
        .backgroundColor(this.capturing ? "#E53935" : "sys.color.comp_background_gray")
        .borderRadius(6)
        .onClick(() => {
          if (this.capturing) {
            this.stopCapture();
          } else {
            this.captureLog();
          }
        })
      Text("管理").fontSize(12).fontColor("sys.color.font_secondary")
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
        .padding({ top: 4, bottom: 4, left: 10, right: 10 })
        .backgroundColor("sys.color.comp_background_gray").borderRadius(6)
        .onClick(() => { this.openLogManager(); })
    }.width("100%").padding({ top: 6, bottom: 2 })
  }

  @Builder
  quickPanel() {
    Column({ space: 6 }) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.quickGroups, (g: QuickGroup) => {
            Text(g.title)
              .fontSize(11).fontColor(this.quickCategory === g.title ? Color.White : "sys.color.font_secondary")
              .textShadow(ImmersiveStyles.textShadow(this.isDark))
              .backgroundColor(this.quickCategory === g.title ? "#007AFF" : "sys.color.comp_background_gray")
              .padding({ top: 4, bottom: 4, left: 10, right: 10 }).borderRadius(12)
              .onClick(() => { this.quickCategory = g.title; })
          }, (g: QuickGroup): string => g.title)
        }
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width("100%")

      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.currentQuickCmds(), (c: QuickCmd) => {
            Text(c.label).fontSize(11).fontColor("sys.color.font_secondary").fontFamily("monospace")
              .textShadow(ImmersiveStyles.textShadow(this.isDark))
              .padding({ top: 5, bottom: 5, left: 10, right: 10 })
              .backgroundColor("sys.color.comp_background_gray").borderRadius(12)
              .opacity(this.isRunning ? 0.5 : 1)
              .onClick(() => { this.executeQuick(c.cmd); })
          }, (c: QuickCmd): string => c.label)
        }
      }
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width("100%")
    }.width("100%").padding({ top: 4, bottom: 2 })
  }

  private currentQuickCmds(): QuickCmd[] {
    for (let g of this.quickGroups) {
      if (g.title === this.quickCategory) { return g.commands; }
    }
    return this.quickGroups[0].commands;
  }

  @Builder
  historyRow() {
    if (this.cmdHistory.length > 0) {
      Row({ space: 6 }) {
        Text("最近:").fontSize(10).fontColor("sys.color.font_secondary")
          .textShadow(ImmersiveStyles.textShadow(this.isDark))
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.cmdHistory.slice(0, 8), (c: string, i: number) => {
              Text(c).fontSize(10).fontColor("sys.color.font_secondary").fontFamily("monospace")
                .textShadow(ImmersiveStyles.textShadow(this.isDark))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ top: 4, bottom: 4, left: 8, right: 8 })
                .backgroundColor("sys.color.comp_background_gray").borderRadius(10)
                .opacity(this.isRunning ? 0.5 : 1)
                .onClick(() => { this.executeQuick(c); })
            }, (c: string, i: number): string => i.toString())
          }
        }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
      }.width("100%").padding({ top: 2, bottom: 2 })
    }
  }

  @Builder
  inputField() {
    // $$ 双向绑定：inputText 变化时输入框显示同步更新，无需重建组件（避免失焦/键盘收起）
    TextInput({ placeholder: "hdc command...", text: $$this.inputText })
      .onSubmit(() => { this.executeCommand(); })
      .onKeyEvent((event: KeyEvent) => {
        if (event.type === KeyType.Down) {
          if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) { this.historyPrev(); }
          else if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) { this.historyNext(); }
        }
      })
      .fontSize(14).fontFamily("monospace").layoutWeight(1).height(40)
      .backgroundColor("sys.color.background_primary").borderRadius(8)
      .border({ width: 1, color: "sys.color.comp_background_emphasize" })
      .padding({ left: 10, right: 10 })
  }

  @Builder
  historyStepBtn(symbol: string, action: () => void, hint: string) {
    Column() {
      Text(symbol).fontSize(16).fontWeight(FontWeight.Bold)
        .fontColor(this.cmdHistory.length > 0 ? "sys.color.font_primary" : "sys.color.font_secondary")
        .textShadow(ImmersiveStyles.textShadow(this.isDark))
    }
    .width(36).height(40)
    .justifyContent(FlexAlign.Center)
    .backgroundColor("sys.color.comp_background_gray")
    .borderRadius(8)
    .enabled(this.cmdHistory.length > 0)
    .onClick(action)
    .accessibilityText(hint)
  }

  @Builder
  inputArea() {
    Row({ space: 6 }) {
      // 手机键盘没有上下键，提供触摸式历史回翻按钮（↑ 上一条 / ↓ 下一条）
      this.historyStepBtn("↑", () => { this.historyPrev(); }, "上一条命令")
      this.historyStepBtn("↓", () => { this.historyNext(); }, "下一条命令")

      this.inputField()

      if (this.isRunning) {
        Button("Cancel")
          .fontSize(13).fontColor(Color.White)
          .backgroundColor("#E53935").borderRadius(8).height(40).padding({ left: 12, right: 12 })
          .onClick(() => { this.cancelCommand(); })
      } else {
        Button("Send")
          .fontSize(13).fontColor(Color.White)
          .backgroundColor("#007AFF").borderRadius(8).height(40).padding({ left: 14, right: 14 })
          .onClick(() => { this.executeCommand(); })
      }
    }.width("100%").padding({ top: 6 })
  }

  build() {
    // @Entry 根节点必须是容器组件，外层包 Stack，内层 WallpaperHost 提供全局壁纸背景
    Stack() {
      WallpaperHost() {
        Column() {
          this.headerRow()
          this.statusLine()

          Column() { this.terminalColumns() }
            .layoutWeight(1).width("100%").padding({ left: 12, right: 12 })
            .backgroundColor("sys.color.background_primary").borderRadius(12)
            .border({ width: 1, color: "sys.color.comp_background_emphasize" })

          Column() {
            this.connectBar()
            this.logToolsRow()
            this.quickPanel()
            this.historyRow()
            this.inputArea()
          }.width("100%").padding({ left: 12, right: 12, bottom: 12 })
        }
        .width("100%").height("100%")
        .backgroundColor(Color.Transparent)
        .padding({ top: AppUtil.getStatusBarHeight() + "px" as string })
        // 已抓取日志管理面板
        .bindSheet(this.showLogManager, this.logManagerSheet(), {
          height: 520,
          dragBar: true,
          backgroundColor: $r('sys.color.background_secondary'),
          showClose: false
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
