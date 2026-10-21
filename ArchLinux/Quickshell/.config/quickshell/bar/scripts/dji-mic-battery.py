#!/usr/bin/env python3
"""Read DJI Mic Mini USB receiver/transmitter battery levels as JSON."""

import json
import signal
import sys
import time

try:
    import usb.core
    import usb.util
except ImportError as exc:
    print(f"dji-mic-battery: PyUSB unavailable ({exc}); install PyUSB and libusb", file=sys.stderr)
    sys.exit(1)

VENDOR_ID = 0x2CA3
PRODUCT_ID = 0x4011
INTERFACE = 6
ENDPOINT = 0x86
TIMEOUT_SECONDS = 10

def crc(data, initial, polynomial):
    value = initial
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = (value >> 1) ^ (polynomial if value & 1 else 0)
    return value


def packets(buffer):
    """Yield complete, CRC-checked packets from a byte stream."""
    while buffer:
        start = buffer.find(0x55)
        if start < 0:
            buffer.clear()
            return
        del buffer[:start]
        if len(buffer) < 4:
            return
        if crc(buffer[:3], 0x77, 0x8C) != buffer[3]:
            del buffer[0]
            continue
        length = int.from_bytes(buffer[1:3], "little") & 0x3FF
        if length < 13:
            del buffer[0]
            continue
        if len(buffer) < length:
            return
        packet = bytes(buffer[:length])
        if crc(packet[:-2], 0x3692, 0x8408) != int.from_bytes(packet[-2:], "little"):
            del buffer[0]
            continue
        del buffer[:length]
        yield packet


def battery_status(packet):
    """Decode receiver and transmitter batteries from a status packet."""
    if packet[9:11] != b"\x5b\x03":
        return None
    data = packet[11:-2]
    if len(data) < 41 or data[3] != 0x03:
        return None

    rx = data[10]
    result = {
        "receiver": {"level": ((rx >> 5) & 7) or None, "charging": bool(rx & 0x10)},
        "transmitters": {},
    }
    for offset in range(41, len(data) - 31, 32):
        channel = data[offset + 1]
        if data[offset] != 0x02 or channel not in (1, 2, 4, 8):
            continue
        value = data[offset + 7]
        result["transmitters"][f"tx{channel.bit_length()}"] = {
            "level": ((value >> 2) & 7) or None,
            "charging": bool(value & 0x02),
        }
    return result


def terminate(signum, frame):
    # Let finally release USB resources; ignore repeated SIGTERM during cleanup.
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    raise SystemExit(128 + signum)


def main():
    device = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID)
    if device is None:
        raise RuntimeError("DJI Mic Mini USB receiver (2ca3:4011) not found")

    detached = False
    claimed = False
    try:
        if device.is_kernel_driver_active(INTERFACE):
            device.detach_kernel_driver(INTERFACE)
            detached = True
        usb.util.claim_interface(device, INTERFACE)
        claimed = True

        buffer = bytearray()
        latest = None
        deadline = time.monotonic() + TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            try:
                buffer.extend(device.read(ENDPOINT, 1024, timeout=500))
            except usb.core.USBTimeoutError:
                continue
            candidate = None
            for packet in packets(buffer):
                status = battery_status(packet)
                if status is not None:
                    latest = status
                    if status["transmitters"]:
                        candidate = status
            if candidate is not None:
                latest = candidate
                break

        if latest is None:
            raise RuntimeError("No battery status received within 10 seconds")
    finally:
        # A first SIGTERM arriving during normal cleanup must not interrupt it.
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        original_error = sys.exc_info()[1]
        errors = []
        for needed, name, action in (
            (claimed, "release interface", lambda: usb.util.release_interface(device, INTERFACE)),
            (detached, "restore kernel driver", lambda: device.attach_kernel_driver(INTERFACE)),
            (True, "dispose resources", lambda: usb.util.dispose_resources(device)),
        ):
            if needed:
                try:
                    action()
                except (usb.core.USBError, NotImplementedError) as exc:
                    errors.append(f"{name}: {exc}")
        if errors:
            if original_error is not None:
                errors.insert(0, f"original operation: {original_error}")
            raise RuntimeError("USB cleanup failed: " + "; ".join(errors))
    print(json.dumps(latest, separators=(",", ":")))


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, terminate)
    try:
        main()
    except usb.core.NoBackendError as exc:
        print(f"dji-mic-battery: libusb backend unavailable ({exc}); install libusb", file=sys.stderr)
        sys.exit(1)
    except (RuntimeError, usb.core.USBError, NotImplementedError) as exc:
        print(f"dji-mic-battery: {exc}", file=sys.stderr)
        sys.exit(1)
