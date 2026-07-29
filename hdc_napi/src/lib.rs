use napi::bindgen_prelude::*;
use napi_derive::napi;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;

#[napi(object)]
pub struct HdcStatus {
    pub connected: bool,
    pub device_count: Option<u32>,
    pub error: Option<String>,
}

#[napi(object)]
pub struct HdcOutput {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

const BANNER: &[u8; 12] = b"OHOS HDC\0\0\0\0";
const HANDSHAKE_SIZE: usize = 108; // 12 + 32 + 64
const CMD_LIST_TARGETS: u16 = 5;
const CMD_SHELL_INIT: u16 = 2000;
const CMD_SHELL_DATA: u16 = 2001;
const CMD_CHECK_SERVER: u16 = 13;

fn connect_to(host: Option<String>, port: Option<u16>, timeout_secs: u64) -> std::io::Result<TcpStream> {
    let h = host.unwrap_or_else(|| "127.0.0.1".to_string());
    let p = port.unwrap_or(8710);
    TcpStream::connect_timeout(
        &format!("{}:{}", h, p).parse().unwrap(),
        Duration::from_secs(timeout_secs),
    )
}

/// Read exactly n bytes from stream
fn read_exact(stream: &mut TcpStream, buf: &mut [u8]) -> std::io::Result<()> {
    let mut total = 0usize;
    while total < buf.len() {
        let n = stream.read(&mut buf[total..])?;
        if n == 0 {
            return Err(std::io::Error::new(std::io::ErrorKind::UnexpectedEof, "connection closed"));
        }
        total += n;
    }
    Ok(())
}

/// Build a HDC packet: [u32 BE: total_len] [u16 LE: cmd] [payload]
fn build_packet(cmd: u16, payload: &[u8]) -> Vec<u8> {
    // total_len includes the 4-byte length field itself + 2-byte cmd + payload
    let total_len: u32 = 4 + 2 + payload.len() as u32;
    let mut pkt = Vec::with_capacity(total_len as usize);
    pkt.extend_from_slice(&total_len.to_be_bytes());
    pkt.extend_from_slice(&cmd.to_le_bytes());
    pkt.extend_from_slice(payload);
    pkt
}

/// Read a HDC response packet, return payload (after cmd)
fn read_response(stream: &mut TcpStream) -> std::io::Result<Vec<u8>> {
    let mut len_buf = [0u8; 4];
    read_exact(stream, &mut len_buf)?;
    let total_len = u32::from_be_bytes(len_buf) as usize;
    if total_len < 6 {
        return Ok(Vec::new());
    }
    let data_len = total_len - 4; // minus the length field itself
    let mut data = vec![0u8; data_len];
    read_exact(stream, &mut data)?;
    // data[0..2] is cmd LE, data[2..] is payload
    if data.len() >= 2 {
        Ok(data[2..].to_vec())
    } else {
        Ok(Vec::new())
    }
}

/// Do the ChannelHandShake: read server handshake, send client handshake
fn do_handshake(stream: &mut TcpStream) -> std::io::Result<()> {
    stream.set_read_timeout(Some(Duration::from_secs(5)))?;
    stream.set_write_timeout(Some(Duration::from_secs(5)))?;

    // Read server handshake (108 bytes)
    let mut server_hs = [0u8; HANDSHAKE_SIZE];
    read_exact(stream, &mut server_hs)?;

    // Verify banner
    if &server_hs[0..8] != b"OHOS HDC" {
        let got = String::from_utf8_lossy(&server_hs[0..8]);
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData,
            format!("bad banner: {:?}", got)));
    }

    // Build client handshake: banner + connect_key + version
    let mut client_hs = [0u8; HANDSHAKE_SIZE];
    client_hs[0..12].copy_from_slice(BANNER);
    // connect_key: "host:transport-any" in first bytes of the 32-byte field
    let key = b"host:transport-any";
    let key_len = key.len().min(32);
    client_hs[12..12+key_len].copy_from_slice(&key[..key_len]);
    // version: "1.0.0"
    let ver = b"1.0.0";
    let ver_len = ver.len().min(64);
    client_hs[44..44+ver_len].copy_from_slice(&ver[..ver_len]);

    stream.write_all(&client_hs)?;
    stream.flush()?;
    Ok(())
}

/// Send a command and read raw response
fn send_cmd(stream: &mut TcpStream, cmd: u16, args: &str) -> std::io::Result<Vec<u8>> {
    let payload = format!("{}\0", args);
    let pkt = build_packet(cmd, payload.as_bytes());
    stream.write_all(&pkt)?;
    stream.flush()?;
    read_response(stream)
}

#[napi]
pub fn hdc_check_connection(host: Option<String>, port: Option<u16>) -> HdcStatus {
    let mut stream = match connect_to(host.clone(), port, 5) {
        Ok(s) => s,
        Err(e) => return HdcStatus { connected: false, device_count: None, error: Some(format!("connect: {}", e)) },
    };

    if let Err(e) = do_handshake(&mut stream) {
        return HdcStatus { connected: false, device_count: None, error: Some(format!("handshake: {}", e)) };
    }

    // After handshake, try list_targets
    match send_cmd(&mut stream, CMD_LIST_TARGETS, "list targets -v") {
        Ok(data) => {
            let resp = String::from_utf8_lossy(&data);
            let lines: Vec<&str> = resp.trim().lines().filter(|l| !l.is_empty()).collect();
            HdcStatus { connected: true, device_count: Some(lines.len() as u32), error: None }
        }
        Err(e) => HdcStatus { connected: true, device_count: Some(0), error: Some(format!("list: {}", e)) },
    }
}

#[napi]
pub fn hdc_execute_shell(command: String, host: Option<String>, port: Option<u16>) -> HdcOutput {
    let mut stream = match connect_to(host.clone(), port, 10) {
        Ok(s) => s,
        Err(e) => return HdcOutput { exit_code: -1, stdout: String::new(), stderr: format!("connect: {}", e) },
    };

    if let Err(e) = do_handshake(&mut stream) {
        return HdcOutput { exit_code: -1, stdout: String::new(), stderr: format!("handshake: {}", e) };
    }

    // Send ShellInit first to establish shell session
    let init_result = send_cmd(&mut stream, CMD_SHELL_INIT, "shell");
    // Ignore init result, send actual command
    let shell_cmd = format!("shell {}", command);
    match send_cmd(&mut stream, CMD_SHELL_DATA, &shell_cmd) {
        Ok(data) => {
            let resp = String::from_utf8_lossy(&data);
            HdcOutput { exit_code: 0, stdout: resp.trim_end_matches('\0').to_string(), stderr: String::new() }
        }
        Err(e) => HdcOutput { exit_code: -1, stdout: String::new(), stderr: format!("exec: {}", e) },
    }
}

#[napi]
pub fn hdc_ping(host: Option<String>, port: Option<u16>) -> bool {
    connect_to(host, port, 2).is_ok()
}
