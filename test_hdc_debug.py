"""
HDC Debug automated test script.
Usage: python test_hdc_debug.py
Requires: hdc in PATH, device connected in developer mode.
"""
import subprocess
import time
import re
import sys
import os

os.environ["PYTHONIOENCODING"] = "utf-8"

BUNDLE = "com.xuchaoji.hmos.supertools.dev"
ABILITY = "MainAbility"
HAP_PATH = os.path.join("main", "build", "dev", "outputs", "dev", "main-dev-signed.hap")

def run(cmd, timeout=10):
    """Run hdc shell command and return stdout."""
    args = ["hdc", "shell"]
    if isinstance(cmd, list):
        args.extend(cmd)
    else:
        args.append(cmd)
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                          encoding="utf-8", errors="replace")
    return (result.stdout or "") + (result.stderr or "")

def hdc_raw(cmd, timeout=10):
    """Run raw hdc command."""
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout,
                         encoding="utf-8", errors="replace").stdout or ""

def install():
    print("[1/6] Installing HAP...")
    out = hdc_raw(f'hdc install "{HAP_PATH}"', timeout=30)
    ok = "successfully" in out
    print(f"  {'OK' if ok else 'FAIL'}: {out.strip()[:200]}")
    return ok

def clear_logs():
    print("[2/6] Clearing hilog...")
    run("hilog -r", timeout=5)

def launch():
    print("[3/6] Launching app...")
    out = run(f"aa start -a {ABILITY} -b {BUNDLE}", timeout=5)
    ok = "successfully" in out
    print(f"  {'OK' if ok else 'FAIL'}")

def wait(sec, msg=""):
    print(f"  Waiting {sec}s{' - ' + msg if msg else ''}...")
    time.sleep(sec)

def tap_hdc_card():
    print("[4/6] Tapping HDC debug card...")
    # Try multiple Y positions to find the card
    for y in [1100, 1000, 1200, 1400, 900, 800, 1300]:
        run(f"uinput -T -c 550 {y}", timeout=3)
        time.sleep(0.3)

def capture():
    print("[5/6] Capturing hilog...")
    out = run("hilog -x", timeout=10)
    lines = [l.strip() for l in out.split('\n') if 'HDC_' in l or 'HDC_LOG' in l]
    for line in lines:
        print("  " + line)
    return lines

def analyze(lines):
    print("\n[6/6] Analyzing...")
    text = '\n'.join(lines)
    checks = {
        "Server constructed": "HdcServer constructed" in text,
        "ServerForClient Initial OK (rc=0)": "Initial: HdcServerForClient::Initial rc=0" in text,
        "Initial returning ret=1": "Initial returning ret=1" in text,
        "Server entering event loop": "all init passed" in text,
        "cmd() started": "cmd() start" in text,
        "cmd() completed": "cmd() done" in text,
        "Output file produced": "execCommand: outputLen" in text,
    }

    bind_fail = re.search(r'bind FAILED.*?ret=(-?\d+).*?errno=(\d+)', text)
    uds_fail = "SetUdsListen FAILED" in text
    no_output = "no output file" in text
    rc_check = re.search(r'Initial: HdcServerForClient::Initial rc=(-?\d+)', text)
    ret_check = re.search(r'Initial returning ret=(\d+)', text)

    for name, passed in checks.items():
        status = "PASS" if passed else "FAIL"
        print(f"  [{status}] {name}")

    if bind_fail:
        print(f"  [INFO] uv_pipe_bind failed: ret={bind_fail.group(1)}, errno={bind_fail.group(2)} (expected, TCP fallback)")
    if uds_fail:
        print(f"  [INFO] SetUdsListen failed (expected, TCP mode overrides)")
    if rc_check:
        rc = int(rc_check.group(1))
        if rc == 0:
            print(f"  [PASS] ServerForClient Initial rc=0")
        else:
            print(f"  [FAIL] ServerForClient Initial rc={rc}")

    # Success criteria: server started AND cmd produced output
    server_ok = (ret_check and int(ret_check.group(1)) == 1) or "all init passed" in text
    cmd_ok = not no_output and "cmd() done" in text

    if server_ok and cmd_ok:
        print("\nRESULT: PASS - HDC server started and commands work")
        return True
    elif server_ok:
        print("\nRESULT: PARTIAL - Server started but no command output")
        return False
    else:
        print("\nRESULT: FAIL - Server didn't start")
        return False

def main():
    print("=== HDC Debug Automated Test ===\n")
    install()
    clear_logs()
    launch()
    wait(4, "app init")
    tap_hdc_card()
    wait(6, "server startup + auto command")
    lines = capture()
    ok = analyze(lines)
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
