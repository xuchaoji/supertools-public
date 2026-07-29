use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;
use aes_gcm::{Aead, Aes128Gcm, KeyInit, Nonce};
use hmac::{Hmac, Mac};
use rand::RngCore;
use sha2::{Digest, Sha256};
use zeroize::Zeroize;

type HmacSha256 = Hmac<Sha256>;

// =====================================================================
// HDC Pairing Protocol Constants
// =====================================================================
const TLS_VERSION: [u8; 2] = [0x03, 0x03]; // TLS 1.2
const SUITE_TLS_PSK_AES128_GCM_SHA256: [u8; 2] = [0x00, 0xA8];

// Record types
const REC_CHANGE_CIPHER_SPEC: u8 = 20;
const REC_ALERT: u8 = 21;
const REC_HANDSHAKE: u8 = 22;
const REC_APPLICATION_DATA: u8 = 23;

// Handshake types
const HS_CLIENT_HELLO: u8 = 1;
const HS_SERVER_HELLO_DONE: u8 = 14;
const HS_CLIENT_KEY_EXCHANGE: u8 = 16;
const HS_FINISHED: u8 = 20;

// PSK identity for HDC
const PSK_IDENTITY: &[u8] = b"hdc";

// =====================================================================
// PSK derivation: HMAC-SHA256(\"hdc pairing key\", code)[..32]
// =====================================================================
pub fn derive_psk(code: &str) -> [u8; 32] {
    let mut mac = HmacSha256::new_from_slice(b"hdc pairing key").unwrap();
    mac.update(code.as_bytes());
    let r = mac.finalize().into_bytes();
    let mut psk = [0u8; 32];
    psk.copy_from_slice(&r[..32]);
    psk
}

// =====================================================================
// PRF P_SHA256 (RFC 5246 §5)
// =====================================================================
fn p_sha256(secret: &[u8], seed: &[u8], len: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(len);
    let mut a = seed.to_vec();
    while out.len() < len {
        let mut m1 = HmacSha256::new_from_slice(secret).unwrap();
        m1.update(&a);
        a = m1.finalize().into_bytes().to_vec();

        let mut m2 = HmacSha256::new_from_slice(secret).unwrap();
        m2.update(&a);
        m2.update(seed);
        out.extend_from_slice(&m2.finalize().into_bytes());
    }
    out.truncate(len);
    out
}

fn tls_prf(secret: &[u8], label: &str, seed: &[u8], len: usize) -> Vec<u8> {
    let mut s = label.as_bytes().to_vec();
    s.extend_from_slice(seed);
    p_sha256(secret, &s, len)
}

// =====================================================================
// Key schedule: premaster → master_secret → key material
// =====================================================================
struct KeyMaterial {
    client_write_key: [u8; 16],
    server_write_key: [u8; 16],
    client_write_iv: [u8; 4],
    server_write_iv: [u8; 4],
}

impl Drop for KeyMaterial {
    fn drop(&mut self) {
        self.client_write_key.zeroize();
        self.server_write_key.zeroize();
        self.client_write_iv.zeroize();
        self.server_write_iv.zeroize();
    }
}

fn derive_keys(psk: &[u8; 32], client_random: &[u8; 32], server_random: &[u8; 32]) -> (KeyMaterial, [u8; 48]) {
    // premaster_secret = u16_be(psk_len) || psk || u16_be(psk_len) || psk  (RFC 4279 §2)
    let pl = 32u16.to_be_bytes();
    let mut premaster = Vec::with_capacity(68);
    premaster.extend_from_slice(&pl);
    premaster.extend_from_slice(psk);
    premaster.extend_from_slice(&pl);
    premaster.extend_from_slice(psk);

    let mut seed = Vec::with_capacity(64);
    seed.extend_from_slice(client_random);
    seed.extend_from_slice(server_random);
    let master_secret: [u8; 48] = tls_prf(&premaster, "master secret", &seed, 48)
        .try_into()
        .unwrap();

    let mut seed2 = Vec::with_capacity(64);
    seed2.extend_from_slice(server_random);
    seed2.extend_from_slice(client_random);
    let kb = tls_prf(&master_secret, "key expansion", &seed2, 40);

    let keys = KeyMaterial {
        client_write_key: kb[0..16].try_into().unwrap(),
        server_write_key: kb[16..32].try_into().unwrap(),
        client_write_iv: kb[32..36].try_into().unwrap(),
        server_write_iv: kb[36..40].try_into().unwrap(),
    };

    (keys, master_secret)
}

