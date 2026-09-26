import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { util } from '@kit.ArkTS';

const HEADER_LIMIT_BYTES: number = 16 * 1024;
const DEFAULT_MAX_TRANSFER_BYTES: number = 200 * 1024 * 1024;
/** 通用 POST 回显缓冲上限：超出部分不保留，避免无界增长。 */
const ECHO_LIMIT_BYTES: number = 1024 * 1024;
/** 单次发送的分片大小，下载时用于把峰值内存压到 O(64KB)。 */
const SEND_CHUNK_BYTES: number = 64 * 1024;
const UPLOAD_API_PATH: string = '/api/upload';

/** 通用 POST 回显响应体（键名与原实现保持一致）。 */
interface EchoResponse {
  code: number;
  message: string;
  path: string;
  received_data: string;
}

/** 请求头解析结果；errorCode 非 0 时 meta 无效，调用方据此返回错误响应。 */
interface RequestMetaResult {
  meta: ParsedRequestMeta | null;
  errorCode: number;
  errorMessage: string;
}

interface ParsedRequestMeta {
  method: string;
  path: string;
  headers: Record<string, string>;
  headerLength: number;
  contentLength: number;
}

/** 单连接状态：header 阶段只缓存 ≤16KB，body 阶段直接落盘，不再累积整包。 */
class ConnState {
  headerChunks: Uint8Array[] = [];
  headerLength: number = 0;
  meta: ParsedRequestMeta | null = null;
  bodyReceived: number = 0;
  uploadFile: fs.File | null = null;
  uploadPath: string = '';
  echoChunks: Uint8Array[] = [];
  echoLength: number = 0;
  echoOverflow: boolean = false;
  closed: boolean = false;
}

export class WebServerUtil {
  private static instance: WebServerUtil | undefined = undefined;
  private tcpServer: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
  private port: number = 8088;
  private rootDir: string = '';
  private _isRunning: boolean = false;
  private encoder = new util.TextEncoder();
  private maxTransferBytes: number = DEFAULT_MAX_TRANSFER_BYTES;

  private rateLimits: Map<string, number> = new Map();
  private lastAccessTimes: Map<string, number> = new Map();

  public static getInstance(): WebServerUtil {
    if (!WebServerUtil.instance) {
      WebServerUtil.instance = new WebServerUtil();
    }
    return WebServerUtil.instance;
  }

  public get isRunning(): boolean {
    return this._isRunning;
  }

  public get maxTransferMb(): number {
    return Math.floor(this.maxTransferBytes / 1024 / 1024);
  }

  public setMaxTransferMb(mb: number): void {
    const safeMb: number = Math.max(1, Math.min(2048, Math.floor(mb)));
    this.maxTransferBytes = safeMb * 1024 * 1024;
  }

  /** 局域网访问地址。本机调试工具，不做访问鉴权，直接用这个地址即可。 */
  public getAccessUrl(): string {
    return `http://${this.getIpAddress()}:${this.port}/`;
  }

  public init(baseDir: string, port: number = 8088): void {
    this.rootDir = this.normalizeRoot(baseDir);
    this.port = port;
    console.info(`[WebServer] Init RootDir: ${this.rootDir}, Port: ${this.port}`);
    this.ensureRootExist();
    AppStorage.setOrCreate('RecentAccessFile', 'Web运行中');
  }

  public setRateLimit(filePath: string, minutes: number): void {
    if (minutes <= 0) {
      this.rateLimits.delete(filePath);
      this.lastAccessTimes.delete(filePath);
    } else {
      this.rateLimits.set(filePath, minutes * 60 * 1000);
    }
  }

  public getRateLimitMinutes(filePath: string): number {
    const limitMs: number | undefined = this.rateLimits.get(filePath);
    return limitMs ? limitMs / 60000 : 0;
  }

  private checkRateLimit(filePath: string): boolean {
    if (!this.rateLimits.has(filePath)) {
      return true;
    }
    const limitMs: number = this.rateLimits.get(filePath) || 0;
    const lastAccess: number = this.lastAccessTimes.get(filePath) || 0;
    return Date.now() - lastAccess >= limitMs;
  }

  private recordAccess(filePath: string): void {
    if (this.rateLimits.has(filePath)) {
      this.lastAccessTimes.set(filePath, Date.now());
    }
    const parts: string[] = filePath.split('/');
    AppStorage.setOrCreate('RecentAccessFile', parts[parts.length - 1]);
  }

