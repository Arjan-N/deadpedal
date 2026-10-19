package main

import (
	"encoding/binary"
	"math"
	"testing"
)

func le(values ...any) []byte {
	var out []byte
	for _, v := range values {
		switch x := v.(type) {
		case uint16:
			out = binary.LittleEndian.AppendUint16(out, x)
		case int16:
			out = binary.LittleEndian.AppendUint16(out, uint16(x))
		case uint8:
			out = append(out, x)
		case []byte:
			out = append(out, x...)
		}
	}
	return out
}

func near(a, b float64) bool { return math.Abs(a-b) < 0.001 }

func TestIndoorBikeSpeedCadencePower(t *testing.T) {
	// speed present (bit0 = 0), cadence (bit2), power (bit6)
	r, err := ParseIndoorBikeData(le(uint16(0x0044), uint16(3250), uint16(170), int16(215)))
	if err != nil || !near(r.SpeedKmh, 32.5) || !near(r.Cadence, 85) || r.Power != 215 {
		t.Fatalf("got %+v, %v", r, err)
	}
}

func TestIndoorBikeSkipsOptionalFields(t *testing.T) {
	// avg speed, cadence, avg cadence, distance (24-bit), resistance, power
	flags := uint16(0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0020 | 0x0040)
	data := le(flags, uint16(3000), uint16(2900), uint16(180), uint16(175), []byte{0x39, 0x30, 0x00}, int16(20), int16(302))
	r, err := ParseIndoorBikeData(data)
	if err != nil || !near(r.Cadence, 90) || r.Power != 302 {
		t.Fatalf("got %+v, %v", r, err)
	}
}

func TestIndoorBikeMoreDataMeansNoSpeed(t *testing.T) {
	r, err := ParseIndoorBikeData(le(uint16(0x0041), int16(150)))
	if err != nil || r.HasSpeed || r.Power != 150 {
		t.Fatalf("got %+v, %v", r, err)
	}
}

func TestIndoorBikeTruncatedPacketIsAnError(t *testing.T) {
	if _, err := ParseIndoorBikeData(le(uint16(0x0044), uint16(3250))); err == nil {
		t.Fatal("expected an error for a truncated packet")
	}
}

func TestCyclingPowerAndCadence(t *testing.T) {
	var cad CrankCadence
	ParseCyclingPower(le(uint16(0x0020), int16(200), uint16(100), uint16(0)), &cad, 0)
	// 2 revolutions in 1.5 s (1536/1024 s) = 80 rpm
	r, err := ParseCyclingPower(le(uint16(0x0020), int16(210), uint16(102), uint16(1536)), &cad, 1.5)
	if err != nil || r.Power != 210 || !near(r.Cadence, 80) {
		t.Fatalf("got %+v, %v", r, err)
	}
}

func TestCrankCounterWraparound(t *testing.T) {
	var cad CrankCadence
	cad.Update(65535, 65000, 0)
	if rpm := cad.Update(1, 65000+1024-65536, 1); !near(rpm, 120) { // 2 revs in 1 s
		t.Fatalf("rpm = %v", rpm)
	}
}

func TestCadenceDropsToZeroWhenPedallingStops(t *testing.T) {
	var cad CrankCadence
	cad.Update(10, 0, 0)
	cad.Update(11, 768, 0.75)
	if cad.RPM <= 0 {
		t.Fatal("expected cadence while pedalling")
	}
	cad.Update(11, 768, 2.0)
	cad.Update(11, 768, 4.0)
	if cad.RPM != 0 {
		t.Fatalf("rpm = %v, want 0", cad.RPM)
	}
}

func TestCyclingPowerSkipsBalanceAndTorque(t *testing.T) {
	var cad CrankCadence
	r, err := ParseCyclingPower(le(uint16(0x0001|0x0004|0x0020), int16(250), uint8(50), uint16(1234), uint16(7), uint16(512)), &cad, 0)
	if err != nil || r.Power != 250 {
		t.Fatalf("got %+v, %v", r, err)
	}
}