// =====================================================================
// Encrypt / decrypt helpers
// =====================================================================
fn encrypt_record(key: &[u8; 16], iv_prefix: &[u8; 4], seq: u64, content_type: u8, plain: &[u8]) -> Vec<u8> {
    let cipher = Aes128Gcm::new_from_slice(key).unwrap();

    // Explicit nonce = seq_num (8 bytes big-endian)
    let exp_nonce = seq.to_be_bytes();

    // Nonce = iv_prefix(4) || explicit_nonce(8) = 12 bytes
    let mut nonce = [0u8; 12];
    nonce[..4].copy_from_slice(iv_prefix);
    nonce[4..].copy_from_slice(&exp_nonce);

    // AAD = seq_num(8) || content_type(1) || version(2) || plaintext_len(2)
    let plen = (plain.len() as u16).to_be_bytes();
    let mut aad = Vec::with_capacity(13);
    aad.extend_from_slice(&exp_nonce);
    aad.push(content_type);
    aad.extend_from_slice(&TLS_VERSION);
    aad.extend_from_slice(&plen);

    let ciphertext = cipher
        .encrypt(Nonce::from_slice(&nonce), plain)
        .unwrap(); // ciphertext || tag(16)

    // Record: explicit_nonce(8) || ciphertext_with_tag
    let mut rec = Vec::with_capacity(8 + ciphertext.len());
    rec.extend_from_slice(&exp_nonce);
    rec.extend_from_slice(&ciphertext);
    rec
}

fn decrypt_record(key: &[u8; 16], iv_prefix: &[u8; 4], seq: u64, content_type: u8, body: &[u8]) -> Result<Vec<u8>, String> {
    if body.len() < 24 {
        // Need at least: explicit_nonce(8) + empty_plaintext(0) + tag(16)
        return Err("record body too short for GCM".into());
    }

    let cipher = Aes128Gcm::new_from_slice(key).unwrap();

    let exp_nonce = &body[..8]; // same as seq_num
    let ct_with_tag = &body[8..];

    let mut nonce = [0u8; 12];
    nonce[..4].copy_from_slice(iv_prefix);
    nonce[4..].copy_from_slice(exp_nonce);

    // plaintext_len = body_len - 8 (nonce) - 16 (tag)
    let plaintext_len = body.len() - 24;
    let plen = (plaintext_len as u16).to_be_bytes();

    let mut aad = Vec::with_capacity(13);
    aad.extend_from_slice(&seq.to_be_bytes());
    aad.push(content_type);
    aad.extend_from_slice(&TLS_VERSION);
    aad.extend_from_slice(&plen);

    cipher
        .decrypt(Nonce::from_slice(&nonce), ct_with_tag)
        .map_err(|e| format!("GCM decrypt failed: {:?}", e))
}

// =====================================================================
// TLS 1.2 PSK Client
// =====================================================================
pub struct TlsPskConnection {
    stream: TcpStream,
    // Crypto state (set after handshake)
    keys: Option<KeyMaterial>,
    master_secret: Option<[u8; 48]>,
    // Sequence counters
    send_seq: u64,
    recv_seq: u64,
    // Hash of all handshake messages seen so far
    hs_hash: Sha256,
}

impl TlsPskConnection {
    pub fn connect(addr: &str, timeout: Duration) -> Result<Self, String> {
        let stream = TcpStream::connect_timeout(
            &addr.parse().map_err(|e| format!("parse addr: {}", e))?,
            timeout,
        )
        .map_err(|e| format!("TCP connect {}: {}", addr, e))?;
        stream
            .set_read_timeout(Some(timeout))
            .map_err(|e| format!("set timeout: {}", e))?;
        Ok(TlsPskConnection {
            stream,
            keys: None,
            master_secret: None,
            send_seq: 0,
            recv_seq: 0,
            hs_hash: Sha256::new(),
        })
    }

