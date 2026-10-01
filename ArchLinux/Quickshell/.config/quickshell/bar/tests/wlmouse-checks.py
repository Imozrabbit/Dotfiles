import importlib.util
import sys
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
path = Path(__file__).resolve().parents[1] / "scripts" / "wlmouse.py"
spec = importlib.util.spec_from_file_location("wlmouse", path)
mouse = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mouse)

header = bytes([0, 0xA1, 0, 2, 2, 0, 0x83])


def check(replies, expected, reads):
    responses = iter(replies)
    count = 0

    def ioctl(fd, operation, buffer, mutate):
        nonlocal count
        if operation == mouse.hid_iocsfeature(mouse.REPORT_LEN):
            return len(buffer)
        count += 1
        payload = next(responses, header)
        buffer[:len(payload)] = payload
        return len(payload)

    with patch.object(mouse.os, "open", return_value=42), \
         patch.object(mouse.os, "close") as close, \
         patch.object(mouse.time, "sleep"), \
         patch.object(mouse.fcntl, "ioctl", side_effect=ioctl):
        assert mouse.query("mock device") == expected
        close.assert_called_once_with(42)
        assert count == reads


check([header, header + bytes([1, 57])], (57, True), 2)
check([header], None, 12)
check([header + bytes([0, 0])], (0, False), 1)
print("WLMouse query checks passed; no HID access")
