import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { wifiManager } from '@kit.ConnectivityKit';
import { util } from '@kit.ArkTS';

export class WebServerUtil {
  private static instance: WebServerUtil | undefined = undefined;
  private tcpServer: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
  private port: number = 8088;
  private rootDir: string = "";
  private _isRunning: boolean = false;
  private decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
  private encoder = new util.TextEncoder();

  // 频控配置存储：文件路径 -> 频控时间(毫秒)
  private rateLimits: Map<string, number> = new Map();
  // 最后访问时间存储：文件路径 -> 时间戳(毫秒)
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

  public init(baseDir: string, port: number = 8088): void {
    this.rootDir = baseDir;
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
    let limitMs = this.rateLimits.get(filePath);
    return limitMs ? (limitMs / 60000) : 0;
  }

  private checkRateLimit(filePath: string): boolean {
    if (!this.rateLimits.has(filePath)) {
      return true;
    }
    let limitMs = this.rateLimits.get(filePath) || 0;
    let lastAccess = this.lastAccessTimes.get(filePath) || 0;
    let now = new Date().getTime();

    if (now - lastAccess < limitMs) {
      return false;
    }
    return true;
  }

  private recordAccess(filePath: string): void {
    if (this.rateLimits.has(filePath)) {
      this.lastAccessTimes.set(filePath, new Date().getTime());
    }
    let parts = filePath.split('/');
    let fileName = parts[parts.length - 1];
    AppStorage.setOrCreate('RecentAccessFile', fileName);
  }

  private ensureRootExist(): void {
    try {
      if (!fs.accessSync(this.rootDir)) {
        fs.mkdirSync(this.rootDir);
      }
    } catch (e) {
      console.error(`[WebServer] Init dir failed: ${JSON.stringify(e)}`);
    }
  }

  // 递归创建文件夹工具 (API 12 适用)
  private ensureDirSync(dirPath: string): void {
    try {
      if (fs.accessSync(dirPath)) return;
    } catch (e) {}

    let parts = dirPath.split('/');
    let currentPath = '';
    for (let i = 0; i < parts.length; i++) {
      if (parts[i] === '') continue;
      currentPath += '/' + parts[i];
      try {
        if (!fs.accessSync(currentPath)) {
          fs.mkdirSync(currentPath);
        }
      } catch (e) {}
    }
  }

  public getIpAddress(): string {
    try {
      let ipInfo = wifiManager.getIpInfo();
      let ip = ipInfo.ipAddress;
      return (ip >>> 24) + '.' + (ip >> 16 & 0xFF) + '.' + (ip >> 8 & 0xFF) + '.' + (ip & 0xFF);
    } catch (e) {
      return "127.0.0.1";
    }
  }

  public start(): Promise<string> {
    return new Promise((resolve, reject) => {
      if (this._isRunning) {
        resolve("Server already running");
        return;
      }

      let localAddress: socket.NetAddress = {
        address: '0.0.0.0',
        port: this.port,
        family: 1
      };

      this.tcpServer.listen(localAddress, (err: BusinessError) => {
        if (err) {
          reject(err);
          return;
        }
        this._isRunning = true;
        console.info(`[WebServer] Server Started on port ${this.port}`);

        this.tcpServer.on('connect', (clientSocket: socket.TCPSocketConnection) => {
          let receivedBuffer = new Uint8Array(0);

          clientSocket.on('message', (value: socket.SocketMessageInfo) => {
            let newData = new Uint8Array(value.message);
            let temp = new Uint8Array(receivedBuffer.length + newData.length);
            temp.set(receivedBuffer);
            temp.set(newData, receivedBuffer.length);
            receivedBuffer = temp;

            this.tryProcessRequest(clientSocket, receivedBuffer, (consumedLength: number) => {
              receivedBuffer = receivedBuffer.slice(consumedLength);
            });
          });
        });
        resolve("Success");
      });
    });
  }

  public stop(): void {
    if (this._isRunning) {
      try {
        this.tcpServer.off('connect');
        this.tcpServer.close();
      } catch (e) {}
      this._isRunning = false;
    }
  }

