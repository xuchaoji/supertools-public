/**
 * WirelessHdcConnection — Pure ArkTS TLS 1.2 PSK client for HDC wireless pair
 *
 * Uses HarmonyOS cryptoFramework (sync APIs) + @kit.NetworkKit TCPSocket.
 * Suite: TLS_PSK_WITH_AES_128_GCM_SHA256 (0x00A8), RFC 4279 / 5246.
 */

import { socket } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

// ==========================================================================
// Interfaces (ArkTS strict-mode)
// ==========================================================================

interface KeyMaterial {
  clientWriteKey: Uint8Array;
  serverWriteKey: Uint8Array;
  clientWriteIv: Uint8Array;
  serverWriteIv: Uint8Array;
}

interface RawRecord {
  recType: number;
  body: Uint8Array;
}

interface DeriveKeysResult {
  keys: KeyMaterial;
  masterSecret: Uint8Array;
}

// ==========================================================================
// TLS constants
// ==========================================================================

const TLS_12_VER = new Uint8Array([0x03, 0x03]);
const SUITE = new Uint8Array([0x00, 0xA8]);
const PSK_ID = new Uint8Array([0x68, 0x64, 0x63]); // "hdc"

const REC_CCS = 20;
const REC_ALERT = 21;
const REC_HS = 22;
const REC_APP = 23;

const HS_CH = 1;
const HS_SHD = 14;
const HS_CKE = 16;
const HS_FIN = 20;

// ==========================================================================
// Utility helpers
// ==========================================================================

function s2u8(s: string): Uint8Array {
  const b = new ArrayBuffer(s.length);
  const v = new Uint8Array(b);
  for (let i = 0; i < s.length; i++) v[i] = s.charCodeAt(i) & 0xFF;
  return v;
}

function u8s(d: Uint8Array): string {
  let r = '';
  for (let i = 0; i < d.byteLength; i++) r += String.fromCharCode(d[i]);
  return r;
}

function u16b(n: number): Uint8Array {
  return new Uint8Array([(n >> 8) & 0xFF, n & 0xFF]);
}

function u24b(n: number): Uint8Array {
  return new Uint8Array([(n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF]);
}

function ucat(...arrs: Uint8Array[]): Uint8Array {
  let t = 0;
  for (let i = 0; i < arrs.length; i++) t += arrs[i].byteLength;
  const r = new Uint8Array(t);
  let o = 0;
  for (let i = 0; i < arrs.length; i++) { r.set(arrs[i], o); o += arrs[i].byteLength; }
  return r;
}

function ueq(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  for (let i = 0; i < a.byteLength; i++) if (a[i] !== b[i]) return false;
  return true;
}

// ==========================================================================
// Cryptography (all sync)
// ==========================================================================

function randomSync(len: number): Uint8Array {
  return cryptoFramework.createRandom().generateRandomSync(len).data;
}

function hmacSha256Sync(keyBytes: Uint8Array, data: Uint8Array): Uint8Array {
  const kg = cryptoFramework.createSymKeyGenerator('HMAC');
  const key = kg.convertKeySync({ data: keyBytes });
  const mac = cryptoFramework.createMac('SHA256');
  mac.initSync(key);
  mac.updateSync({ data: data });
  return mac.doFinalSync().data;
}

function sha256Sync(data: Uint8Array): Uint8Array {
  const md = cryptoFramework.createMd('SHA256');
  md.updateSync({ data: data });
  return md.digestSync().data;
}

function sha256AllSync(parts: Uint8Array[]): Uint8Array {
  const md = cryptoFramework.createMd('SHA256');
  for (let i = 0; i < parts.length; i++) md.updateSync({ data: parts[i] });
  return md.digestSync().data;
}

function pSha256Sync(secret: Uint8Array, seed: Uint8Array, len: number): Uint8Array {
  const parts: Uint8Array[] = [];
  let a = seed;
  let prod = 0;
  while (prod < len) {
    a = hmacSha256Sync(secret, a);
    const seg = hmacSha256Sync(secret, ucat(a, seed));
    parts.push(seg);
    prod += seg.byteLength;
  }
  return ucat(...parts).slice(0, len);
}

function tlsPrfSync(secret: Uint8Array, label: string, seed: Uint8Array, len: number): Uint8Array {
  return pSha256Sync(secret, ucat(s2u8(label), seed), len);
}

function aes128GcmEncSync(key: Uint8Array, nonce12: Uint8Array, aad: Uint8Array, pt: Uint8Array): Uint8Array {
  const kg = cryptoFramework.createSymKeyGenerator('AES128');
  const sk = kg.convertKeySync({ data: key });
  const cipher = cryptoFramework.createCipher('AES128|GCM|PKCS7');
  const params: cryptoFramework.GcmParamsSpec = {
    algName: 'GcmParamsSpec',
    iv: { data: nonce12 },
    aad: { data: aad },
    authTag: { data: new Uint8Array(16) }
  };
  cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, sk, params);
  const ct1 = cipher.doFinalSync({ data: pt });
  // In GCM doFinalSync, the result is ciphertext+tag (16 bytes appended).
  // But wait — the API says doFinal(null) returns ONLY the tag in GCM mode.
  // And doFinal with data returns ciphertext. Actually looking at the docs again:
  // "对于GCM和CCM模式的对称加密：一次加密流程中，如果将每一次update和doFinal的结果拼接起来，会得到'密文+authTag'"
  // So doFinal({data: pt}) returns ciphertext AND the authTag is the last 16 bytes of output.
  // Actually no: "如果doFinal的data参数传入null，则doFinal的结果就是authTag"
  // This means: update gives ciphertext portions, doFinal(null) gives authTag.
  // But if you do doFinal({data: pt}) directly (no update), then doFinal output = ciphertext + authTag(16).
  const raw = ct1.data;
  // raw = ciphertext (pt.length bytes) + authTag (16 bytes)
  // We need to return ciphertext+tag concatenated. It already is in raw.
  return raw;
}

