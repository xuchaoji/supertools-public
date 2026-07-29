import { HMRouter, HMRouterMgr } from "@hadss/hmrouter";
import { AppUtil } from "@pura/harmony-utils";
import { HdcService, HdcConnectionState, HdcShellResult, HdcConnectionResult } from "../utils/HdcService";

type TerminalEntryType = "input" | "output" | "error" | "system";

interface TerminalEntry {
  type: TerminalEntryType;
  text: string;
  timestamp: number;
}

@ObservedV2
class TerminalState {
  @Trace connectionState: HdcConnectionState = HdcConnectionState.DISCONNECTED;
  @Trace stateMessage: string = "disconnected";
  @Trace inputText: string = "";
  @Trace host: string = "192.168.3.39";
  @Trace port: string = "44769";
  @Trace showSettings: boolean = true;
}

@HMRouter({ pageUrl: "hdcDebugPage" })
@Entry
@ComponentV2
export struct HdcDebugPage {
  @Local terminal: TerminalState = new TerminalState();
  @Local entries: TerminalEntry[] = [];
  @Local isRunning: boolean = false;
  private scroller: Scroller = new Scroller();
  private hdcService: HdcService = new HdcService();

  aboutToAppear(): void {
    this.addSystemMessage("=== SuperTools HDC ===");
    this.addSystemMessage("Native TCP to hdcd via Rust NAPI");
    this.addSystemMessage("1. Enable Wireless Debug in Developer Options");
    this.addSystemMessage("2. Enter IP:Port shown there, tap Connect");
  }

  aboutToDisappear(): void {
    this.hdcService.destroy();
  }

  private async doConnect(): Promise<void> {
    const port: number = parseInt(this.terminal.port);
    if (isNaN(port) || port < 1 || port > 65535) {
      this.addErrorMessage("invalid port: " + this.terminal.port);
      return;
    }
    this.hdcService.setTarget(this.terminal.host, port);
    this.terminal.showSettings = false;

    this.terminal.connectionState = HdcConnectionState.CONNECTING;
    this.terminal.stateMessage = "connecting " + this.hdcService.getTarget() + " ...";
    this.addSystemMessage("--- connect " + this.hdcService.getTarget() + " ---");

    const result: HdcConnectionResult = await this.hdcService.checkConnection();
    if (result.connected) {
      this.terminal.connectionState = HdcConnectionState.CONNECTED;
      this.terminal.stateMessage = "connected " + this.hdcService.getTarget();
      this.addSystemMessage("connected OK");
      if (result.deviceCount !== undefined && result.deviceCount > 0) {
        this.addSystemMessage("found " + result.deviceCount + " device(s)");
      }
      this.executeQuickCommand("shell uname -a");
    } else {
      this.terminal.connectionState = HdcConnectionState.DISCONNECTED;
      this.terminal.stateMessage = result.error || "failed";
      this.addErrorMessage("failed: " + (result.error || "unknown"));
    }
  }

  private async executeCommand(): Promise<void> {
    const cmd: string = this.terminal.inputText.trim();
    if (cmd.length === 0) return;
    this.addLine("input", "$ " + cmd);
    this.terminal.inputText = "";
    this.isRunning = true;

    const result: HdcShellResult = await this.hdcService.execCommand(cmd);
    this.printResult(result);
    this.isRunning = false;
  }

  private async executeQuickCommand(cmd: string): Promise<void> {
    this.addLine("input", "$ " + cmd);
    this.isRunning = true;
    const result: HdcShellResult = await this.hdcService.execCommand(cmd);
    this.printResult(result);
    this.isRunning = false;
  }

  private printResult(result: HdcShellResult): void {
    if (result.stdout.length > 0) {
      const lines: string[] = result.stdout.split("\n");
      for (let i: number = 0; i < lines.length; i++) {
        if (lines[i].length > 0) this.addLine("output", lines[i]);
      }
    }
    if (result.stderr.length > 0) {
      const errs: string[] = result.stderr.split("\n");
      for (let i: number = 0; i < errs.length; i++) {
        if (errs[i].length > 0) this.addLine("error", errs[i]);
      }
    }
    if (result.exitCode !== 0) {
      this.addLine("error", "exit: " + result.exitCode);
    }
  }

  private addLine(type: TerminalEntryType, text: string): void {
    this.entries.push({ type: type, text: text, timestamp: Date.now() });
  }

  private addSystemMessage(text: string): void { this.addLine("system", text); }
  private addErrorMessage(text: string): void { this.addLine("error", text); }

