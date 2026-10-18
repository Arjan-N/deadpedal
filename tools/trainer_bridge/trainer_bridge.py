"""DEAD PEDAL trainer bridge.

Connects to a Bluetooth smart trainer (e.g. Zwift Hub One, Wahoo KICKR,
Tacx, Elite...) and forwards live power and cadence to the game over UDP on
this computer (127.0.0.1:47800). The game's "Smart trainer" input reads it.

Supports the two standard Bluetooth profiles trainers broadcast:
  * Fitness Machine Service (FTMS) - Indoor Bike Data   (preferred)
  * Cycling Power Service (CPS)    - Power Measurement  (fallback)

Usage:
  python trainer_bridge.py                 scan and connect to the first trainer
  python trainer_bridge.py --name "Zwift"  only trainers whose name contains this
  python trainer_bridge.py --list          just list nearby trainers
  python trainer_bridge.py --simulate      no hardware: send fake data, clearly
                                           marked as simulated (for testing)

Only reads data; it never changes the trainer's resistance.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import socket
import struct
import sys
import time

GAME_ADDRESS = ("127.0.0.1", 47800)

FTMS_SERVICE = "00001826-0000-1000-8000-00805f9b34fb"
INDOOR_BIKE_DATA = "00002ad2-0000-1000-8000-00805f9b34fb"
CPS_SERVICE = "00001818-0000-1000-8000-00805f9b34fb"
CPS_MEASUREMENT = "00002a63-0000-1000-8000-00805f9b34fb"

# How often the last reading is re-sent so the game knows we're alive.
HEARTBEAT_SECONDS = 0.25
# Readings older than this are not forwarded (trainer stopped sending).
STALE_SECONDS = 3.0


# --- Parsing (pure functions, unit tested in test_trainer_bridge.py) ---------

def parse_indoor_bike_data(data: bytes) -> dict:
    """Parses an FTMS Indoor Bike Data notification (Bluetooth spec 4.9.1).

    Returns a dict that may contain 'power' (W), 'cadence' (rpm) and
    'speed_kmh'. Fields are present in the order defined by the flags.
    """
    flags = struct.unpack_from("<H", data, 0)[0]
    offset = 2
    result: dict = {}

    def take(fmt: str):
        nonlocal offset
        value = struct.unpack_from(fmt, data, offset)
        offset += struct.calcsize(fmt)
        return value[0] if len(value) == 1 else value

    if not flags & 0x0001:            # bit 0 = "More Data"; 0 means speed present
        result["speed_kmh"] = take("<H") * 0.01
    if flags & 0x0002:                # average speed
        take("<H")
    if flags & 0x0004:                # instantaneous cadence, 0.5 rpm units
        result["cadence"] = take("<H") * 0.5
    if flags & 0x0008:                # average cadence
        take("<H")
    if flags & 0x0010:                # total distance (uint24)
        offset += 3
    if flags & 0x0020:                # resistance level
        take("<h")
    if flags & 0x0040:                # instantaneous power
        result["power"] = float(take("<h"))
    return result


class CrankCadence:
    """Turns Cycling Power 'cumulative crank revolutions' into rpm."""

    def __init__(self) -> None:
        self._last: tuple[int, int] | None = None
        self._last_change = 0.0
        self.rpm = 0.0

    def update(self, revolutions: int, event_time_1024: int, now: float) -> float:
        if self._last is not None:
            d_rev = (revolutions - self._last[0]) & 0xFFFF
            d_time = (event_time_1024 - self._last[1]) & 0xFFFF
            if d_rev > 0 and d_time > 0:
                self.rpm = d_rev * 60.0 * 1024.0 / d_time
                self._last_change = now
            elif now - self._last_change > 2.5:
                self.rpm = 0.0  # no new revolutions: the rider stopped
        else:
            self._last_change = now
        self._last = (revolutions, event_time_1024)
        return self.rpm


def parse_cycling_power(data: bytes, cadence: CrankCadence, now: float) -> dict:
    """Parses a Cycling Power Measurement notification (Bluetooth spec 3.2)."""
    flags, power = struct.unpack_from("<Hh", data, 0)
    offset = 4
    result: dict = {"power": float(power)}
    if flags & 0x0001:   # pedal power balance
        offset += 1
    if flags & 0x0004:   # accumulated torque
        offset += 2
    if flags & 0x0010:   # wheel revolution data
        offset += 6
    if flags & 0x0020:   # crank revolution data
        revs, event_time = struct.unpack_from("<HH", data, offset)
        result["cadence"] = cadence.update(revs, event_time, now)
    return result


# --- Sending to the game -----------------------------------------------------

class GameLink:
    def __init__(self, device_name: str, simulated: bool) -> None:
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.device_name = device_name
        self.simulated = simulated
        self.power = 0.0
        self.cadence = -1.0
        self.updated = 0.0

    def update(self, reading: dict) -> None:
        if "power" in reading:
            self.power = max(0.0, reading["power"])
        if "cadence" in reading:
            self.cadence = reading["cadence"]
        self.updated = time.monotonic()

    def send(self) -> None:
        if time.monotonic() - self.updated > STALE_SECONDS:
            return
        packet = {
            "power": round(self.power, 1),
            "cadence": round(self.cadence, 1),
            "device": self.device_name,
            "simulated": self.simulated,
        }
        self.sock.sendto(json.dumps(packet).encode(), GAME_ADDRESS)

    async def heartbeat(self) -> None:
        while True:
            self.send()
            await asyncio.sleep(HEARTBEAT_SECONDS)


def status_line(link: GameLink) -> None:
    cad = f"{link.cadence:5.0f} rpm" if link.cadence >= 0 else "  -- rpm"
    print(f"\r  {link.power:5.0f} W  {cad}   -> game on {GAME_ADDRESS[0]}:{GAME_ADDRESS[1]}   ", end="", flush=True)


# --- Bluetooth -----------------------------------------------------------------

def _import_bleak():
    try:
        import bleak  # noqa: F401
        return bleak
    except ImportError:
        print("The 'bleak' Bluetooth library is missing. Install it with:\n"
              "    python -m pip install bleak\n"
              "(start_bridge.bat does this for you on Windows.)")
        sys.exit(1)


async def find_trainers(name_filter: str | None, timeout: float = 8.0) -> list:
    bleak = _import_bleak()
    print(f"Scanning for trainers for {timeout:.0f} s... (pedal to wake the trainer up)")
    found = await bleak.BleakScanner.discover(timeout=timeout, return_adv=True)
    trainers = []
    for device, adv in found.values():
        uuids = [u.lower() for u in (adv.service_uuids or [])]
        name = device.name or adv.local_name or ""
        is_trainer = FTMS_SERVICE in uuids or CPS_SERVICE in uuids or "hub" in name.lower()
        if not is_trainer:
            continue
        if name_filter and name_filter.lower() not in name.lower():
            continue
        trainers.append((device, name or device.address, FTMS_SERVICE in uuids))
    # Prefer FTMS trainers.
    trainers.sort(key=lambda t: not t[2])
    return trainers


async def run_bluetooth(args) -> None:
    bleak = _import_bleak()
    while True:
        trainers = await find_trainers(args.name)
        if not trainers:
            print("No trainer found. Is it powered on and NOT connected to Zwift or another app?\n"
                  "Retrying in 3 s...")
            await asyncio.sleep(3)
            continue
        device, name, _ = trainers[0]
        print(f"Connecting to {name} ({device.address})...")
        link = GameLink(name, simulated=False)
        cadence = CrankCadence()
        disconnected = asyncio.Event()
        try:
            async with bleak.BleakClient(device, disconnected_callback=lambda _c: disconnected.set()) as client:
                characteristics = {c.uuid.lower() for s in client.services for c in s.characteristics}
                if INDOOR_BIKE_DATA in characteristics:
                    def on_bike_data(_sender, data: bytearray) -> None:
                        link.update(parse_indoor_bike_data(bytes(data)))
                        status_line(link)
                    await client.start_notify(INDOOR_BIKE_DATA, on_bike_data)
                    profile = "FTMS Indoor Bike Data"
                elif CPS_MEASUREMENT in characteristics:
                    def on_power(_sender, data: bytearray) -> None:
                        link.update(parse_cycling_power(bytes(data), cadence, time.monotonic()))
                        status_line(link)
                    await client.start_notify(CPS_MEASUREMENT, on_power)
                    profile = "Cycling Power"
                else:
                    print("This device doesn't offer FTMS or Cycling Power data.")
                    await asyncio.sleep(3)
                    continue
                print(f"Connected using {profile}. Start DEAD PEDAL and choose 'Smart trainer'.")
                print("Leave this window open while you ride. Ctrl+C to stop.")
                beat = asyncio.create_task(link.heartbeat())
                await disconnected.wait()
                beat.cancel()
                print("\nTrainer disconnected - reconnecting...")
        except Exception as e:  # noqa: BLE001 - keep the bridge alive whatever happens
            print(f"\nConnection problem: {e}\nRetrying in 3 s...")
            await asyncio.sleep(3)


async def run_simulated() -> None:
    """Fake rider for testing without hardware. Marked simulated in every packet."""
    link = GameLink("Simulated trainer", simulated=True)
    print("SIMULATED trainer (no hardware). Sending fake power to the game.")
    start = time.monotonic()
    while True:
        t = time.monotonic() - start
        link.update({"power": 190 + 40 * math.sin(t / 6.0), "cadence": 85 + 5 * math.sin(t / 3.0)})
        link.send()
        status_line(link)
        await asyncio.sleep(HEARTBEAT_SECONDS)


async def list_only(args) -> None:
    trainers = await find_trainers(args.name)
    if not trainers:
        print("No trainers found.")
    for device, name, ftms in trainers:
        print(f"  {name:30s} {device.address}   {'FTMS' if ftms else 'Cycling Power'}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Forward smart-trainer power to DEAD PEDAL.")
    parser.add_argument("--name", help="only connect to trainers whose name contains this text")
    parser.add_argument("--list", action="store_true", help="list nearby trainers and exit")
    parser.add_argument("--simulate", action="store_true", help="send fake data (no hardware needed)")
    args = parser.parse_args()
    print("DEAD PEDAL trainer bridge")
    try:
        if args.simulate:
            asyncio.run(run_simulated())
        elif args.list:
            asyncio.run(list_only(args))
        else:
            asyncio.run(run_bluetooth(args))
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
