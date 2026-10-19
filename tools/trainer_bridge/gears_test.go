package main

import (
	"encoding/binary"
	"testing"
)

func TestGearboxShiftsWithinRange(t *testing.T) {
	g := NewGearbox(24, 8, 0.4)
	if g.Gear() != 8 || g.Grade() != 0 {
		t.Fatalf("starts in neutral on the flat, got gear %d grade %v", g.Gear(), g.Grade())
	}
	if gear, changed := g.Shift(+1); gear != 9 || !changed {
		t.Fatalf("shift up: gear %d changed %v", gear, changed)
	}
	for i := 0; i < 50; i++ {
		g.Shift(+1)
	}
	if g.Gear() != 24 {
		t.Fatalf("top gear = %d, want 24", g.Gear())
	}
	if _, changed := g.Shift(+1); changed {
		t.Fatal("shifting past the top gear should not change anything")
	}
	if g.Grade() > maxGrade {
		t.Fatalf("grade %v exceeds the safety limit", g.Grade())
	}
	for i := 0; i < 50; i++ {
		g.Shift(-1)
	}
	if g.Gear() != 1 || g.Grade() < minGrade {
		t.Fatalf("bottom gear %d grade %v", g.Gear(), g.Grade())
	}
}

func TestSimulationCommandEncoding(t *testing.T) {
	b := SimulationCommand(2.5)
	if len(b) != 7 || b[0] != 0x11 {
		t.Fatalf("bad command % x", b)
	}
	if grade := int16(binary.LittleEndian.Uint16(b[3:])); grade != 250 {
		t.Fatalf("grade field = %d, want 250 (0.01 %% units)", grade)
	}
	if neg := int16(binary.LittleEndian.Uint16(SimulationCommand(-1.2)[3:])); neg != -120 {
		t.Fatalf("negative grade field = %d", neg)
	}
}

func TestClickV1Buttons(t *testing.T) {
	cases := []struct {
		msg  []byte
		want ShiftButtons
	}{
		{[]byte{0x37, 0x08, 0x00, 0x10, 0x01}, ShiftButtons{Up: true}},   // plus pressed
		{[]byte{0x37, 0x08, 0x01, 0x10, 0x00}, ShiftButtons{Down: true}}, // minus pressed
		{[]byte{0x37, 0x08, 0x01, 0x10, 0x01}, ShiftButtons{}},           // released
	}
	for _, c := range cases {
		got, ok := ParseZwiftControllerMessage(c.msg)
		if !ok || got != c.want {
			t.Errorf("% x: got %+v ok=%v, want %+v", c.msg, got, ok, c.want)
		}
	}
}

func TestClickV2ButtonMap(t *testing.T) {
	msg := func(pressedBits uint32) []byte {
		return binary.AppendUvarint([]byte{0x23, 0x08}, uint64(^pressedBits))
	}
	if got, ok := ParseZwiftControllerMessage(msg(0)); !ok || got != (ShiftButtons{}) {
		t.Errorf("released: got %+v ok=%v", got, ok)
	}
	if got, _ := ParseZwiftControllerMessage(msg(btnRightUp)); !got.Up || got.Down {
		t.Errorf("plus on the right puck should shift up, got %+v", got)
	}
	if got, _ := ParseZwiftControllerMessage(msg(btnB)); got.Up || !got.Down {
		t.Errorf("B should shift down, got %+v", got)
	}
	// Exactly the released frame the Zwift apps send: all bits set.
	if got, ok := ParseZwiftControllerMessage([]byte{0x23, 0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F}); !ok || got != (ShiftButtons{}) {
		t.Errorf("released frame: got %+v ok=%v", got, ok)
	}
}

func TestOtherMessagesIgnored(t *testing.T) {
	for _, m := range [][]byte{
		[]byte("RideOn\x01\x03"), // handshake reply
		{0x15},                   // keep-alive
		{0x19, 0x08, 0x50},       // battery level
		{0x37},                   // truncated
		{0x23, 0x08, 0xFF, 0xFF}, // truncated varint
	} {
		if _, ok := ParseZwiftControllerMessage(m); ok {
			t.Errorf("% x should be ignored", m)
		}
	}
}

func TestShiftOncePerPress(t *testing.T) {
	var e shiftEdges
	steps := []ShiftButtons{{Up: true}, {Up: true}, {}, {Up: true}, {Down: true}, {}}
	total := 0
	for _, s := range steps {
		total += e.update(s)
	}
	// up, (held), release, up, down -> +1 +1 -1 = +1
	if total != 1 {
		t.Fatalf("net shift = %d, want 1", total)
	}
}
