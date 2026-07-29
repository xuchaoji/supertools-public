
export interface HdcStatus {
  connected: boolean;
  deviceCount?: number;
  error?: string;
}

export interface HdcOutput {
  exitCode: number;
  stdout: string;
  stderr: string;
}

export declare function hdcCheckConnection(host?: string, port?: number): HdcStatus;
export declare function hdcExecuteShell(command: string, host?: string, port?: number): HdcOutput;
export declare function hdcPing(host?: string, port?: number): boolean;
export declare function hdcServerVersion(host?: string, port?: number): HdcOutput;
