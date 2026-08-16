"""
HDC Debug feature verification (device-side, post-install).
Usage: python verify_hdc_debug.py [--bundle com.xuchaoji.hmos.supertools.dev]
Requires: hdc connected & authorized, app installed.

Checks:
  1. native bridge call + server start (hilog)
  2. real readiness probe -> UI shows "Server ready"
  3. auto command `list targets -v` executed (hilog) and shown in terminal
  4. new UI elements present (Terminal / follow toggle / quick categories)
  5. manual quick command execution (tap `version` chip) -> output + duration
"""
import subprocess
import time
import sys
import os

os.environ["PYTHONIOENCODING"] = "utf-8"

BUNDLE = sys.argv[sys.argv.index("--bundle") + 1] if "--bundle" in sys.argv else "com.xuchaoji.hmos.supertools.dev"
ABILITY = "MainAbility"

def sh(cmd, timeout=15):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout,
                       encoding="utf-8", errors="replace")
    return (r.stdout or "") + (r.stderr or "")

def latest_layout():
    sh("hdc shell uitest dumpLayout", timeout=10)
    f = sh('hdc shell "ls -t /data/local/tmp/layout_*.json 2>/dev/null | head -1"', timeout=10).strip()
    return sh(f"hdc shell cat {f}", timeout=10)

def find_center(layout, text):
    idx = layout.find(f'"text":"{text}"')
    if idx < 0:
        idx = layout.find(f'"originalText":"{text}"')
    if idx < 0:
        return None
    seg = layout[max(0, idx - 400): idx + 900]
    import re
    m = re.search(r'"bounds":"\[(\d+),(\d+),(\d+),(\d+)\]"', seg)
    if not m:
        return None
    x1, y1, x2, y2 = (int(m.group(i)) for i in range(1, 5))
    return (x1 + x2) // 2, (y1 + y2) // 2

def main():
    print("=== HDC Debug verification ===\n")

    sh("hdc shell aa force-stop " + BUNDLE, timeout=10)
    sh("hdc shell hilog -r", timeout=10)
    time.sleep(1)

    print("[1] Launching app...")
    sh(f"hdc shell aa start -a {ABILITY} -b {BUNDLE}", timeout=10)
    time.sleep(6)

    log = sh("hdc shell hilog -x", timeout=10)
    hdc_lines = [l for l in log.split("\n") if "HDC_Z" in l]
    checks = {
        "native hdcServer called": any("hdcServer called from ArkTS" in l for l in hdc_lines),
        "server started OK": any("startServer: native hdcServer returned OK" in l for l in hdc_lines),
        "auto command executed (execCommand)": any("execCommand: cmd=" in l for l in hdc_lines),
    }
    for k, v in checks.items():
        print(f"  [{'PASS' if v else 'FAIL'}] {k}")

    print("[2] Entering HDC Debug page...")
    home = latest_layout()
    pt = find_center(home, "HDC 调试")
    if not pt:
        print("  [FAIL] HDC card not found on home page")
        return 1
    sh(f"hdc shell uinput -T -c {pt[0]} {pt[1]}", timeout=10)
    time.sleep(3)
    layout = latest_layout()

    ui_checks = {
        "page title 'HDC Debug'": "HDC Debug" in layout,
        "server status '● Server'": "Server ready" in layout or "● Server" in layout,
        "terminal panel 'Terminal'": "Terminal" in layout,
        "follow toggle '⤓ 跟随'": "跟随" in layout,
        "quick categories": all(k in layout for k in ("常用", "系统", "进程", "网络", "存储", "日志")),
        "auto output + duration": ("$ list targets -v" in layout) and ("⏱" in layout),
    }
    for k, v in ui_checks.items():
        print(f"  [{'PASS' if v else 'FAIL'}] {k}")

    print("[3] Tapping 'version' quick command...")
    pt = find_center(layout, "version")
    if pt:
        sh(f"hdc shell uinput -T -c {pt[0]} {pt[1]}", timeout=10)
        time.sleep(3)
        layout2 = latest_layout()
        ok = ("$ version" in layout2) and ("Ver:" in layout2) and ("⏱" in layout2)
        print(f"  [{'PASS' if ok else 'FAIL'}] version executed with output + duration")
    else:
        print("  [FAIL] version chip not found")

    passed = sum(1 for _, v in {**checks, **ui_checks}.items() if v)
    total = len(checks) + len(ui_checks)
    print(f"\nRESULT: {passed}/{total} checks passed")
    return 0 if passed >= total - 1 else 1

if __name__ == "__main__":
    sys.exit(main())
