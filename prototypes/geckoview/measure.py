#!/usr/bin/env python3
"""Explicit opt-in cold-process starts, or read-only named-scene memory capture.

Run only after builds finish and the operator confirms the scene. No data is
cleared. Cold starts force-stop only the two named comparison applications.
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

PACKAGES = {
    'webview': 'com.wingmanbrowser.wingman_browser',
    'gecko': 'com.wingmanbrowser.wingman_browser.gecko_prototype',
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--adb', default=str(Path.home() / 'Library/Android/sdk/platform-tools/adb'))
parser.add_argument('--serial', required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--webview-apk', type=Path, required=True)
parser.add_argument('--gecko-apk', type=Path, required=True)
actions = parser.add_mutually_exclusive_group(required=True)
actions.add_argument('--cold-startups', action='store_true')
actions.add_argument('--memory', choices=PACKAGES)
parser.add_argument('--scene', required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)

def run(command, timeout=60):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT, timeout=timeout)

def adb(*command):
    return run([args.adb, '-s', args.serial, *command])

def save(name, value):
    (args.output / name).write_text(value)

receipt = {
    'at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'serial': args.serial, 'scene': args.scene,
    'hostSwap': run(['sysctl', 'vm.swapusage']).strip(),
    'hostLoad': run(['uptime']).strip(),
    'device': {key: adb('shell', 'getprop', key).strip() for key in
               ['ro.build.version.sdk', 'ro.build.version.release', 'ro.product.cpu.abi', 'ro.product.model']},
    'pageSize': adb('shell', 'getconf', 'PAGESIZE').strip(),
    'artifacts': {},
}
for name, path in [('webview', args.webview_apk), ('gecko', args.gecko_apk)]:
    receipt['artifacts'][name] = {'path': str(path), 'bytes': path.stat().st_size,
                                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
save('provider.txt', adb('shell', 'dumpsys', 'webviewupdate'))

if args.cold_startups:
    receipt['method'] = 'Three alternating cold-process starts per app; retained app data and OS caches. am start is not first-content timing.'
    samples = []
    try:
        for index in range(3):
            for name, package in PACKAGES.items():
                for other in PACKAGES.values():
                    adb('shell', 'am', 'force-stop', other)
                start = time.monotonic()
                raw = adb('shell', 'am', 'start', '-W', '-a', 'android.intent.action.MAIN',
                          '-c', 'android.intent.category.LAUNCHER', '-n',
                          package + '/com.wingmanbrowser.wingman_browser.MainActivity')
                sample = {'engine': name, 'index': index + 1, 'commandSeconds': time.monotonic() - start}
                sample['mainPid'] = adb('shell', 'pidof', package).strip()
                for key in ['ThisTime', 'TotalTime', 'WaitTime']:
                    match = re.search(r'^' + key + r': (\d+)$', raw, re.M)
                    sample[key + 'Ms'] = int(match.group(1)) if match else None
                sample['status'] = re.search(r'^Status: (.+)$', raw, re.M).group(1) if 'Status:' in raw else 'missing'
                samples.append(sample)
                save(f'start-{name}-{index + 1}.txt', raw)
                time.sleep(3)
    finally:
        receipt['samples'] = samples
        save('receipt.json', json.dumps(receipt, indent=2) + '\n')
else:
    name = args.memory
    package = PACKAGES[name]
    activity = adb('shell', 'dumpsys', 'activity', 'activities')
    resumed = [line.strip() for line in activity.splitlines() if 'topResumedActivity=' in line]
    if not any(package + '/' in line for line in resumed):
        raise SystemExit('Requested comparison app is not foreground; no scene captured.')
    receipt['foreground'] = resumed
    process_text = adb('shell', 'ps', '-A', '-o', 'PID,NAME')
    processes = {}
    for line in process_text.splitlines()[1:]:
        parts = line.split(None, 1)
        if len(parts) == 2 and (parts[1] == package or parts[1].startswith(package + ':')):
            processes[int(parts[0])] = parts[1]
    service_text = adb('shell', 'dumpsys', 'activity', 'services')
    owned_services = []
    for block in re.split(r'(?=^  \* ServiceRecord\{)', service_text, flags=re.M):
        header = block.splitlines()[0] if block else ''
        if package + '/' not in header:
            continue
        if 'SandboxedProcessService' not in block and 'GeckoChildProcessServices' not in block:
            continue
        match = re.search(r'app=ProcessRecord\{\S+ (\d+):([^/\n]+)', block)
        if match:
            processes[int(match.group(1))] = match.group(2)
            owned_services.append(block)
    save('owned-service-bindings.txt', '\n'.join(owned_services))
    if not processes:
        raise SystemExit('No live owned process found.')
    start = time.monotonic()
    def capture(item):
        pid, process = item
        raw = adb('shell', 'dumpsys', 'meminfo', str(pid))
        save(f'process-{pid}-meminfo.txt', raw)
        values = {'pid': pid, 'process': process}
        for key in ['TOTAL PSS', 'TOTAL RSS', 'TOTAL SWAP PSS']:
            match = re.search(key + r':\s*(\d+)', raw)
            values[key + ' KiB'] = int(match.group(1)) if match else None
        return values
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        receipt['processes'] = list(pool.map(capture, processes.items()))
    receipt['captureSeconds'] = time.monotonic() - start
    receipt['sumPssKiB'] = sum(p['TOTAL PSS KiB'] or 0 for p in receipt['processes'])
    receipt['method'] = 'Concurrent per-PID meminfo; exact package processes plus independently owned renderer service bindings. RSS is not summed.'
    save('receipt.json', json.dumps(receipt, indent=2) + '\n')
print(json.dumps(receipt, indent=2))
