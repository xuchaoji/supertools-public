import { HMRouter, HMRouterMgr } from "@hadss/hmrouter";
import hilog from "@ohos.hilog";
import { AppUtil, PreferencesUtil } from "@pura/harmony-utils";
import { HdcService, HdcShellResult } from "../utils/HdcService";
import { connection } from "@kit.NetworkKit";
import { KeyCode } from "@kit.InputKit";
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';

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

const MAX_ENTRIES: number = 800;
const DEFAULT_TIMEOUT_MS: number = 30000;
const HISTORY_KEY: string = 'hdc_history';
const MAX_HISTORY: number = 20;

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
  @Local inputEpoch: number = 0;
  @Local followOutput: boolean = true;
  private scroller: Scroller = new Scroller();
  private hdcService: HdcService = new HdcService();
  private entrySeq: number = 0;

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
        { label: 'hilog', cmd: 'shell hilog -x' },
        { label: 'crash', cmd: 'shell hilog -b crash -n 20' },
        { label: 'main 30', cmd: 'shell hilog -b main -n 30' },
        { label: 'dmesg', cmd: 'shell dmesg | tail -20' },
      ]
    }
  ];

  aboutToAppear(): void {
    hilog.info(0x0000, "HDC_Z", "HdcDebugPage aboutToAppear");
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
      this.executeQuick("list targets -v");
    });
  }

  aboutToDisappear(): void {
    this.hdcService.destroy();
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
    this.inputEpoch++;
    this.historyIndex = -1;
    this.isRunning = true;
    const r = await this.hdcService.execCommand(cmd, DEFAULT_TIMEOUT_MS);
    this.printResult(r);
    this.isRunning = false;
  }

  private async executeQuick(cmd: string): Promise<void> {
    if (this.isRunning) return;
    hilog.info(0x0000, "HDC_Z", "executeQuick: %{public}s", cmd);
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
          this.cmdHistory = arr.filter((s: string) => typeof s === 'string' && s.length > 0);
        }
      }
    } catch (e) {
      hilog.info(0x0000, "HDC_Z", "loadHistory failed");
    }
  }

  private pushHistory(cmd: string): void {
    const idx = this.cmdHistory.indexOf(cmd);
    if (idx >= 0) { this.cmdHistory.splice(idx, 1); }
    this.cmdHistory.unshift(cmd);
    if (this.cmdHistory.length > MAX_HISTORY) { this.cmdHistory.pop(); }
    this.historyIndex = -1;
    try { PreferencesUtil.putSync(HISTORY_KEY, JSON.stringify(this.cmdHistory)); } catch (e) { /* ignore */ }
  }

  private historyPrev(): void {
    if (this.cmdHistory.length === 0) { return; }
    this.historyIndex = this.historyIndex < 0 ? this.cmdHistory.length - 1 : Math.max(0, this.historyIndex - 1);
    this.inputText = this.cmdHistory[this.historyIndex];
    this.inputEpoch++;
  }

  private historyNext(): void {
    if (this.historyIndex < 0) { return; }
    this.historyIndex++;
    if (this.historyIndex >= this.cmdHistory.length) {
      this.historyIndex = -1;
      this.inputText = "";
    } else {
      this.inputText = this.cmdHistory[this.historyIndex];
    }
    this.inputEpoch++;
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
      Blank()
      Text(this.serverStatus === "ready" ? "● Server" : this.serverStatus === "failed" ? "● Failed" : "● Starting")
        .fontSize(11).fontColor(
          this.serverStatus === "ready" ? "#28A745" : this.serverStatus === "failed" ? "#F44336" : "#FF9800"
        ).fontWeight(FontWeight.Medium)
      Text("Copy").fontSize(12).fontColor("sys.color.font_secondary")
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor("sys.color.comp_background_gray").borderRadius(6)
        .onClick(() => { this.copyAll(); })
      Text("Clear").fontSize(12).fontColor("sys.color.font_secondary")
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
      Blank()
      Text(this.isConnected ? "●" : "○").fontSize(12)
        .fontColor(this.isConnected ? "#28A745" : "sys.color.font_secondary")
    }.width("100%").padding({ left: 16, right: 16, top: 2, bottom: 4 })
  }

  @Builder
  terminalColumns() {
    Column() {
      Row({ space: 8 }) {
        Text("Terminal").fontSize(13).fontWeight(FontWeight.Bold).fontColor("sys.color.font_emphasize")
        Text(this.entries.length + " 行").fontSize(10).fontColor("sys.color.font_secondary")
        Blank()
        Text(this.followOutput ? "⤓ 跟随" : "⤒ 暂停")
          .fontSize(11).fontColor(this.followOutput ? "#007AFF" : "sys.color.font_secondary")
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
              .copyOption(CopyOptions.LocalDevice)
              .width("100%").padding({ top: 2, bottom: 2, left: 12, right: 12 })
          }
        }, (e: TerminalEntry): string => e.uid.toString())

        if (this.isRunning) {
          ListItem() {
            Row() {
              LoadingProgress().width(12).height(12).margin({ right: 6 })
              Text("running...").fontSize(12).fontColor("sys.color.font_secondary").fontFamily("monospace")
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

  @Builder
  quickPanel() {
    Column({ space: 6 }) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.quickGroups, (g: QuickGroup) => {
            Text(g.title)
              .fontSize(11).fontColor(this.quickCategory === g.title ? Color.White : "sys.color.font_secondary")
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
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.cmdHistory.slice(0, 8), (c: string, i: number) => {
              Text(c).fontSize(10).fontColor("sys.color.font_secondary").fontFamily("monospace")
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
    TextInput({ placeholder: "hdc command...（↑↓ 回翻历史）", text: this.inputText })
      .onChange((v: string) => { this.inputText = v; })
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
  inputArea() {
    Row({ space: 8 }) {
      // Recreate the TextInput when inputEpoch changes so recalled history
      // commands actually appear in the field (text is only applied on create).
      if (this.inputEpoch % 2 === 0) {
        this.inputField()
      } else {
        this.inputField()
      }

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
    Column() {
      this.headerRow()
      this.statusLine()

      Column() { this.terminalColumns() }
        .layoutWeight(1).width("100%").padding({ left: 12, right: 12 })
        .backgroundColor("sys.color.background_primary").borderRadius(12)
        .border({ width: 1, color: "sys.color.comp_background_emphasize" })

      Column() {
        this.connectBar()
        this.quickPanel()
        this.historyRow()
        this.inputArea()
      }.width("100%").padding({ left: 12, right: 12, bottom: 12 })
    }
    .width("100%").height("100%")
    .backgroundColor("sys.color.background_primary")
    .padding({ top: AppUtil.getStatusBarHeight() + "px" as string })
  }
}
