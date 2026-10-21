"""Run with python3 -B tests/hardware/dji-mic-backend-checks.py. Synthetic USB only."""
import contextlib
import builtins
import importlib.util
import io
import json
import runpy
import signal
import sys
from pathlib import Path
from types import ModuleType
from unittest.mock import patch

path = Path(__file__).parents[2] / "scripts/dji-mic-battery.py"
usb = ModuleType("usb")
usb.core, usb.util = ModuleType("usb.core"), ModuleType("usb.util")
class USBError(Exception): pass
class USBTimeoutError(USBError): pass
class NoBackendError(ValueError): pass
usb.core.USBError, usb.core.USBTimeoutError, usb.core.NoBackendError = USBError, USBTimeoutError, NoBackendError
with patch.dict(sys.modules, {"usb": usb, "usb.core": usb.core, "usb.util": usb.util}):
    spec = importlib.util.spec_from_file_location("dji", path)
    dji = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dji)

def packet(level=3):
    data = bytearray(41 if level is None else 73)
    data[3], data[10] = 3, (1 << 5) | 0x10
    if level is not None:
        data[41], data[42], data[48] = 2, 1, (level << 2) | 2
    length = len(data) + 13
    frame = bytearray([0x55, length & 255, ((length >> 8) & 3) | 4])
    frame.append(dji.crc(frame, 0x77, 0x8C))
    frame.extend(bytes(5) + b"\x5b\x03" + data)
    frame.extend(dji.crc(frame, 0x3692, 0x8408).to_bytes(2, "little"))
    return bytes(frame)

frame = packet()
expected = {"receiver": {"level": 1, "charging": True}, "transmitters": {"tx1": {"level": 3, "charging": True}}}
assert dji.battery_status(frame) == expected
for split in range(len(frame)):
    buffer = bytearray(frame[:split])
    assert list(dji.packets(buffer)) == []
    buffer.extend(frame[split:])
    assert list(dji.packets(buffer)) == [frame] and not buffer
bad = bytearray(frame); bad[-1] ^= 1
assert list(dji.packets(bytearray(b"noise" + bad + frame))) == [frame]

def run(chunks, failures=(), interrupt=False, interrupt_cleanup=False):
    events, clock, output = [], [0.0], io.StringIO()
    handlers = {signal.SIGTERM: dji.terminate}
    def action(name):
        events.append(name)
        if name == "release" and interrupt_cleanup:
            handler = handlers[signal.SIGTERM]
            if callable(handler): handler(signal.SIGTERM, None)
        if name in failures: raise USBError(name + " failed")
    class Device:
        def is_kernel_driver_active(self, interface): return True
        def detach_kernel_driver(self, interface): action("detach")
        def attach_kernel_driver(self, interface): action("restore")
        def read(self, endpoint, size, timeout):
            assert endpoint == 0x86 and size == 1024 and timeout == 500
            action("read")
            if interrupt: dji.terminate(signal.SIGTERM, None)
            if chunks: return chunks.pop(0)
            clock[0] += timeout / 1000
            raise USBTimeoutError()
    usb.core.find = lambda **kwargs: Device()
    usb.util.claim_interface = lambda *args: action("claim")
    usb.util.release_interface = lambda *args: action("release")
    usb.util.dispose_resources = lambda *args: action("dispose")
    error = None
    with contextlib.redirect_stdout(output), patch.object(dji.time, "monotonic", side_effect=lambda: clock[0]), patch.object(signal, "signal", side_effect=lambda signum, handler: handlers.__setitem__(signum, handler)):
        try: dji.main()
        except (RuntimeError, USBError, SystemExit) as exc: error = exc
    return output.getvalue(), events, error, clock[0]

output, events, error, _ = run([packet(1) + packet(3)])
assert error is None and json.loads(output) == expected, "Return latest qualifying status from whole USB batch"
assert events[-3:] == ["release", "restore", "dispose"]
for failure in ("release", "restore", "dispose"):
    output, events, error, _ = run([frame], failures=(failure,))
    assert error is not None and failure in str(error), "Cleanup failure must be reported"
    assert output == "", "Success JSON must wait for successful cleanup"
    assert events[-3:] == ["release", "restore", "dispose"], "All cleanup steps must be attempted"
output, events, error, _ = run([], interrupt=True)
assert isinstance(error, SystemExit) and error.code == 143 and not output
assert events[-3:] == ["release", "restore", "dispose"], "SIGTERM must clean up"
output, events, error, _ = run([frame], interrupt_cleanup=True)
assert error is None and events[-3:] == ["release", "restore", "dispose"], "SIGTERM during cleanup cannot skip remaining cleanup"
output, events, error, elapsed = run([packet(None)])
assert error is None and json.loads(output)["transmitters"] == {} and elapsed == 10, "Preserve receiver-only fallback and acquisition window"
output, events, error, _ = run([])
assert isinstance(error, RuntimeError) and not output, "No status must not output fake battery data"
output, events, error, _ = run([], failures=("claim",))
assert error is not None and events[-2:] == ["restore", "dispose"] and "release" not in events

usb.core.find = lambda **kwargs: (_ for _ in ()).throw(NoBackendError("No backend available"))
stdout, stderr = io.StringIO(), io.StringIO()
with patch.dict(sys.modules, {"usb": usb, "usb.core": usb.core, "usb.util": usb.util}), patch.object(signal, "signal"), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
    try: runpy.run_path(str(path), run_name="__main__")
    except SystemExit as exc: assert exc.code == 1
    else: raise AssertionError("Missing libusb backend must fail")
assert not stdout.getvalue() and "Traceback" not in stderr.getvalue() and "libusb" in stderr.getvalue().lower()
original_import = builtins.__import__
def missing_pyusb(name, *args, **kwargs):
    if name.startswith("usb"):
        raise ModuleNotFoundError("No module named 'usb'", name="usb")
    return original_import(name, *args, **kwargs)
stdout, stderr = io.StringIO(), io.StringIO()
with patch.object(builtins, "__import__", side_effect=missing_pyusb), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
    try: runpy.run_path(str(path), run_name="__main__")
    except SystemExit as exc: assert exc.code == 1
    else: raise AssertionError("Missing PyUSB must fail")
assert not stdout.getvalue() and "Traceback" not in stderr.getvalue() and "PyUSB" in stderr.getvalue()
print("DJI parser, latest batch, cleanup failures, termination and backend diagnostics passed; synthetic USB only")