  private tryProcessRequest(clientSocket: socket.TCPSocketConnection, data: Uint8Array, onProcessed: (len: number) => void): void {
    const peekSize = Math.min(data.length, 4096);
    const peekData = data.slice(0, peekSize);
    const requestText = this.decoder.decodeWithStream(peekData);

    const headerEndIndex = requestText.indexOf('\r\n\r\n');
    if (headerEndIndex === -1) return;

    const headerPart = requestText.substring(0, headerEndIndex);
    const lines = headerPart.split('\r\n');
    const firstLine = lines[0].split(' ');

    if (firstLine.length < 2) return;

    const method = firstLine[0].toUpperCase();
    const path = firstLine[1];

    // 新增：提取所有 Headers 供后续读取自定义标头
    let headers: Record<string, string> = {};
    let contentLength = 0;

    for (let i = 1; i < lines.length; i++) {
      let line = lines[i].trim();
      if (!line) continue;
      let colonIdx = line.indexOf(':');
      if (colonIdx > 0) {
        let key = line.substring(0, colonIdx).trim().toLowerCase();
        let val = line.substring(colonIdx + 1).trim();
        headers[key] = val;
        if (key === 'content-length') {
          contentLength = parseInt(val, 10);
        }
      }
    }

    const headerBinaryLength = this.encoder.encodeInto(headerPart + '\r\n\r\n').length;
    const totalExpectedLength = headerBinaryLength + contentLength;

    // 分块传输时，等待接收完整
    if (data.length < totalExpectedLength) return;

    const bodyData = data.slice(headerBinaryLength, totalExpectedLength);

    if (method === 'POST') {
      this.handlePostRequest(clientSocket, path, headers, bodyData);
    } else if (method === 'GET') {
      this.handleGetRequest(clientSocket, path);
    } else {
      this.sendErrorResponse(clientSocket, 405, 'Method Not Allowed');
    }

    onProcessed(totalExpectedLength);
  }

  private handlePostRequest(clientSocket: socket.TCPSocketConnection, path: string, headers: Record<string, string>, body: Uint8Array): void {
    let requestPath = "";
    try {
      requestPath = decodeURIComponent(path.split('?')[0]);
    } catch (e) {
      requestPath = path.split('?')[0];
    }

    // --- 新增：处理 /api/upload 批量上传请求 ---
    if (requestPath === '/api/upload') {
      let reqPath = headers['x-file-path'];
      if (reqPath) {
        try {
          reqPath = decodeURIComponent(reqPath);
          if (reqPath.includes('..')) {
            this.sendErrorResponse(clientSocket, 403, 'Forbidden');
            return;
          }
          let fullPath = this.rootDir + (reqPath.startsWith('/') ? reqPath : '/' + reqPath);
          let lastSlash = fullPath.lastIndexOf('/');
          let dirPath = fullPath.substring(0, lastSlash);

          // 确保目标文件的所在目录树已建立
          this.ensureDirSync(dirPath);

          let file = fs.openSync(fullPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          // 安全地从 body 提取对应的 buffer 并写入
          let buf = body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength);
          fs.writeSync(file.fd, buf);
          fs.closeSync(file);

          this.sendResponse(clientSocket, 200, "OK", "application/json", this.encoder.encodeInto('{"code":200,"msg":"Success"}'));
          return;
        } catch (e) {
          console.error(`[WebServer] Upload Error: ${e}`);
          this.sendErrorResponse(clientSocket, 500, 'Write Failed');
          return;
        }
      }
    }
    // ------------------------------------

    let fsPath = this.rootDir + (requestPath.startsWith('/') ? requestPath : '/' + requestPath);
    let isFile = false;

    try {
      if (fs.accessSync(fsPath)) {
        let stat = fs.statSync(fsPath);
        if (!stat.isDirectory()) {
          isFile = true;
        }
      }
    } catch (e) {}

    if (isFile) {
      this.sendFile(clientSocket, fsPath);
    } else {
      let bodyStr = "";
      if (body.length > 0) {
        try {
          bodyStr = this.decoder.decodeWithStream(body);
        } catch (e) {
          bodyStr = "[Binary Data]";
        }
      } else {
        bodyStr = "[Empty Body]";
      }

      const response: Record<string, string | number> = {
        "code": 200,
        "message": "API Received",
        "path": path,
        "received_data": bodyStr
      };

      const responseData = this.encoder.encodeInto(JSON.stringify(response));
      this.sendResponse(clientSocket, 200, "OK", "application/json", responseData);
    }
  }