function aes128GcmDecSync(key: Uint8Array, nonce12: Uint8Array, aad: Uint8Array, ctWithTag: Uint8Array): Uint8Array {
  const kg = cryptoFramework.createSymKeyGenerator('AES128');
  const sk = kg.convertKeySync({ data: key });
  const cipher = cryptoFramework.createCipher('AES128|GCM|PKCS7');
  const ct = ctWithTag.slice(0, ctWithTag.byteLength - 16);
  const tag = ctWithTag.slice(ctWithTag.byteLength - 16);
  const params: cryptoFramework.GcmParamsSpec = {
    algName: 'GcmParamsSpec',
    iv: { data: nonce12 },
    aad: { data: aad },
    authTag: { data: tag }
  };
  cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, sk, params);
  const result = cipher.doFinalSync({ data: ct });
  return result.data;
}

// ==========================================================================
// PSK derivation
// ==========================================================================

export function derivePskSync(code: string): Uint8Array {
  const keyBytes = s2u8('hdc pairing key');
  const codeBytes = s2u8(code);
  const result = hmacSha256Sync(keyBytes, codeBytes);
  return result.slice(0, 32);
}

// ==========================================================================
// Key schedule
// ==========================================================================

function deriveKeysSync(psk: Uint8Array, cr: Uint8Array, sr: Uint8Array): DeriveKeysResult {
  const pl = u16b(psk.byteLength);
  const premaster = ucat(pl, psk, pl, psk);
  const masterSecret = tlsPrfSync(premaster, 'master secret', ucat(cr, sr), 48);
  const keyBlock = tlsPrfSync(masterSecret, 'key expansion', ucat(sr, cr), 40);
  const keys: KeyMaterial = {
    clientWriteKey: keyBlock.slice(0, 16),
    serverWriteKey: keyBlock.slice(16, 32),
    clientWriteIv: keyBlock.slice(32, 36),
    serverWriteIv: keyBlock.slice(36, 40),
  };
  return { keys, masterSecret };
}

// ==========================================================================
// GCM record helpers
// ==========================================================================

function encRecord(keys: KeyMaterial, seq: number, recType: number, pt: Uint8Array): Uint8Array {
  const exp = bigEndian8(seq);
  const nonce = ucat(keys.clientWriteIv, exp);
  const plen = u16b(pt.byteLength);
  const aad = ucat(exp, new Uint8Array([recType]), TLS_12_VER, plen);
  // Encrypt: returns ct || tag(16)
  const ctWithTag = aes128GcmEncSync(keys.clientWriteKey, nonce, aad, pt);
  // Record on wire: recType || TLS_12_VER || (8 + len)_u16 || exp(8) || ctWithTag
  const body = ucat(exp, ctWithTag);
  const hdr = ucat(new Uint8Array([recType]), TLS_12_VER, u16b(body.byteLength));
  return ucat(hdr, body);
}

