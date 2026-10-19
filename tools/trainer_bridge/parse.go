package main

// Decoding of the two standard Bluetooth trainer data formats.
// Pure functions: unit tested in parse_test.go without any hardware.

import (
	"encoding/binary"
	"errors"
)

var errShort = errors.New("packet too short")

// Reading is one decoded trainer notification. Has* says which fields were present.
type Reading struct {
	Power      float64
	HasPower   bool
	Cadence    float64
	HasCadence bool
	SpeedKmh   float64
	HasSpeed   bool
}

// ParseIndoorBikeData decodes an FTMS Indoor Bike Data notification
// (Bluetooth Fitness Machine Service spec, section 4.9.1). Fields appear in a
// fixed order, each one present only if its flag bit is set.
func ParseIndoorBikeData(d []byte) (Reading, error) {
	var r Reading
	if len(d) < 2 {
		return r, errShort
	}
	flags := binary.LittleEndian.Uint16(d)
	off := 2
	take := func(n int) ([]byte, error) {
		if off+n > len(d) {
			return nil, errShort
		}
		b := d[off : off+n]
		off += n
		return b, nil
	}
	if flags&0x0001 == 0 { // bit 0 "More Data": 0 means instantaneous speed is present
		b, err := take(2)
		if err != nil {
			return r, err
		}
		r.SpeedKmh, r.HasSpeed = float64(binary.LittleEndian.Uint16(b))*0.01, true
	}
	if flags&0x0002 != 0 { // average speed
		if _, err := take(2); err != nil {
			return r, err
		}
	}
	if flags&0x0004 != 0 { // instantaneous cadence, 0.5 rpm units
		b, err := take(2)
		if err != nil {
			return r, err
		}
		r.Cadence, r.HasCadence = float64(binary.LittleEndian.Uint16(b))*0.5, true
	}
	if flags&0x0008 != 0 { // average cadence
		if _, err := take(2); err != nil {
			return r, err
		}
	}
	if flags&0x0010 != 0 { // total distance (24-bit)
		if _, err := take(3); err != nil {
			return r, err
		}
	}
	if flags&0x0020 != 0 { // resistance level
		if _, err := take(2); err != nil {
			return r, err
		}
	}
	if flags&0x0040 != 0 { // instantaneous power, signed watts
		b, err := take(2)
		if err != nil {
			return r, err
		}
		r.Power, r.HasPower = float64(int16(binary.LittleEndian.Uint16(b))), true
	}
	return r, nil
}

// CrankCadence turns Cycling Power "cumulative crank revolutions" into rpm.
type CrankCadence struct {
	haveLast   bool
	lastRevs   uint16
	lastTime   uint16 // 1/1024 s
	lastChange float64
	RPM        float64
}

// Update takes the latest counters; now is in seconds. Counters wrap at 65536.
func (c *CrankCadence) Update(revs, eventTime uint16, now float64) float64 {
	if c.haveLast {
		dRev := revs - c.lastRevs // uint16 arithmetic handles wrap-around
		dTime := eventTime - c.lastTime
		if dRev > 0 && dTime > 0 {
			c.RPM = float64(dRev) * 60.0 * 1024.0 / float64(dTime)
			c.lastChange = now
		} else if now-c.lastChange > 2.5 {
			c.RPM = 0 // no new revolutions for a while: the rider stopped
		}
	} else {
		c.lastChange = now
	}
	c.haveLast, c.lastRevs, c.lastTime = true, revs, eventTime
	return c.RPM
}

// ParseCyclingPower decodes a Cycling Power Measurement notification
// (Bluetooth Cycling Power Service spec, section 3.2).
func ParseCyclingPower(d []byte, cad *CrankCadence, now float64) (Reading, error) {
	var r Reading
	if len(d) < 4 {
		return r, errShort
	}
	flags := binary.LittleEndian.Uint16(d)
	r.Power, r.HasPower = float64(int16(binary.LittleEndian.Uint16(d[2:]))), true
	off := 4
	if flags&0x0001 != 0 { // pedal power balance
		off++
	}
	if flags&0x0004 != 0 { // accumulated torque
		off += 2
	}
	if flags&0x0010 != 0 { // wheel revolution data
		off += 6
	}
	if flags&0x0020 != 0 { // crank revolution data
		if off+4 > len(d) {
			return r, errShort
		}
		revs := binary.LittleEndian.Uint16(d[off:])
		t := binary.LittleEndian.Uint16(d[off+2:])
		r.Cadence, r.HasCadence = cad.Update(revs, t, now), true
	}
	return r, nil
}
