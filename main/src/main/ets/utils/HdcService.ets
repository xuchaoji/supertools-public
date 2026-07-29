import { BusinessError } from "@kit.BasicServicesKit";
import nativeHdc from "libhdc_napi.so";

export interface HdcConnectionResult {
  connected: boolean;
  deviceCount?: number;
  error?: string;
}

export interface HdcShellResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

export enum HdcConnectionState {
  DISCONNECTED = 0,
  CONNECTING = 1,
  CONNECTED = 2
}

interface NativeHdcStatus {
  connected: boolean;
  device_count?: number;
  error?: string;
}

interface NativeHdcOutput {
  exit_code: number;
  stdout: string;
  stderr: string;
}

export class HdcService {
  private host: string = "127.0.0.1";
  private port: number = 8710;

  setTarget(host: string, port: number): void {
    this.host = host;
    this.port = port;
  }

  getTarget(): string {
    return this.host + ":" + this.port;
  }

  async checkConnection(): Promise<HdcConnectionResult> {
    try {
      const status: NativeHdcStatus = nativeHdc.hdcCheckConnection(this.host, this.port);
      return {
        connected: status.connected,
        deviceCount: status.device_count !== undefined ? status.device_count : undefined,
        error: status.error !== undefined ? status.error : undefined
      };
    } catch (e) {
      return { connected: false, error: "napi failed: " + JSON.stringify(e) };
    }
  }

  async execCommand(cmd: string): Promise<HdcShellResult> {
    try {
      const output: NativeHdcOutput = nativeHdc.hdcExecuteShell(cmd, this.host, this.port);
      return {
        exitCode: output.exit_code,
        stdout: output.stdout,
        stderr: output.stderr
      };
    } catch (e) {
      return { exitCode: -1, stdout: "", stderr: "napi failed: " + JSON.stringify(e) };
    }
  }

  getReceivedHex(): string {
    return "";
  }

  destroy(): void {
    // NAPI connections are per-call, no persistent socket
  }
}