function decRecord(keys: KeyMaterial, seq: number, recType: number, body: Uint8Array): Uint8Array {
  if (body.byteLength < 24) throw new Error('body too short: ' + body.byteLength);
  const exp = body.slice(0, 8);
  const ctWithTag = body.slice(8);
  const nonce = ucat(keys.serverWriteIv, exp);
  const ct = ctWithTag.slice(0, ctWithTag.byteLength - 16);
  const plen = u16b(ct.byteLength);
  const aad = ucat(bigEndian8(seq), new Uint8Array([recType]), TLS_12_VER, plen);
  return aes128GcmDecSync(keys.serverWriteKey, nonce, aad, ctWithTag);
}

function bigEndian8(n: number): Uint8Array {
  const r = new Uint8Array(8);
  let v = n;
  for (let i = 7; i >= 0; i--) { r[i] = v & 0xFF; v = Math.floor(v / 256); }
  return r;
}

// ==========================================================================
// Plain record framing
// ==========================================================================

function makePlainRec(recType: number, body: Uint8Array): Uint8Array {
  return ucat(new Uint8Array([recType]), TLS_12_VER, u16b(body.byteLength), body);
}

// ==========================================================================
// Handshake message builders
// ==========================================================================

function buildCH(cr: Uint8Array): Uint8Array {
  const inner = ucat(
    new Uint8Array([HS_CH]),
    u24b(0),
    TLS_12_VER, cr,
    new Uint8Array([0]),      // session_id len
    u16b(2), SUITE,           // cipher suites
    new Uint8Array([1, 0]),   // compression
    u16b(0),                  // extensions
  );
  const blen = inner.byteLength - 4;
  inner[1] = (blen >> 16) & 0xFF; inner[2] = (blen >> 8) & 0xFF; inner[3] = blen & 0xFF;
  return inner;
}

function buildCKE(): Uint8Array {
  const body = ucat(u16b(PSK_ID.byteLength), PSK_ID);
  return ucat(new Uint8Array([HS_CKE]), u24b(body.byteLength), body);
}

function buildFIN(vd: Uint8Array): Uint8Array {
  return ucat(new Uint8Array([HS_FIN]), u24b(vd.byteLength), vd);
}

// ==========================================================================
// WirelessHdcConnection
// ==========================================================================

export class WirelessHdcConnection {
  private tcp: socket.TCPSocket | null = null;
  private keys: KeyMaterial | null = null;
  private ms: Uint8Array | null = null;
  private sseq: number = 0;
  private rseq: number = 0;
  private hsParts: Uint8Array[] = [];
  // Message buffer for async TCP reads
  private buf: Uint8Array[] = [];
  private pending: (() => void) | null = null;

  async connect(host: string, port: number, timeoutMs: number): Promise<void> {
    this.close();
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    this.tcp = tcp;
    tcp.on('message', (info: socket.SocketMessageInfo) => {
      this.buf.push(new Uint8Array(info.message));
      if (this.pending) { const p = this.pending; this.pending = null; p(); }
    });
    await tcp.connect({ address: { address: host, port: port, family: 1 }, timeout: timeoutMs });
  }

  async pair(psk: Uint8Array, code: string): Promise<string> {
    await this.handshake(psk);
    await this.sendApp(s2u8('host:pair:' + code + '\0'));
    const resp = await this.recvApp();
    return u8s(resp).replace(/\0+$/, '').trim();
  }

  async exec(cmd: string): Promise<string> {
    await this.sendApp(s2u8('host:' + cmd + '\0'));
    const resp = await this.recvApp();
    return u8s(resp).replace(/\0+$/, '').trim();
  }

  close(): void {
    this.keys = null; this.ms = null; this.sseq = 0; this.rseq = 0;
    this.hsParts = []; this.buf = []; this.pending = null;
    if (this.tcp) { try { this.tcp.close(); } catch (e) {} this.tcp = null; }
  }

  // --- Internal ---