    /// Perform full TLS 1.2 PSK handshake using the given PSK.
    /// After this returns Ok, the connection is encrypted and ready for application data.
    pub fn handshake(&mut self, psk: &[u8; 32]) -> Result<(), String> {
        // 1. Generate client_random
        let mut client_random = [0u8; 32];
        rand::rngs::OsRng.fill_bytes(&mut client_random);

        // 2. Build and send ClientHello
        let ch = self.build_client_hello(&client_random);
        self.send_record(REC_HANDSHAKE, &ch, false)?;
        self.hs_hash.update(&ch);

        // 3. Read ServerHello .. ServerHelloDone, extract server_random
        let server_random = self.read_server_hello_series()?;

        // 4. Derive keys
        let (keys, master_secret) = derive_keys(psk, &client_random, &server_random);
        self.keys = Some(keys);
        self.master_secret = Some(master_secret);

        // 5. Send ClientKeyExchange (PSK identity)
        let cke = self.build_client_key_exchange();
        self.send_record(REC_HANDSHAKE, &cke, false)?;
        self.hs_hash.update(&cke);

        // 6. Send ChangeCipherSpec
        self.send_raw(&[REC_CHANGE_CIPHER_SPEC, 0x03, 0x03, 0x00, 0x01, 0x01])?;
        self.send_seq += 1; // CCS counts but isn't encrypted

        // 7. Send Finished (now encrypted)
        let client_finished = self.build_finished("client finished");
        self.send_record(REC_HANDSHAKE, &client_finished, true)?;

        // 8. Receive server ChangeCipherSpec + Finished
        let (ct, body) = self.read_raw_record()?;
        if ct != REC_CHANGE_CIPHER_SPEC || body != [1] {
            return Err(format!("expected server CCS, got type={}", ct));
        }
        self.recv_seq += 1;

        let (ct, body) = self.read_raw_record()?;
        if ct != REC_HANDSHAKE {
            return Err(format!("expected server Finished, got type={}", ct));
        }
        let plain = self.decrypt_body(ct, &body)?;
        self.recv_seq += 1;

        if plain.len() < 4 || plain[0] != HS_FINISHED {
            return Err("expected Finished handshake message".into());
        }
        // Verify server Finished (12 bytes verify_data)
        let expected = self.verify_data("server finished");
        let actual = &plain[4..]; // skip type(1) + length(3)
        if actual.len() != 12 || actual != &expected[..] {
            return Err("server Finished verify_data mismatch".into());
        }

        Ok(())
    }

    /// Send application data over the encrypted channel
    pub fn send_appdata(&mut self, data: &[u8]) -> Result<(), String> {
        self.send_record(REC_APPLICATION_DATA, data, true)
    }

    /// Receive application data over the encrypted channel
    pub fn recv_appdata(&mut self) -> Result<Vec<u8>, String> {
        loop {
            let (ct, body) = self.read_raw_record()?;
            match ct {
                REC_ALERT => {
                    let desc = if body.len() >= 2 { body[1] } else { 0 };
                    return Err(format!("TLS alert: level={}, desc={}", body.first().unwrap_or(&0), desc));
                }
                REC_APPLICATION_DATA | REC_HANDSHAKE => {
                    let plain = self.decrypt_body(ct, &body)?;
                    self.recv_seq += 1;
                    return Ok(plain);
                }
                _ => continue, // skip other record types
            }
        }
    }

    // =====================================================================
    // Internal: record I/O
    // =====================================================================

    /// Read a raw TLS record: (content_type, body_bytes)
    fn read_raw_record(&mut self) -> Result<(u8, Vec<u8>), String> {
        let mut hdr = [0u8; 5];
        self.stream
            .read_exact(&mut hdr)
            .map_err(|e| format!("read record hdr: {}", e))?;
        let ct = hdr[0];
        let len = u16::from_be_bytes([hdr[3], hdr[4]]) as usize;
        let mut body = vec![0u8; len];
        self.stream
            .read_exact(&mut body)
            .map_err(|e| format!("read record body ({} bytes): {}", len, e))?;
        Ok((ct, body))
    }

    /// Send a raw byte sequence (used for CCS which is never encrypted)
    fn send_raw(&mut self, data: &[u8]) -> Result<(), String> {
        self.stream
            .write_all(data)
            .map_err(|e| format!("send_raw: {}", e))
    }

    /// Send a TLS record. If encrypted, uses client_write_key.
    fn send_record(&mut self, content_type: u8, data: &[u8], encrypted: bool) -> Result<(), String> {
        let body = if encrypted {
            let keys = self.keys.as_ref().ok_or("keys not set")?;
            encrypt_record(&keys.client_write_key, &keys.client_write_iv, self.send_seq, content_type, data)
        } else {
            data.to_vec()
        };

        let total_len = if encrypted { 8 + body.len() } else { body.len() };

        let mut rec = Vec::with_capacity(5 + total_len);
        rec.push(content_type);
        rec.extend_from_slice(&TLS_VERSION);
        rec.extend_from_slice(&(total_len as u16).to_be_bytes());
        rec.extend_from_slice(&body);

        self.stream.write_all(&rec).map_err(|e| format!("send: {}", e))?;
        self.send_seq += 1;
        Ok(())
    }

    /// Decrypt a record body using server keys
    fn decrypt_body(&self, content_type: u8, body: &[u8]) -> Result<Vec<u8>, String> {
        let keys = self.keys.as_ref().ok_or("keys not set")?;
        decrypt_record(&keys.server_write_key, &keys.server_write_iv, self.recv_seq, content_type, body)
    }

    // =====================================================================
    // Internal: handshake message builders
    // =====================================================================