  private handleGetRequest(clientSocket: socket.TCPSocketConnection, path: string): void {
    if (path.includes('..')) {
      this.sendErrorResponse(clientSocket, 403, 'Forbidden');
      return;
    }

    let requestPath = decodeURIComponent(path.split('?')[0]);
    let fsPath = this.rootDir + (requestPath.startsWith('/') ? requestPath : '/' + requestPath);

    try {
      if (fs.accessSync(fsPath)) {
        let stat = fs.statSync(fsPath);
        if (stat.isDirectory()) {
          let indexPath = fsPath + (fsPath.endsWith('/') ? '' : '/') + 'index.html';
          if (fs.accessSync(indexPath)) {
            this.sendFile(clientSocket, indexPath);
          } else {
            this.handleDirectoryListing(clientSocket, requestPath, fsPath);
          }
        } else {
          this.sendFile(clientSocket, fsPath);
        }
      } else {
        this.sendErrorResponse(clientSocket, 404, 'Not Found');
      }
    } catch (e) {
      this.sendErrorResponse(clientSocket, 500, 'Server Error');
    }
  }

  private handleDirectoryListing(clientSocket: socket.TCPSocketConnection, urlPath: string, fsPath: string): void {
    try {
      let files = fs.listFileSync(fsPath);
      // 将前端 HTML 增加了拖拽上传区和 JS 处理逻辑
      let html = `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Index</title>
<style>
  body{font-family:sans-serif;padding:20px;background:#f5f5f7}
  .card{background:#fff;border-radius:12px;padding:20px;box-shadow:0 4px 12px rgba(0,0,0,0.05);margin-bottom:20px}
  a{display:flex;align-items:center;padding:12px;border-bottom:1px solid #eee;text-decoration:none;color:#333;transition:background 0.2s}
  a:hover{background:#f0f8ff}
  .icon{margin-right:10px;font-size:20px}
  .upload-zone{border:2px dashed #007DFF;padding:30px 20px;text-align:center;border-radius:12px;background:#f9fbff;cursor:pointer;transition:all 0.3s}
  .upload-zone.dragover{background:#e0f0ff;border-color:#005bb5;transform:scale(1.01)}
  .btn{background:#007DFF;color:white;border:none;padding:10px 20px;border-radius:8px;cursor:pointer;margin:5px;font-size:14px;transition:opacity 0.2s}
  .btn:hover{opacity:0.8}
  #progress{margin-top:15px;font-size:14px;color:#007DFF;font-weight:bold}
</style>
</head><body>
<div class="card">
  <h2>Index of ${urlPath}</h2>
  <div class="upload-zone" id="drop-zone">
    <div style="font-size:32px;margin-bottom:10px">☁️</div>
    <p style="color:#666;margin-bottom:15px">拖拽文件或整个文件夹到此处上传</p>
    <input type="file" id="file-input" multiple style="display:none">
    <input type="file" id="folder-input" webkitdirectory multiple style="display:none">
    <button class="btn" onclick="document.getElementById('file-input').click()">选择多文件</button>
    <button class="btn" onclick="document.getElementById('folder-input').click()">选择文件夹</button>
    <div id="progress"></div>
  </div>
</div>
<div class="card" style="padding:0">`;

      if (urlPath !== '/' && urlPath !== '') {
        let parent = urlPath.substring(0, urlPath.lastIndexOf('/')) || '/';
        html += `<a href="${parent}"><span class="icon">⬆️</span>.. (Parent)</a>`;
      }

      files.forEach(file => {
        let fullPath = fsPath + (fsPath.endsWith('/') ? '' : '/') + file;
        let isDir = false;
        try { isDir = fs.statSync(fullPath).isDirectory(); } catch (e) {}

        let icon = isDir ? "📂" : "📄";
        let href = (urlPath.endsWith('/') ? urlPath : urlPath + '/') + encodeURIComponent(file);
        html += `<a href="${href}"><span class="icon">${icon}</span>${file}</a>`;
      });

      html += `</div>
<script>
  const currentPath = window.location.pathname.endsWith('/') ? window.location.pathname : window.location.pathname + '/';
  const dropZone = document.getElementById('drop-zone');
  const progressDiv = document.getElementById('progress');

  ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(e => dropZone.addEventListener(e, prev, false));
  function prev(e) { e.preventDefault(); e.stopPropagation(); }

  ['dragenter', 'dragover'].forEach(e => dropZone.addEventListener(e, () => dropZone.classList.add('dragover'), false));
  ['dragleave', 'drop'].forEach(e => dropZone.addEventListener(e, () => dropZone.classList.remove('dragover'), false));

  dropZone.addEventListener('drop', async (e) => {
    const items = e.dataTransfer.items;
    const files = [];
    if (items) {
      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (item.kind === 'file') {
          const entry = item.webkitGetAsEntry();
          if (entry) await traverse(entry, '', files);
        }
      }
    }
    if(files.length) handleFiles(files);
  }, false);

  document.getElementById('file-input').addEventListener('change', function() { handleFiles(Array.from(this.files)); });
  document.getElementById('folder-input').addEventListener('change', function() { handleFiles(Array.from(this.files)); });

  // 递归解析文件夹结构
  async function traverse(item, path, files) {
    if (item.isFile) {
      const file = await new Promise(r => item.file(r));
      file.customPath = path + file.name;
      files.push(file);
    } else if (item.isDirectory) {
      const dirReader = item.createReader();
      const entries = await new Promise(r => dirReader.readEntries(r));
      for (let i = 0; i < entries.length; i++) {
        await traverse(entries[i], path + item.name + "/", files);
      }
    }
  }

  // 队列调度上传
  async function handleFiles(files) {
    if(files.length === 0) return;
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const relPath = file.webkitRelativePath || file.customPath || file.name;
      const targetPath = currentPath + relPath;
      progressDiv.innerText = '上传中 (' + (i+1) + '/' + files.length + '): ' + file.name;
      await uploadFile(file, targetPath);
    }
    progressDiv.innerText = '✅ 上传完成，正在刷新...';
    setTimeout(() => location.reload(), 800);
  }

  // 二进制直传
  async function uploadFile(file, targetPath) {
    const buffer = await file.arrayBuffer();
    await fetch('/api/upload', {
      method: 'POST',
      headers: {
        'X-File-Path': encodeURIComponent(targetPath),
        'Content-Type': 'application/octet-stream'
      },
      body: buffer
    });
  }
</script>
</body></html>`;

      this.sendResponse(clientSocket, 200, "OK", "text/html; charset=utf-8", this.encoder.encodeInto(html));
    } catch (e) {
      this.sendErrorResponse(clientSocket, 500, 'Listing Failed');
    }
  }

