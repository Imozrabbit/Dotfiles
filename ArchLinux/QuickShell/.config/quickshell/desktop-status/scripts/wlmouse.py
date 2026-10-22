#!/usr/bin/env python3

import fcntl
import json
import os
import sys
import time
from pathlib import Path


VID = 0x36A7

# Prefer the wired mouse when present so charging state is read directly.
PIDS = {
    0xA884: 0,  # Beast X wired
    0xA882: 1,  # Beast X 1K receiver
}

REPORT_LEN = 65


# Linux ioctl encoding.
_IOC_NRBITS = 8
_IOC_TYPEBITS = 8
_IOC_SIZEBITS = 14

_IOC_NRSHIFT = 0
_IOC_TYPESHIFT = _IOC_NRSHIFT + _IOC_NRBITS
_IOC_SIZESHIFT = _IOC_TYPESHIFT + _IOC_TYPEBITS
_IOC_DIRSHIFT = _IOC_SIZESHIFT + _IOC_SIZEBITS

_IOC_WRITE = 1
_IOC_READ = 2


def _ioc(direction, type_, nr, size):
    return (
        (direction << _IOC_DIRSHIFT)
        | (ord(type_) << _IOC_TYPESHIFT)
        | (nr << _IOC_NRSHIFT)
        | (size << _IOC_SIZESHIFT)
    )


def hid_iocsfeature(length):
    return _ioc(_IOC_READ | _IOC_WRITE, "H", 0x06, length)


def hid_iocgfeature(length):
    return _ioc(_IOC_READ | _IOC_WRITE, "H", 0x07, length)


def usb_ids(hidraw):
    path = (hidraw / "device").resolve()

    for parent in (path, *path.parents):
        vendor = parent / "idVendor"
        product = parent / "idProduct"

        if not vendor.exists() or not product.exists():
            continue

        try:
            return (
                int(vendor.read_text().strip(), 16),
                int(product.read_text().strip(), 16),
            )
        except (OSError, ValueError):
            return None

    return None


def find_candidates():
    candidates = []

    for hidraw in Path("/sys/class/hidraw").glob("hidraw*"):
        ids = usb_ids(hidraw)

        if ids is None:
            continue

        vid, pid = ids

        if vid != VID or pid not in PIDS:
            continue

        candidates.append(
            (
                PIDS[pid],
                Path("/dev") / hidraw.name,
                pid,
            )
        )

    candidates.sort(key=lambda item: item[0])

    return candidates


def parse_response(data):
    # Expected frame:
    #
    # 00 a1 00 02 02 00 83 <charging> <battery> ...
    #
    # Byte 0 here is the HID report ID.
    for i in range(6, len(data) - 2):
        if (
            data[i] == 0x83
            and data[i - 1] == 0x00
            and data[i - 2] == 0x02
            and data[i - 3] == 0x02
            and data[i - 4] == 0x00
            and data[i - 5] in (0xA1, 0xA2)
        ):
            charging = data[i + 1] == 1
            battery = data[i + 2]

            if battery <= 100:
                return battery, charging

    return None


def query(path):
    fd = os.open(path, os.O_RDWR)

    try:
        # Report ID 0 + 64-byte WLMouse request:
        #
        # status = 0x00
        # target = 0x02  (mouse)
        # length = 0x02
        # page   = 0x00
        # command= 0x83  (battery)
        query = bytearray(REPORT_LEN)
        query[:7] = bytes([
            0x00,  # report ID
            0x00,  # request status
            0x00,
            0x02,  # mouse target
            0x02,  # response length
            0x00,  # device page
            0x83,  # battery command
        ])

        fcntl.ioctl(
            fd,
            hid_iocsfeature(REPORT_LEN),
            query,
            True,
        )

        for _ in range(12):
            time.sleep(0.03)

            response = bytearray(REPORT_LEN)
            response[0] = 0

            try:
                received = fcntl.ioctl(
                    fd,
                    hid_iocgfeature(REPORT_LEN),
                    response,
                    True,
                )
            except OSError:
                continue

            result = parse_response(response[:received])

            if result is not None:
                return result

        return None

    finally:
        os.close(fd)


def main():
    candidates = find_candidates()

    if not candidates:
        print("WLMouse not found", file=sys.stderr)
        return 1

    permission_error = False

    for _, path, pid in candidates:
        try:
            result = query(path)
        except PermissionError:
            permission_error = True
            continue
        except OSError:
            continue

        if result is None:
            continue

        battery, charging = result

        print(json.dumps(
            {
                "battery": battery,
                "charging": charging,
                "connection": "wired" if pid == 0xA884 else "wireless",
            },
            separators=(",", ":"),
        ))

        return 0

    if permission_error:
        print("Permission denied accessing WLMouse hidraw device", file=sys.stderr)
    else:
        print("No battery response", file=sys.stderr)

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