  private normalizeRoot(path: string): string {
    let normalized: string = path.replace(/\\/g, '/');
    while (normalized.endsWith('/') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  private ensureRootExist(): void {
    try {
      if (!fs.accessSync(this.rootDir)) {
        fs.mkdirSync(this.rootDir, true);
      }
    } catch (e) {
      console.error(`[WebServer] Init dir failed: ${JSON.stringify(e)}`);
    }
  }

  private ensureDirSync(dirPath: string): void {
    try {
      if (fs.accessSync(dirPath)) {
        return;
      }
      fs.mkdirSync(dirPath, true);
    } catch (e) {
      console.error(`[WebServer] mkdir failed: ${JSON.stringify(e)}`);
    }
  }

  public getIpAddress(): string {
    try {
      const ipInfo = wifiManager.getIpInfo();
      const ip: number = ipInfo.ipAddress;
      return (ip >>> 24) + '.' + (ip >> 16 & 0xFF) + '.' + (ip >> 8 & 0xFF) + '.' + (ip & 0xFF);
    } catch (e) {
      return '127.0.0.1';
    }
  }

  public start(): Promise<string> {
    return new Promise((resolve, reject) => {
      if (this._isRunning) {
        resolve('Server already running');
        return;
      }
      this.tcpServer = socket.constructTCPSocketServerInstance();
      const localAddress: socket.NetAddress = { address: '0.0.0.0', port: this.port, family: 1 };
      this.tcpServer.listen(localAddress, (err: BusinessError) => {
        if (err) {
          reject(err);
          return;
        }
        this._isRunning = true;
        console.info(`[WebServer] Server Started on port ${this.port}`);
        this.tcpServer.on('connect', (clientSocket: socket.TCPSocketConnection) => {
          const state = new ConnState();
          clientSocket.on('message', (value: socket.SocketMessageInfo) => {
            if (state.closed) {
              return;
            }
            try {
              this.onData(clientSocket, state, new Uint8Array(value.message));
            } catch (e) {
              console.error(`[WebServer] 请求处理异常: ${JSON.stringify(e)}`);
              this.failConnection(clientSocket, state, 500, 'Server Error');
            }
          });
        });
        resolve('Success');
      });
    });
  }

  public stop(): void {
    if (!this._isRunning) {
      return;
    }
    try {
      this.tcpServer.off('connect');
      this.tcpServer.close();
    } catch (e) {
      console.error(`[WebServer] stop failed: ${JSON.stringify(e)}`);
    }
    this._isRunning = false;
  }

  /**
   * 单个 TCP 分片的处理入口：header 阶段缓存 ≤16KB，body 阶段直接写文件，
   * 因此 200MB 上传的内存峰值与文件大小无关（旧实现每收到一片就重拼全量缓冲）。
   */
  private onData(clientSocket: socket.TCPSocketConnection, state: ConnState, chunk: Uint8Array): void {
    if (state.meta === null) {
      state.headerChunks.push(chunk);
      state.headerLength += chunk.length;
      const headerData: Uint8Array = this.combineChunks(state.headerChunks, state.headerLength);
      const parsed: RequestMetaResult = this.parseRequestMeta(headerData);
      if (parsed.errorCode !== 0) {
        this.failConnection(clientSocket, state, parsed.errorCode, parsed.errorMessage);
        return;
      }
      if (parsed.meta === null) {
        if (state.headerLength > HEADER_LIMIT_BYTES) {
          this.failConnection(clientSocket, state, 431, 'Request Header Fields Too Large');
        }
        return;
      }
      state.meta = parsed.meta;
      state.headerChunks = [];
      if (state.meta.contentLength > this.maxTransferBytes) {
        this.failConnection(clientSocket, state, 413, 'Payload Too Large');
        return;
      }
      if (state.meta.method === 'POST' && state.meta.path.split('?')[0] === UPLOAD_API_PATH) {
        if (!this.prepareUpload(clientSocket, state)) {
          return;
        }
      }
      // 同一分片里已到达的 body 部分（header 之后）立即进入 body 处理。
      const leftoverStart: number = state.meta.headerLength;
      if (state.headerLength > leftoverStart) {
        this.onBody(clientSocket, state, headerData.slice(leftoverStart, state.headerLength));
      } else if (state.meta.contentLength === 0) {
        this.finishRequest(clientSocket, state);
      }
      return;
    }
    this.onBody(clientSocket, state, chunk);
  }

  private onBody(clientSocket: socket.TCPSocketConnection, state: ConnState, data: Uint8Array): void {
    const meta: ParsedRequestMeta | null = state.meta;
    if (!meta) {
      return;
    }
    if (data.length > 0) {
      state.bodyReceived += data.length;
      if (state.bodyReceived > this.maxTransferBytes) {
        this.failConnection(clientSocket, state, 413, 'Payload Too Large');
        return;
      }
      const remaining: number = meta.contentLength - (state.bodyReceived - data.length);
      const usable: Uint8Array = data.length <= remaining ? data : data.slice(0, Math.max(remaining, 0));
      if (usable.length > 0) {
        if (state.uploadFile) {
          // 顺序写入：writeSync 省略 offset 时从 filePointer 继续，不传绝对偏移。
          fs.writeSync(state.uploadFile.fd,
            usable.buffer.slice(usable.byteOffset, usable.byteOffset + usable.byteLength));
        } else if (state.echoLength < ECHO_LIMIT_BYTES) {
          const room: number = ECHO_LIMIT_BYTES - state.echoLength;
          const take: number = Math.min(room, usable.length);
          state.echoChunks.push(usable.slice(0, take));
          state.echoLength += take;
          if (take < usable.length) {
            state.echoOverflow = true;
          }
        } else {
          state.echoOverflow = true;
        }
      }
    }
    if (state.bodyReceived >= meta.contentLength) {
      this.finishRequest(clientSocket, state);
    }
  }

  private finishRequest(clientSocket: socket.TCPSocketConnection, state: ConnState): void {
    const meta: ParsedRequestMeta | null = state.meta;
    if (!meta || state.closed) {
      return;
    }
    if (state.uploadFile) {
      const uploadPath: string = state.uploadPath;
      this.closeUpload(state);
      this.recordAccess(uploadPath);
      this.sendResponse(clientSocket, 200, 'OK', 'application/json',
        this.encoder.encodeInto('{"code":200,"msg":"Success"}'));
      state.closed = true;
      return;
    }
    state.closed = true;
    if (meta.method === 'POST') {
      this.handlePostRequest(clientSocket, meta, state);
    } else if (meta.method === 'GET') {
      this.handleGetRequest(clientSocket, meta.path);
    } else {
      this.sendErrorResponse(clientSocket, 405, 'Method Not Allowed');
    }
  }

  private closeUpload(state: ConnState): void {
    if (state.uploadFile) {
      try {
        fs.closeSync(state.uploadFile);
      } catch (e) {
        console.error(`[WebServer] 关闭上传文件失败: ${JSON.stringify(e)}`);
      }
      state.uploadFile = null;
    }
  }

  private failConnection(clientSocket: socket.TCPSocketConnection, state: ConnState,
    code: number, message: string): void {
    if (state.closed) {
      return;
    }
    state.closed = true;
    this.closeUpload(state);
    this.sendErrorResponse(clientSocket, code, message);
  }

  private combineChunks(chunks: Uint8Array[], expectedLength: number): Uint8Array {
    const result: Uint8Array = new Uint8Array(expectedLength);
    let offset: number = 0;
    for (const chunk of chunks) {
      const remaining: number = expectedLength - offset;
      if (remaining <= 0) {
        break;
      }
      const part: Uint8Array = chunk.length <= remaining ? chunk : chunk.slice(0, remaining);
      result.set(part, offset);
      offset += part.length;
    }
    return result;
  }

  private isDecimal(value: string): boolean {
    if (value.length === 0) {
      return false;
    }
    for (let i = 0; i < value.length; i++) {
      const code: number = value.charCodeAt(i);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  private decode(bytes: Uint8Array): string {
    // 每次新建解码器：共享的 stateful decoder 会跨连接污染。
    return util.TextDecoder.create('utf-8', { ignoreBOM: true }).decodeWithStream(bytes);
  }

  private parseRequestMeta(data: Uint8Array): RequestMetaResult {
    const text: string = this.decode(data);
    const headerEndIndex: number = text.indexOf('\r\n\r\n');
    if (headerEndIndex < 0) {
      return { meta: null, errorCode: 0, errorMessage: '' };
    }
    const headerPart: string = text.substring(0, headerEndIndex);
    const lines: string[] = headerPart.split('\r\n');
    const firstLine: string[] = lines[0].split(' ');
    if (firstLine.length < 2) {
      return { meta: null, errorCode: 400, errorMessage: 'Bad Request' };
    }
    const headers: Record<string, string> = {};
    let contentLength: number = 0;
    let chunked: boolean = false;
    for (let i = 1; i < lines.length; i++) {
      const colonIndex: number = lines[i].indexOf(':');
      if (colonIndex <= 0) {
        continue;
      }
      const key: string = lines[i].substring(0, colonIndex).trim().toLowerCase();
      const value: string = lines[i].substring(colonIndex + 1).trim();
      headers[key] = value;
      if (key === 'content-length') {
        // 非法长度必须显式拒绝：旧实现里 NaN 会让同一请求被反复响应。
        if (!this.isDecimal(value)) {
          return { meta: null, errorCode: 400, errorMessage: 'Bad Request' };
        }
        contentLength = Number(value);
        if (!Number.isFinite(contentLength)) {
          return { meta: null, errorCode: 400, errorMessage: 'Bad Request' };
        }
      } else if (key === 'transfer-encoding' && value.toLowerCase().indexOf('chunked') >= 0) {
        chunked = true;
      }
    }
    // 不支持分块传输：明确返回 411，而不是静默等待一个永远凑不齐的 body。
    if (chunked) {
      return { meta: null, errorCode: 411, errorMessage: 'Length Required' };
    }
    const headerLength: number = this.encoder.encodeInto(headerPart + '\r\n\r\n').length;
    const meta: ParsedRequestMeta = {
      method: firstLine[0].toUpperCase(), path: firstLine[1], headers: headers,
      headerLength: headerLength, contentLength: contentLength
    };
    return { meta: meta, errorCode: 0, errorMessage: '' };
  }

  /**
   * 逐段解码后再校验，是同时封堵 `%2e%2e%2f`（编码穿越）与 `%2F`（伪造分隔符）
   * 的唯一形式：旧实现先查 `..` 再解码，可被编码变形绕过。
   */
  private resolveSafePath(rawPath: string): string | null {
    let raw: string = rawPath;
    const queryIndex: number = raw.indexOf('?');
    if (queryIndex >= 0) {
      raw = raw.substring(0, queryIndex);
    }
    const segments: string[] = raw.split('/');
    const safeSegments: string[] = [];
    for (const segment of segments) {
      if (!segment || segment === '.') {
        continue;
      }
      let decoded: string = '';
      try {
        decoded = decodeURIComponent(segment);
      } catch (e) {
        return null;
      }
      if (!decoded || decoded === '.') {
        continue;
      }
      if (decoded === '..' || decoded.indexOf('/') >= 0 || decoded.indexOf('\\') >= 0 ||
        decoded.indexOf('\0') >= 0 || decoded.indexOf(':') >= 0) {
        return null;
      }
      safeSegments.push(decoded);
    }
    return this.rootDir + (safeSegments.length > 0 ? '/' + safeSegments.join('/') : '');
  }

  /** 打开上传目标文件；路径非法或写入准备失败时直接响应错误并返回 false。 */
  private prepareUpload(clientSocket: socket.TCPSocketConnection, state: ConnState): boolean {
    const meta: ParsedRequestMeta | null = state.meta;
    if (!meta) {
      return false;
    }
    const rawFilePath: string = meta.headers['x-file-path'] || '';
    const fullPath: string | null = this.resolveSafePath(rawFilePath);
    if (!fullPath) {
      this.failConnection(clientSocket, state, 403, 'Forbidden');
      return false;
    }
    try {
      const lastSlash: number = fullPath.lastIndexOf('/');
      if (lastSlash > 0) {
        this.ensureDirSync(fullPath.substring(0, lastSlash));
      }
      state.uploadFile = fs.openSync(fullPath,
        fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      state.uploadPath = fullPath;
      return true;
    } catch (e) {
      console.error(`[WebServer] Upload Error: ${JSON.stringify(e)}`);
      this.failConnection(clientSocket, state, 500, 'Write Failed');
      return false;
    }
  }

  private handlePostRequest(clientSocket: socket.TCPSocketConnection, meta: ParsedRequestMeta,
    state: ConnState): void {
    const requestPath: string = meta.path.split('?')[0];
    const fullPath: string | null = this.resolveSafePath(requestPath);
    if (!fullPath) {
      this.sendErrorResponse(clientSocket, 403, 'Forbidden');
      return;
    }
    try {
      if (fs.accessSync(fullPath) && !fs.statSync(fullPath).isDirectory()) {
        this.sendFile(clientSocket, fullPath);
        return;
      }
    } catch (e) {}

    let bodyString: string = '[Empty Body]';
    if (state.echoOverflow) {
      bodyString = '[Body Too Large]';
    } else if (state.echoLength > 0) {
      try {
        bodyString = this.decode(this.combineChunks(state.echoChunks, state.echoLength));
      } catch (e) {
        bodyString = '[Binary Data]';
      }
    }
    const response: EchoResponse = {
      code: 200, message: 'API Received', path: requestPath, received_data: bodyString
    };
    this.sendResponse(clientSocket, 200, 'OK', 'application/json',
      this.encoder.encodeInto(JSON.stringify(response)));
  }

  private handleGetRequest(clientSocket: socket.TCPSocketConnection, path: string): void {
    const requestPath: string = path.split('?')[0];
    const fsPath: string | null = this.resolveSafePath(requestPath);
    if (!fsPath) {
      this.sendErrorResponse(clientSocket, 403, 'Forbidden');
      return;
    }
    try {
      if (!fs.accessSync(fsPath)) {
        this.sendErrorResponse(clientSocket, 404, 'Not Found');
        return;
      }
      const stat = fs.statSync(fsPath);
      if (stat.isDirectory()) {
        const indexPath: string = fsPath + (fsPath.endsWith('/') ? '' : '/') + 'index.html';
        if (fs.accessSync(indexPath)) {
          this.sendFile(clientSocket, indexPath);
        } else {
          this.handleDirectoryListing(clientSocket, requestPath || '/', fsPath);
        }
      } else {
        this.sendFile(clientSocket, fsPath);
      }
    } catch (e) {
      this.sendErrorResponse(clientSocket, 500, 'Server Error');
    }
  }

  private escapeHtml(value: string): string {
    return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  private handleDirectoryListing(clientSocket: socket.TCPSocketConnection, urlPath: string, fsPath: string): void {
    try {
      const files: string[] = fs.listFileSync(fsPath);
      let html: string = `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Index</title>
<style>body{font-family:sans-serif;padding:20px;background:#f5f5f7}.card{background:#fff;border-radius:12px;padding:20px;box-shadow:0 4px 12px rgba(0,0,0,.05);margin-bottom:20px}a{display:flex;align-items:center;padding:12px;border-bottom:1px solid #eee;text-decoration:none;color:#333}.upload-zone{border:2px dashed #007DFF;padding:30px 20px;text-align:center;border-radius:12px;background:#f9fbff}.btn{background:#007DFF;color:white;border:none;padding:10px 20px;border-radius:8px;margin:5px}</style></head><body>
<div class="card"><h2>Index of ${this.escapeHtml(urlPath)}</h2><div class="upload-zone" id="drop-zone"><p>拖拽文件或文件夹到此处上传（单文件上限 ${this.maxTransferMb} MB）</p><input type="file" id="file-input" multiple><input type="file" id="folder-input" webkitdirectory multiple><div id="progress"></div></div></div><div class="card">`;
      if (urlPath !== '/' && urlPath !== '') {
        const parent: string = urlPath.substring(0, urlPath.lastIndexOf('/')) || '/';
        html += `<a href="${parent}">⬆️ .. (Parent)</a>`;
      }
      files.forEach((file: string) => {
        const fullPath: string = fsPath + (fsPath.endsWith('/') ? '' : '/') + file;
        let isDir: boolean = false;
        try {
          isDir = fs.statSync(fullPath).isDirectory();
        } catch (e) {}
        const href: string = (urlPath.endsWith('/') ? urlPath : urlPath + '/') + encodeURIComponent(file);
        html += `<a href="${href}">${isDir ? '📂' : '📄'} ${this.escapeHtml(file)}</a>`;
      });
      html += `</div><script>
const currentPath=location.pathname.endsWith('/')?location.pathname:location.pathname+'/';const progress=document.getElementById('progress');
async function uploadFile(file,targetPath){if(file.size>${this.maxTransferBytes}){throw new Error('文件超过 ${this.maxTransferMb} MB');}const buffer=await file.arrayBuffer();const r=await fetch('/api/upload',{method:'POST',headers:{'X-File-Path':encodeURIComponent(targetPath),'Content-Type':'application/octet-stream'},body:buffer});if(!r.ok)throw new Error(await r.text());}
async function handle(files){for(let i=0;i<files.length;i++){const f=files[i];const p=f.webkitRelativePath||f.name;progress.innerText='上传中 '+(i+1)+'/'+files.length;await uploadFile(f,currentPath+p);}location.reload();}
document.getElementById('file-input').onchange=e=>handle(Array.from(e.target.files)).catch(e=>progress.innerText=e.message);document.getElementById('folder-input').onchange=e=>handle(Array.from(e.target.files)).catch(e=>progress.innerText=e.message);
const dz=document.getElementById('drop-zone');dz.ondragover=e=>e.preventDefault();dz.ondrop=e=>{e.preventDefault();handle(Array.from(e.dataTransfer.files)).catch(e=>progress.innerText=e.message);};
</script></body></html>`;
      this.sendResponse(clientSocket, 200, 'OK', 'text/html; charset=utf-8', this.encoder.encodeInto(html));
    } catch (e) {
      this.sendErrorResponse(clientSocket, 500, 'Listing Failed');
    }
  }

  private sendFile(clientSocket: socket.TCPSocketConnection, filePath: string): void {
    this.sendFileAsync(clientSocket, filePath).catch((err: Object) => {
      console.error(`[WebServer] 发送文件异常: ${JSON.stringify(err)}`);
      try {
        clientSocket.close();
      } catch (e) {}
    });
  }

  /** 分片流式发送：峰值内存 O(64KB)，而不是把整个文件读进内存。 */
  private async sendFileAsync(clientSocket: socket.TCPSocketConnection, filePath: string): Promise<void> {
    if (!this.checkRateLimit(filePath)) {
      this.sendErrorResponse(clientSocket, 429, 'Too Many Requests (Rate Limited)');
      return;
    }
    let file: fs.File | null = null;
    let headerSent: boolean = false;
    try {
      const stat = fs.statSync(filePath);
      const total: number = stat.size;
      if (total > this.maxTransferBytes) {
        this.sendErrorResponse(clientSocket, 413, 'File Too Large');
        return;
      }
      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      const headerString: string = `HTTP/1.1 200 OK\r\nContent-Type: ${this.getMimeType(filePath)}\r\n`
        + `Content-Length: ${total}\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-store\r\n\r\n`;
      await clientSocket.send({ data: this.encoder.encodeInto(headerString).buffer as ArrayBuffer });
      headerSent = true;
      let sent: number = 0;
      while (sent < total) {
        const want: number = Math.min(SEND_CHUNK_BYTES, total - sent);
        const buffer: ArrayBuffer = new ArrayBuffer(want);
        const read: number = fs.readSync(file.fd, buffer, { length: want });
        if (read <= 0) {
          break;
        }
        await clientSocket.send({ data: read === want ? buffer : buffer.slice(0, read) });
        sent += read;
      }
      this.recordAccess(filePath);
    } catch (e) {
      console.error(`[WebServer] Read File Error: ${JSON.stringify(e)}`);
      if (!headerSent) {
        this.sendErrorResponse(clientSocket, 500, 'File Read Error');
        return;
      }
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (e) {}
      }
      try {
        clientSocket.close();
      } catch (e) {}
    }
  }

  private sendResponse(clientSocket: socket.TCPSocketConnection, code: number, statusMsg: string,
    mime: string, body: Uint8Array): void {
    try {
      const headerString: string = `HTTP/1.1 ${code} ${statusMsg}\r\nContent-Type: ${mime}\r\nContent-Length: ${body.length}\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-store\r\n\r\n`;
      const data: ArrayBuffer = body.byteLength === body.buffer.byteLength ?
        body.buffer as ArrayBuffer : body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength);
      clientSocket.send({ data: this.encoder.encodeInto(headerString).buffer as ArrayBuffer })
        .then(() => clientSocket.send({ data: data }))
        .then(() => {
          clientSocket.close().catch(() => {});
        })
        .catch(() => {
          clientSocket.close().catch(() => {});
        });
    } catch (e) {
      console.error(`[WebServer] 响应失败: ${JSON.stringify(e)}`);
      clientSocket.close().catch(() => {});
    }
  }

  private sendErrorResponse(clientSocket: socket.TCPSocketConnection, code: number, msg: string): void {
    this.sendResponse(clientSocket, code, msg, 'text/plain; charset=utf-8',
      this.encoder.encodeInto(`${code} ${msg}`));
  }

  private getMimeType(path: string): string {
    const lower: string = path.toLowerCase();
    if (lower.endsWith('.html')) return 'text/html; charset=utf-8';
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) return 'application/javascript';
    if (lower.endsWith('.css')) return 'text/css';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.txt') || lower.endsWith('.md') || lower.endsWith('.csv')) return 'text/plain; charset=utf-8';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }
}
