#!/usr/bin/env python3
"""Collector regressions using fake USB only; never read real devices or OAuth."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
PACKET = "5556000600000000005b030000000300000000000020000000000000000000000000000000000000000000000000000000000000020100000000000a000000000000000000000000000000000000000000000000d55c"


def cooldowns(env):
    code = r'''
const fs = require('node:fs');
const vm = require('node:vm');
for (const name of ['MouseBattery', 'DjiMicBattery']) {
    const source = fs.readFileSync(`services/${name}.qml`, 'utf8');
    const body = source.match(/function refresh\(force\) \{([\s\S]*?)\n    \}/)[1];
    for (const [now, previous, force, want] of [
        [100000, 3700000, false, true], // backwards wall-clock adjustment
        [104000, 100000, false, false],
        [111000, 100000, false, true],
        [104000, 100000, true, true],
    ]) {
        const ctx = { root: {enabled:true, queryPending:false, lastAttemptAt:previous},
            Date: {now: () => now}, queryProcess: {running:false}, watchdog: {restart() {}} };
        vm.runInNewContext(`function refresh(force) {${body}\n}\nrefresh(${force});`, ctx);
        if (ctx.queryProcess.running !== want)
            throw Error(`${name}: now=${now}, previous=${previous}, force=${force}: expected queryStarted=${want}`);
    }
}
'''
    subprocess.run(['node', '-e', code], cwd=ROOT, env=env, check=True)
    print('PASS: hardware cooldowns survive clock setbacks and retain forced refresh')


def events(log):
    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []


def wait_for(log, operation, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = [event for event in events(log) if event['op'] == operation]
        if found:
            return found[-1]
        time.sleep(0.01)
    raise AssertionError(f'Missing {operation}: {events(log)}')


def usb_checks(private, env):
    modules = private / 'modules/usb'
    modules.mkdir(parents=True)
    (modules / '__init__.py').write_text('')
    (modules / 'core.py').write_text('''import json, os, time
from pathlib import Path
class USBError(Exception): pass
class USBTimeoutError(USBError): pass
class NoBackendError(USBError): pass
def trace(op):
    with open(os.environ['DJI_TEST_LOG'], 'a') as stream:
        stream.write(json.dumps({'op': op, 'pid': os.getpid()}) + '\\n')
class Device:
    def is_kernel_driver_active(self, interface): return True
    def detach_kernel_driver(self, interface): trace('detached')
    def attach_kernel_driver(self, interface): trace('attached')
    def read(self, endpoint, length, timeout):
        trace('reading')
        if os.environ['DJI_TEST_MODE'] == 'success':
            return bytes.fromhex(''' + repr(PACKET) + ''')
        if os.environ['DJI_TEST_MODE'] == 'error':
            raise USBError('fixture read failed')
        time.sleep(0.05)
        raise USBTimeoutError()
def find(**kwargs): return Device()
''')
    (modules / 'util.py').write_text('''import os, time
from pathlib import Path
from .core import trace
def claim_interface(device, interface): trace('claimed')
def release_interface(device, interface):
    trace('release-start')
    gate = os.environ.get('DJI_TEST_CLEANUP_GATE')
    deadline = time.monotonic() + 10
    while gate and not Path(gate).exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    trace('released')
def dispose_resources(device): trace('disposed')
''')
    env = {**env, 'PYTHONPATH': str(modules.parent)}
    script = ROOT / 'scripts/dji-mic-battery.py'
    processes = []
    logs = []
    gates = []

    def case(name, mode='wait', hold_cleanup=False):
        log = private / f'{name}.jsonl'
        logs.append(log)
        gate = private / f'{name}.gate'
        if hold_cleanup:
            gates.append(gate)
        return log, {**env, 'DJI_TEST_LOG': str(log), 'DJI_TEST_MODE': mode,
                     'DJI_TEST_CLEANUP_GATE': str(gate) if hold_cleanup else ''}

    def launch(command, environment):
        proc = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        processes.append(proc)
        return proc

    def cleaned(log):
        wait_for(log, 'disposed')
        ops = [event['op'] for event in events(log)]
        assert ops.count('detached') == ops.count('released') == ops.count('attached') == ops.count('disposed') == 1, ops
        assert ops.index('released') < ops.index('attached') < ops.index('disposed'), ops

    try:
        log, settings = case('success', 'success')
        proc = launch([sys.executable, str(script)], settings)
        out, err = proc.communicate(timeout=5)
        assert proc.returncode == 0, err
        assert json.loads(out)['transmitters']['tx1'] == {'level': 2, 'charging': True}
        cleaned(log)

        log, settings = case('read-error', 'error')
        proc = launch([sys.executable, str(script)], settings)
        out, err = proc.communicate(timeout=5)
        assert proc.returncode == 1 and 'fixture read failed' in err, (out, err)
        cleaned(log)

        log, settings = case('sigterm')
        proc = launch([sys.executable, str(script)], settings)
        wait_for(log, 'reading')
        proc.terminate()
        proc.communicate(timeout=5)
        cleaned(log)
        assert proc.returncode == 128 + signal.SIGTERM, 'Cancellation must not report a successful empty reading'

        log, settings = case('killed-owner', hold_cleanup=True)
        proc = launch([sys.executable, str(script)], settings)
        wait_for(log, 'reading')
        proc.kill()
        wait_for(log, 'release-start')
        # A replacement query cannot touch USB while old cleanup owns the lock.
        other_log, other_settings = case('busy', 'success')
        other = launch([sys.executable, str(script)], other_settings)
        out, err = other.communicate(timeout=5)
        assert other.returncode != 0 and 'busy' in err.lower(), (out, err)
        assert not events(other_log), 'Overlapping query accessed USB'
        Path(settings['DJI_TEST_CLEANUP_GATE']).touch()
        proc.communicate(timeout=5)
        cleaned(log)

        # Real Quickshell process ownership, but a fake USB backend and no window.
        config = private / 'config'
        (config / 'services').mkdir(parents=True)
        (config / 'scripts').mkdir()
        for name in ('DjiMicBattery.qml', 'DjiMicBatteryParser.js'):
            shutil.copy2(ROOT / 'services' / name, config / 'services' / name)
        shutil.copy2(script, config / 'scripts/dji-mic-battery.py')
        (config / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
import "services" as Services
Scope {
    Services.DjiMicBattery {}
    IpcHandler { target: "fixture"; function stop(): void { Qt.quit(); } }
}
''')
        for name, mode, operation in (('qs-reading', 'wait', 'reading'), ('qs-cleanup', 'success', 'release-start')):
            log, settings = case(name, mode, hold_cleanup=mode == 'success')
            proc = launch(['quickshell', '-p', str(config), '--no-color'], settings)
            wait_for(log, operation)
            command = ['quickshell', '-p', str(config), 'ipc', 'call', 'fixture', 'stop']
            subprocess.run(command, env=settings, check=True, capture_output=True, text=True, timeout=5)
            out, err = proc.communicate(timeout=5)
            assert proc.returncode == 0, out + err
            if settings['DJI_TEST_CLEANUP_GATE']:
                Path(settings['DJI_TEST_CLEANUP_GATE']).touch()
            cleaned(log)
        print('PASS: reads/errors, SIGTERM, killed owners, overlap exclusion, Quickshell shutdown during read/cleanup')
    finally:
        for gate in gates:
            gate.touch()
        for proc in processes:
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=5)
        # Stop only remaining workers belonging to this private fake backend.
        pids = {event['pid'] for log in logs for event in events(log)}

        def fixture_alive(pid):
            try:
                directory = Path('/proc', str(pid))
                environment = (directory / 'environ').read_bytes()
                state = (directory / 'stat').read_text().split(') ', 1)[1].split()[0]
                return state != 'Z' and any(str(log).encode() in environment for log in logs)
            except (FileNotFoundError, ProcessLookupError):
                return False

        for pid in pids:
            if not fixture_alive(pid):
                continue
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                continue
            deadline = time.monotonic() + 3
            while fixture_alive(pid) and time.monotonic() < deadline:
                time.sleep(0.01)
            if fixture_alive(pid):
                os.kill(pid, signal.SIGKILL)
        for proc in processes:
            proc.communicate(timeout=5)


def check():
    with tempfile.TemporaryDirectory(prefix='desktop-status-collectors-', dir='/tmp/opencode') as directory:
        private = Path(directory)
        env = os.environ.copy()
        for name in ('XDG_CACHE_HOME', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'TMPDIR', 'XDG_RUNTIME_DIR'):
            path = private / name
            path.mkdir(mode=0o700)
            env[name] = str(path)
        env.update(QT_QPA_PLATFORM='offscreen', QML_DISABLE_DISK_CACHE='1', PYTHONDONTWRITEBYTECODE='1')
        env.pop('WAYLAND_DISPLAY', None)
        if sys.argv[1:] != ['usb']:
            cooldowns(env)
        if sys.argv[1:] != ['cooldowns']:
            usb_checks(private, env)


if __name__ == '__main__':
    check()
