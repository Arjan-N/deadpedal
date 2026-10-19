package main

// Virtual gears and Zwift Click decoding. Pure logic, unit tested in gears_test.go.
//
// Virtual shifting works like Zwift's: your power still decides your in-game
// speed; a gear only changes how heavy the trainer feels at a given cadence.
// The bridge does that with the standard FTMS "indoor bike simulation"
// command: each gear above the neutral gear adds a little slope, each gear
// below takes some away.

import (
	"encoding/binary"
	"math"
	"sync"
)

// Gearbox holds the current virtual gear. Safe for concurrent use.
type Gearbox struct {
	mu        sync.Mutex
	count     int     // number of gears (1..count)
	neutral   int     // this gear feels like riding on the flat
	stepGrade float64 // % slope added per gear above neutral
	gear      int
}

// Slope limits, so no gear can make the trainer dangerously heavy or spin free.
const (
	minGrade = -3.0
	maxGrade = 8.0
)

func NewGearbox(count, neutral int, stepGrade float64) *Gearbox {
	neutral = max(1, min(neutral, count))
	return &Gearbox{count: count, neutral: neutral, stepGrade: stepGrade, gear: neutral}
}

// Shift moves delta gears (+1 harder, -1 easier) and reports whether it changed.
func (g *Gearbox) Shift(delta int) (gear int, changed bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	next := max(1, min(g.gear+delta, g.count))
	changed = next != g.gear
	g.gear = next
	return g.gear, changed
}

func (g *Gearbox) Gear() int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.gear
}

func (g *Gearbox) Count() int { return g.count }

// Grade is the simulated slope (%) for the current gear.
func (g *Gearbox) Grade() float64 {
	g.mu.Lock()
	defer g.mu.Unlock()
	return math.Max(minGrade, math.Min(maxGrade, float64(g.gear-g.neutral)*g.stepGrade))
}

// SimulationCommand builds the FTMS Control Point "Set Indoor Bike Simulation
// Parameters" (op code 0x11): wind speed 0, the given grade, typical road
// rolling resistance (Crr 0.004) and wind resistance (Cw 0.51 kg/m).
func SimulationCommand(gradePercent float64) []byte {
	b := []byte{0x11}
	b = binary.LittleEndian.AppendUint16(b, 0)                                           // wind speed, 0.001 m/s
	b = binary.LittleEndian.AppendUint16(b, uint16(int16(math.Round(gradePercent*100)))) // grade, 0.01 %
	return append(b, 40, 51)                                                             // Crr x 0.0001, Cw x 0.01
}

// --- Zwift Click ----------------------------------------------------------------

// ShiftButtons is which shift buttons are held down in a controller message.
type ShiftButtons struct{ Up, Down bool }

const (
	clickV1Message    = 0x37 // Zwift Click (v1): two button fields
	controllerMessage = 0x23 // Zwift Click v2 / Ride / Play: a 32-bit button map
)

// Button bits in the v2 button map. A pressed button reads as a 0 bit.
const (
	btnB        = 0x00020
	btnY        = 0x00040
	btnZ        = 0x00080
	btnLeftUp   = 0x00100 // the "-" on a Click v2's left puck
	btnLeftDn   = 0x00200
	btnRightUp  = 0x01000 // the "+" on a Click v2's right puck
	btnRightDn  = 0x02000
	harderMask  = btnRightUp | btnY
	easierMask  = btnLeftUp | btnLeftDn | btnRightDn | btnB | btnZ
	clickV1Down = 0 // protobuf enum value for "pressed" (released = 1)
)

// ParseZwiftControllerMessage decodes a button notification from a Zwift
// Click. ok is false for other messages (battery, keep-alive, handshake...).
//
// Click v1: "+" = harder gear, "-" = easier.
// Click v2 right puck (the left puck is locked to Zwift's own app):
// "+" or Y = harder, B or Z = easier.
func ParseZwiftControllerMessage(b []byte) (buttons ShiftButtons, ok bool) {
	if len(b) < 2 {
		return ShiftButtons{}, false
	}
	fields, valid := parseProtoVarints(b[1:])
	if !valid {
		return ShiftButtons{}, false
	}
	switch b[0] {
	case clickV1Message:
		plus, hasPlus := fields[1]
		minus, hasMinus := fields[2]
		if !hasPlus && !hasMinus {
			return ShiftButtons{}, false
		}
		// A missing field means the protobuf default (0), which is "pressed".
		return ShiftButtons{Up: plus == clickV1Down, Down: minus == clickV1Down}, true
	case controllerMessage:
		bitmap, has := fields[1]
		if !has {
			return ShiftButtons{}, false
		}
		pressed := ^uint32(bitmap)
		return ShiftButtons{Up: pressed&harderMask != 0, Down: pressed&easierMask != 0}, true
	}
	return ShiftButtons{}, false
}

// parseProtoVarints reads a protobuf message and returns its varint fields by
// field number. Other field types are skipped.
func parseProtoVarints(b []byte) (map[uint64]uint64, bool) {
	fields := map[uint64]uint64{}
	for len(b) > 0 {
		key, n := binary.Uvarint(b)
		if n <= 0 {
			return nil, false
		}
		b = b[n:]
		switch key & 7 {
		case 0: // varint
			v, m := binary.Uvarint(b)
			if m <= 0 {
				return nil, false
			}
			fields[key>>3] = v
			b = b[m:]
		case 1: // 64-bit
			if len(b) < 8 {
				return nil, false
			}
			b = b[8:]
		case 2: // length-delimited
			l, m := binary.Uvarint(b)
			if m <= 0 || uint64(len(b)-m) < l {
				return nil, false
			}
			b = b[m+int(l):]
		case 5: // 32-bit
			if len(b) < 4 {
				return nil, false
			}
			b = b[4:]
		default:
			return nil, false
		}
	}
	return fields, true
}

// shiftEdges turns button states into shift steps: a gear changes once per
// press, not continuously while held.
type shiftEdges struct{ prev ShiftButtons }

func (e *shiftEdges) update(now ShiftButtons) (delta int) {
	if now.Up && !e.prev.Up {
		delta++
	}
	if now.Down && !e.prev.Down {
		delta--
	}
	e.prev = now
	return delta
}