  @Builder
  settingsPanel() {
    if (this.terminal.showSettings) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text("Host:").fontSize(13).fontColor("sys.color.font_primary")
          TextInput({ text: this.terminal.host })
            .onChange((v: string) => { this.terminal.host = v; })
            .fontSize(14).layoutWeight(1).height(36)
            .backgroundColor("sys.color.background_primary").borderRadius(6)
            .border({ width: 1, color: "sys.color.comp_background_emphasize" })
        }
        Row({ space: 8 }) {
          Text("Port:").fontSize(13).fontColor("sys.color.font_primary")
          TextInput({ text: this.terminal.port })
            .onChange((v: string) => { this.terminal.port = v; })
            .fontSize(14).layoutWeight(1).height(36).type(InputType.Number)
            .backgroundColor("sys.color.background_primary").borderRadius(6)
            .border({ width: 1, color: "sys.color.comp_background_emphasize" })
        }
        Row({ space: 8 }) {
          Button("Connect")
            .fontSize(14).fontColor(Color.White)
            .backgroundColor("#4CAF50").borderRadius(8).height(40).layoutWeight(1)
            .enabled(this.terminal.connectionState !== HdcConnectionState.CONNECTING)
            .onClick(() => { this.doConnect(); })
          Button("Disconnect")
            .fontSize(14).fontColor("sys.color.font_secondary")
            .backgroundColor("sys.color.comp_background_gray").borderRadius(8).height(40).layoutWeight(1)
            .onClick(() => {
              this.hdcService.destroy();
              this.terminal.connectionState = HdcConnectionState.DISCONNECTED;
              this.terminal.stateMessage = "disconnected";
              this.addSystemMessage("--- disconnected ---");
            })
        }
      }
      .width("100%").padding(12)
      .backgroundColor("sys.color.comp_background_gray").borderRadius(8)
      .margin({ bottom: 6 })
    }
  }

  @Builder
  connectionIndicator() {
    Row({ space: 6 }) {
      Circle({ width: 8, height: 8 })
        .fill(
          this.terminal.connectionState === HdcConnectionState.CONNECTED ? "#4CAF50" :
          this.terminal.connectionState === HdcConnectionState.CONNECTING ? "#FF9800" : "#F44336"
        )
      Text(this.terminal.stateMessage)
        .fontSize(12).fontColor("sys.color.font_secondary").fontFamily("monospace")
    }.width("100%")
  }

  @Builder
  terminalContent() {
    Column() {
      Row({ space: 8 }) {
        Text("Terminal").fontSize(13).fontWeight(FontWeight.Bold).fontColor("sys.color.font_emphasize")
        Blank()
        Text("Clear")
          .fontSize(11).fontColor("sys.color.font_secondary")
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor("sys.color.comp_background_gray").borderRadius(4)
          .onClick(() => { this.entries = []; this.addSystemMessage("=== cleared ==="); })
      }
      .width("100%").padding({ left: 12, right: 12, top: 8, bottom: 4 })

      Divider().color("sys.color.comp_background_emphasize").strokeWidth(0.5)

      List({ scroller: this.scroller }) {
        ForEach(this.entries, (entry: TerminalEntry, index: number) => {
          ListItem() {
            Text(entry.text)
              .fontSize(13).fontFamily("monospace")
              .fontColor(
                entry.type === "error" ? "#F44336" :
                entry.type === "system" ? "#FF9800" :
                entry.type === "input" ? "#4CAF50" : "sys.color.font_primary"
              )
              .width("100%").padding({ top: 2, bottom: 2, left: 12, right: 12 })
          }
        }, (_: TerminalEntry, index: number): string => index.toString())

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
    .width("100%").layoutWeight(1)
    .backgroundColor("sys.color.background_primary")
    .borderRadius(12)
    .border({ width: 1, color: "sys.color.comp_background_emphasize" })
  }

  @Builder
  inputArea() {
    Row({ space: 8 }) {
      TextInput({ placeholder: "shell command...", text: this.terminal.inputText })
        .onChange((v: string) => { this.terminal.inputText = v; })
        .onSubmit(() => { this.executeCommand(); })
        .fontSize(14).fontFamily("monospace").layoutWeight(1).height(40)
        .backgroundColor("sys.color.background_primary").borderRadius(8)
        .border({ width: 1, color: "sys.color.comp_background_emphasize" })
        .padding({ left: 10, right: 10 })

      Button("Send")
        .fontSize(13).fontColor(Color.White)
        .backgroundColor(
          this.terminal.connectionState === HdcConnectionState.CONNECTED && !this.isRunning ?
          "#007AFF" : "#CCCCCC"
        )
        .borderRadius(8).height(40).padding({ left: 14, right: 14 })
        .enabled(this.terminal.connectionState === HdcConnectionState.CONNECTED && !this.isRunning)
        .onClick(() => { this.executeCommand(); })
    }.width("100%").padding({ top: 8 })
  }

  @Builder
  quickCommands() {
    Row({ space: 6 }) {
      this.qBtn("devices", "list targets -v")
      this.qBtn("check", "checkserver")
      this.qBtn("ps", "shell ps")
      this.qBtn("net", "shell netstat -tln")
      this.qBtn("uname", "shell uname -a")
    }.width("100%").padding({ top: 4, bottom: 4 })
  }

  @Builder
  qBtn(label: string, command: string) {
    Text(label)
      .fontSize(11).fontColor("sys.color.font_secondary").fontFamily("monospace")
      .padding({ top: 4, bottom: 4, left: 8, right: 8 })
      .backgroundColor("sys.color.comp_background_gray").borderRadius(6)
      .onClick(() => { this.executeQuickCommand(command); })
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Image("app.media.back_arrow")
          .width(24).height(24).fillColor("sys.color.font_primary")
          .onClick(() => { HMRouterMgr.pop(); })

        Text("HDC Debug")
          .fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor("sys.color.font_emphasize")

        Blank()

        Text("Settings")
          .fontSize(13).fontColor("sys.color.font_secondary")
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .border({ width: 1, color: "sys.color.comp_background_emphasize" })
          .borderRadius(6)
          .onClick(() => { this.terminal.showSettings = !this.terminal.showSettings; })
      }
      .width("100%").padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Column() {
        this.settingsPanel()
        this.connectionIndicator()
      }.padding({ left: 16, right: 16, bottom: 8 }).width("100%")

      Column() { this.terminalContent() }
        .layoutWeight(1).width("100%").padding({ left: 12, right: 12 })

      Column() {
        this.quickCommands()
        this.inputArea()
      }.width("100%").padding({ left: 12, right: 12, bottom: 12 })
    }
    .width("100%").height("100%")
    .backgroundColor("sys.color.background_primary")
    .padding({ top: AppUtil.getStatusBarHeight() + "px" as string })
  }
}