    fn build_client_hello(&self, client_random: &[u8; 32]) -> Vec<u8> {
        let mut body = Vec::new();
        body.push(HS_CLIENT_HELLO);
        // placeholder for 3-byte length
        body.extend_from_slice(&[0, 0, 0]);
        body.extend_from_slice(&TLS_VERSION);
        body.extend_from_slice(client_random);
        // Session ID: empty
        body.push(0);
        // Cipher suites: 1 suite
        body.extend_from_slice(&2u16.to_be_bytes());
        body.extend_from_slice(&SUITE_TLS_PSK_AES128_GCM_SHA256);
        // Compression: null
        body.push(1);
        body.push(0);
        // Extensions: none
        body.extend_from_slice(&0u16.to_be_bytes());

        // Fix the 3-byte length
        let body_len = (body.len() - 4) as u32;
        body[1..4].copy_from_slice(&body_len.to_be_bytes()[1..]);
        body
    }

    /// Read ServerHello .. ServerHelloDone series, returns server_random
    fn read_server_hello_series(&mut self) -> Result<[u8; 32], String> {
        let mut server_random = [0u8; 32];
        let mut seen_shd = false;

        while !seen_shd {
            let (ct, body) = self.read_raw_record()?;
            if ct != REC_HANDSHAKE {
                continue;
            }
            self.hs_hash.update(&body);

            let mut pos = 0;
            while pos + 4 <= body.len() {
                let ht = body[pos];
                let hl = u32::from_be_bytes([0, body[pos + 1], body[pos + 2], body[pos + 3]]) as usize;
                if pos + 4 + hl > body.len() {
                    break;
                }

                if ht == 2 {
                    // ServerHello: version(2) + random(32) + session_id_len(1) + session_id + suite(2) + compression(1) + ext...
                    server_random.copy_from_slice(&body[pos + 4 + 2..pos + 4 + 2 + 32]);
                } else if ht == HS_SERVER_HELLO_DONE {
                    seen_shd = true;
                }
                pos += 4 + hl;
            }
        }

        if !seen_shd {
            return Err("did not receive ServerHelloDone".into());
        }
        Ok(server_random)
    }

    fn build_client_key_exchange(&self) -> Vec<u8> {
        // CKE body: PSK identity length(2) + identity
        let mut cke_body = Vec::with_capacity(2 + PSK_IDENTITY.len());
        cke_body.extend_from_slice(&(PSK_IDENTITY.len() as u16).to_be_bytes());
        cke_body.extend_from_slice(PSK_IDENTITY);

        let mut hs = Vec::with_capacity(4 + cke_body.len());
        hs.push(HS_CLIENT_KEY_EXCHANGE);
        hs.extend_from_slice(&(cke_body.len() as u32).to_be_bytes()[1..]);
        hs.extend_from_slice(&cke_body);
        hs
    }

    fn build_finished(&self, label: &str) -> Vec<u8> {
        let vd = self.verify_data(label);
        let mut hs = Vec::with_capacity(4 + vd.len());
        hs.push(HS_FINISHED);
        hs.extend_from_slice(&(vd.len() as u32).to_be_bytes()[1..]);
        hs.extend_from_slice(&vd);
        hs
    }

    fn verify_data(&self, label: &str) -> Vec<u8> {
        let ms = self.master_secret.as_ref().unwrap();
        let hash = self.hs_hash.clone().finalize();
        tls_prf(ms, label, &hash, 12)
    }

    // =====================================================================
    // High-level HDC operations
    // =====================================================================

    /// Do HDC pairing: TLS handshake + send host:pair command
    pub fn pair(&mut self, psk: &[u8; 32], code: &str) -> Result<String, String> {
        self.handshake(psk)?;

        let cmd = format!("host:pair:{}\0", code);
        self.send_appdata(cmd.as_bytes())?;

        let resp = self.recv_appdata()?;
        Ok(String::from_utf8_lossy(&resp).trim_end_matches('\0').to_string())
    }

    /// Execute shell command over established TLS channel
    pub fn exec(&mut self, command: &str) -> Result<String, String> {
        let cmd = format!("host:{}\0", command);
        self.send_appdata(cmd.as_bytes())?;

        let resp = self.recv_appdata()?;
        Ok(String::from_utf8_lossy(&resp).trim_end_matches('\0').to_string())
    }

    /// Check connection status
    pub fn check_connection(&mut self) -> Result<String, String> {
        self.send_appdata(b"host:list targets -v\0")?;
        let resp = self.recv_appdata()?;
        Ok(String::from_utf8_lossy(&resp).trim_end_matches('\0').to_string())
    }
}

// =====================================================================
// Tests
// =====================================================================
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_psk_derivation() {
        let psk1 = derive_psk("123456");
        let psk2 = derive_psk("123456");
        assert_eq!(psk1, psk2); // deterministic
        let psk3 = derive_psk("654321");
        assert_ne!(psk1, psk3); // different codes
    }
}