  private sendFile(clientSocket: socket.TCPSocketConnection, filePath: string): void {
    if (!this.checkRateLimit(filePath)) {
      this.sendErrorResponse(clientSocket, 429, 'Too Many Requests (Rate Limited)');
      return;
    }

    try {
      let file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(filePath);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);

      this.sendResponse(clientSocket, 200, "OK", this.getMimeType(filePath), new Uint8Array(buf));
      this.recordAccess(filePath);
    } catch (e) {
      console.error(`[WebServer] Read File Error: ${e}`);
      this.sendErrorResponse(clientSocket, 500, 'File Read Error');
    }
  }

  private sendResponse(clientSocket: socket.TCPSocketConnection, code: number, statusMsg: string, mime: string, body: Uint8Array): void {
    try {
      let headerStr = `HTTP/1.1 ${code} ${statusMsg}\r\nContent-Type: ${mime}\r\nContent-Length: ${body.length}\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n`;
      let headerData = this.encoder.encodeInto(headerStr);
      let responsePacket = new Uint8Array(headerData.length + body.length);
      responsePacket.set(headerData, 0);
      responsePacket.set(body, headerData.length);

      clientSocket.send({ data: responsePacket.buffer }).then(() => {
        clientSocket.close().catch(() => {});
      }).catch((e: Error) => {
        clientSocket.close().catch(() => {});
      });
    } catch (e) {
      clientSocket.close().catch(() => {});
    }
  }

  private sendErrorResponse(clientSocket: socket.TCPSocketConnection, code: number, msg: string): void {
    this.sendResponse(clientSocket, code, msg, "text/plain", this.encoder.encodeInto(`${code} ${msg}`));
  }

  private getMimeType(path: string): string {
    let lower = path.toLowerCase();
    if (lower.endsWith('.html')) return 'text/html';
    if (lower.endsWith('.js')) return 'application/javascript';
    if (lower.endsWith('.css')) return 'text/css';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}