  private async handshake(psk: Uint8Array): Promise<void> {
    const cr = randomSync(32);

    // 1. ClientHello
    const ch = buildCH(cr);
    this.feedHs(ch);
    await this.sendRaw(makePlainRec(REC_HS, ch));

    // 2. Read ServerHello...ServerHelloDone
    const sr = await this.readServerHelloSeries();

    // 3. Derive keys
    const result = deriveKeysSync(psk, cr, sr);
    this.keys = result.keys;
    this.ms = result.masterSecret;

    // 4. CKE
    const cke = buildCKE();
    this.feedHs(cke);
    await this.sendRaw(makePlainRec(REC_HS, cke));

    // 5. CCS
    await this.sendRaw(makePlainRec(REC_CCS, new Uint8Array([1])));
    this.sseq++;

    // 6. Finished (encrypted)
    const vdC = this.verifyDataSync('client finished');
    await this.sendEnc(REC_HS, buildFIN(vdC));

    // 7. Server CCS + Finished
    const r1 = await this.readRaw();
    if (r1.recType !== REC_CCS) throw new Error('expected CCS, got ' + r1.recType);
    this.rseq++;

    const r2 = await this.readRaw();
    if (r2.recType !== REC_HS) throw new Error('expected Finished, got ' + r2.recType);
    const plain = decRecord(this.keys!, this.rseq, REC_HS, r2.body);
    this.rseq++;
    if (plain.byteLength < 4 || plain[0] !== HS_FIN) throw new Error('expected Finished message');
    const expected = this.verifyDataSync('server finished');
    if (!ueq(plain.slice(4), expected)) throw new Error('server Finished verify_data mismatch');
  }

  private async sendApp(data: Uint8Array): Promise<void> {
    await this.sendEnc(REC_APP, data);
  }

  private async recvApp(): Promise<Uint8Array> {
    while (true) {
      const rec = await this.readRaw();
      if (rec.recType === REC_ALERT) throw new Error('TLS alert');
      const plain = decRecord(this.keys!, this.rseq, rec.recType, rec.body);
      this.rseq++;
      if (rec.recType === REC_APP || rec.recType === REC_HS) return plain;
    }
  }

  private feedHs(data: Uint8Array): void {
    this.hsParts.push(data);
  }

  private verifyDataSync(label: string): Uint8Array {
    const hash = sha256AllSync(this.hsParts);
    return tlsPrfSync(this.ms!, label, hash, 12);
  }

  private async sendRaw(data: Uint8Array): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      this.tcp!.send({ data: data.buffer }).then(() => resolve()).catch(reject);
    });
  }

  private async sendEnc(recType: number, data: Uint8Array): Promise<void> {
    const rec = encRecord(this.keys!, this.sseq, recType, data);
    this.sseq++;
    await this.sendRaw(rec);
  }

  private async readRaw(): Promise<RawRecord> {
    const hdr = await this.readExact(5);
    const recType = hdr[0];
    const len = (hdr[3] << 8) | hdr[4];
    const body = await this.readExact(len);
    const result: RawRecord = { recType, body };
    return result;
  }

  private async readExact(len: number): Promise<Uint8Array> {
    const out = new Uint8Array(len);
    let off = 0;
    while (off < len) {
      const chunk = await this.readAvail();
      const n = Math.min(chunk.byteLength, len - off);
      out.set(chunk.slice(0, n), off);
      off += n;
      if (chunk.byteLength > n) this.buf.unshift(chunk.slice(n));
    }
    return out;
  }

  private async readAvail(): Promise<Uint8Array> {
    if (this.buf.length > 0) return this.buf.shift()!;
    return new Promise<Uint8Array>(resolve => { this.pending = () => resolve(this.buf.shift()!); });
  }

  private async readServerHelloSeries(): Promise<Uint8Array> {
    let sr: Uint8Array | null = null;
    let done = false;
    while (!done) {
      const rec = await this.readRaw();
      if (rec.recType !== REC_HS) continue;
      this.feedHs(rec.body);
      let pos = 0;
      while (pos + 4 <= rec.body.byteLength) {
        const ht = rec.body[pos];
        const hl = (rec.body[pos + 1] << 16) | (rec.body[pos + 2] << 8) | rec.body[pos + 3];
        if (pos + 4 + hl > rec.body.byteLength) break;
        if (ht === 2 && sr === null) { // ServerHello
          sr = rec.body.slice(pos + 4 + 2, pos + 4 + 2 + 32);
        } else if (ht === HS_SHD) {
          done = true;
        }
        pos += 4 + hl;
      }
    }
    if (sr === null) throw new Error('no ServerHello');
    return sr;
  }
}