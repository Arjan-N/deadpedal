"""Tests for the trainer bridge's Bluetooth data parsing (no hardware needed).

Run:  python -m unittest tools/trainer_bridge/test_trainer_bridge.py
"""

import struct
import unittest

from trainer_bridge import CrankCadence, parse_cycling_power, parse_indoor_bike_data


class IndoorBikeDataTests(unittest.TestCase):
    def test_speed_cadence_power(self):
        # flags: speed present (bit0 = 0), cadence (bit2), power (bit6)
        flags = 0x0004 | 0x0040
        data = struct.pack("<HHHh", flags, 3250, 170, 215)  # 32.5 km/h, 85 rpm, 215 W
        r = parse_indoor_bike_data(data)
        self.assertAlmostEqual(r["speed_kmh"], 32.5)
        self.assertAlmostEqual(r["cadence"], 85.0)
        self.assertEqual(r["power"], 215.0)

    def test_skips_optional_fields_before_power(self):
        # avg speed, cadence, avg cadence, distance (uint24), resistance, power
        flags = 0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0020 | 0x0040
        data = struct.pack("<HHHHH", flags, 3000, 2900, 180, 175) + (12345).to_bytes(3, "little") + struct.pack("<hh", 20, 302)
        r = parse_indoor_bike_data(data)
        self.assertAlmostEqual(r["cadence"], 90.0)
        self.assertEqual(r["power"], 302.0)

    def test_more_data_flag_means_no_speed(self):
        data = struct.pack("<Hh", 0x0001 | 0x0040, 150)
        r = parse_indoor_bike_data(data)
        self.assertNotIn("speed_kmh", r)
        self.assertEqual(r["power"], 150.0)


class CyclingPowerTests(unittest.TestCase):
    def test_power_and_cadence_from_crank_revolutions(self):
        cad = CrankCadence()
        flags = 0x0020  # crank revolution data present
        parse_cycling_power(struct.pack("<HhHH", flags, 200, 100, 0), cad, 0.0)
        # 2 revolutions in 1.5 s (1536/1024) = 80 rpm
        r = parse_cycling_power(struct.pack("<HhHH", flags, 210, 102, 1536), cad, 1.5)
        self.assertEqual(r["power"], 210.0)
        self.assertAlmostEqual(r["cadence"], 80.0)

    def test_counter_wraparound(self):
        cad = CrankCadence()
        cad.update(65535, 65000, 0.0)
        rpm = cad.update(1, 65000 + 1024 - 65536, 1.0)  # 2 revs in 1 s across the wrap
        self.assertAlmostEqual(rpm, 120.0)

    def test_cadence_drops_to_zero_when_pedalling_stops(self):
        cad = CrankCadence()
        cad.update(10, 0, 0.0)
        cad.update(11, 768, 0.75)
        self.assertGreater(cad.rpm, 0)
        cad.update(11, 768, 2.0)
        cad.update(11, 768, 4.0)
        self.assertEqual(cad.rpm, 0.0)

    def test_skips_balance_and_torque_fields(self):
        cad = CrankCadence()
        flags = 0x0001 | 0x0004 | 0x0020
        data = struct.pack("<HhBHHH", flags, 250, 50, 1234, 7, 512)
        r = parse_cycling_power(data, cad, 0.0)
        self.assertEqual(r["power"], 250.0)


if __name__ == "__main__":
    unittest.main()
