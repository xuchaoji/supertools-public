import { HMRouter, HMRouterMgr } from "@hadss/hmrouter";
import hilog from "@ohos.hilog";
import { AppUtil, PreferencesUtil } from "@pura/harmony-utils";
import { HdcService, HdcShellResult } from "../utils/HdcService";
import { connection } from "@kit.NetworkKit";

type EntryType = "input" | "output" | "error" | "system";

interface TerminalEntry {
  type: EntryType;
  text: string;
  timestamp: number;
}

@HMRouter({ pageUrl: "hdcDebugPage" })
@Entry
@ComponentV2
export struct HdcDebugPage {
  @Local entries: TerminalEntry[] = [];
  @Local inputText: string = "";
  @Local isRunning: boolean = false;
  @Local serverReady: boolean = false;
  @Local connectIp: string = "";
  @Local connectPort: string = "";
  @Local isConnected: boolean = false;
  private scroller: Scroller = new Scroller();
  private hdcService: HdcService = new HdcService();

  aboutToAppear(): void {
    hilog.info(0x0000, "HDC_Z", "HdcDebugPage aboutToAppear");
    this.addSystem("=== SuperTools HDC ===");
    this.addSystem("Starting HDC server...");
    this.hdcService.startServer();
    PreferencesUtil.get("hdc_port", "").then((v) => {
      if (v) { this.connectPort = v as string; }
    });
    this.getLocalIp();

    setTimeout(() => {
      this.serverReady = true;
      this.addSystem("Server ready");
      this.executeQuick("list targets -v");
    }, 1500);
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

  private async connectDevice(): Promise<void> {
    let ip = this.connectIp.trim();
    let port = this.connectPort.trim() || "8710";
    if (!ip) return;
    PreferencesUtil.put("hdc_port", port);
    let cmd = "tconn " + ip + ":" + port;
    this.addSystem("Connecting " + ip + ":" + port + "...");
    this.isRunning = true;
    let r = await this.hdcService.execCommand(cmd);
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
    this.addInput(cmd);
    this.inputText = "";
    this.isRunning = true;
    const r = await this.hdcService.execCommand(cmd);
    this.printResult(r);
    this.isRunning = false;
  }

  private async executeQuick(cmd: string): Promise<void> {
    hilog.info(0x0000, "HDC_Z", "executeQuick: %{public}s", cmd);
    this.addInput(cmd);
    this.isRunning = true;
    const r = await this.hdcService.execCommand(cmd);
    this.printResult(r);
    this.isRunning = false;
  }

  private printResult(r: HdcShellResult): void {
    const text = r.stdout || r.stderr || "";
    if (text) {
      text.split("\n").filter(l => l).forEach(l => this.addOutput(l));
    }
    if (r.exitCode !== 0) this.addError("exit: " + r.exitCode);
  }

  private addEntry(type: EntryType, text: string): void {
    let e: TerminalEntry = { type: type, text: text, timestamp: Date.now() };
    this.entries.push(e);
  }
  private addSystem(t: string): void { this.addEntry("system", t); }
  private addInput(t: string): void { this.addEntry("input", "$ " + t); }
  private addOutput(t: string): void { this.addEntry("output", t); }
  private addError(t: string): void { this.addEntry("error", t); }

  @Builder
  connectBar() {
    Column() {
      Row({ space: 6 }) {
        TextInput({ placeholder: "IP address", text: this.connectIp })
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
  terminalColumns() {
    Row({ space: 8 }) {
      Text("Terminal").fontSize(13).fontWeight(FontWeight.Bold).fontColor("sys.color.font_emphasize")
      Blank()
      Text("Clear").fontSize(11).fontColor("sys.color.font_secondary")
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor("sys.color.comp_background_gray").borderRadius(4)
        .onClick(() => { this.entries = []; this.addSystem("=== cleared ==="); })
    }
    .width("100%").padding({ left: 12, right: 12, top: 8, bottom: 4 })

    Divider().color("sys.color.comp_background_emphasize").strokeWidth(0.5)

    List({ scroller: this.scroller }) {
      ForEach(this.entries, (e: TerminalEntry, i: number) => {
        ListItem() {
          Text(e.text).fontSize(13).fontFamily("monospace").fontColor(
            e.type === "error" ? "#F44336" : e.type === "system" ? "#FF9800" :
            e.type === "input" ? "#4CAF50" : "sys.color.font_primary"
          ).width("100%").padding({ top: 2, bottom: 2, left: 12, right: 12 })
        }
      }, (_: TerminalEntry, i: number): string => i.toString())

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

  @Builder
  inputArea() {
    Row({ space: 8 }) {
      TextInput({ placeholder: "hdc command...", text: this.inputText })
        .onChange((v: string) => { this.inputText = v; })
        .onSubmit(() => { this.executeCommand(); })
        .fontSize(14).fontFamily("monospace").layoutWeight(1).height(40)
        .backgroundColor("sys.color.background_primary").borderRadius(8)
        .border({ width: 1, color: "sys.color.comp_background_emphasize" })
        .padding({ left: 10, right: 10 })

      Button("Send")
        .fontSize(13).fontColor(Color.White)
        .backgroundColor(!this.isRunning ? "#007AFF" : "#CCCCCC")
        .borderRadius(8).height(40).padding({ left: 14, right: 14 })
        .enabled(!this.isRunning)
        .onClick(() => { this.executeCommand(); })
    }.width("100%").padding({ top: 8 })
  }

  @Builder
  quickBtn(label: string, cmd: string) {
    Text(label).fontSize(11).fontColor("sys.color.font_secondary").fontFamily("monospace")
      .padding({ top: 4, bottom: 4, left: 8, right: 8 })
      .backgroundColor("sys.color.comp_background_gray").borderRadius(6)
      .onClick(() => { this.executeQuick(cmd); })
  }

  @Builder
  quickBar() {
    Row({ space: 6 }) {
      this.quickBtn("targets", "list targets -v")
      this.quickBtn("version", "version")
      this.quickBtn("ps", "shell ps")
      this.quickBtn("uname", "shell uname -a")
      this.quickBtn("net", "shell netstat -tln")
    }.width("100%").padding({ top: 4, bottom: 4 })
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Image("app.media.back_arrow").width(24).height(24).fillColor("sys.color.font_primary")
          .onClick(() => { HMRouterMgr.pop(); })
        Text("HDC Debug").fontSize(20).fontWeight(FontWeight.Bold).fontColor("sys.color.font_emphasize")
        Blank()
      }
      .width("100%").padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Column() { this.terminalColumns() }
        .layoutWeight(1).width("100%").padding({ left: 12, right: 12 })
        .backgroundColor("sys.color.background_primary").borderRadius(12)
        .border({ width: 1, color: "sys.color.comp_background_emphasize" })

      Column() {
        this.connectBar()
        this.quickBar()
        this.inputArea()
      }.width("100%").padding({ left: 12, right: 12, bottom: 12 })
    }
    .width("100%").height("100%")
    .backgroundColor("sys.color.background_primary")
    .padding({ top: AppUtil.getStatusBarHeight() + "px" as string })
  }
}
