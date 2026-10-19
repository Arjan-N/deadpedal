package main

// FTMS Control Point: how the bridge sets the trainer's resistance for the
// virtual gears. Only used while a Zwift Click is connected, so riding
// without a Click leaves the trainer exactly as it was.

import (
	"fmt"
	"sync"
	"time"

	"tinygo.org/x/bluetooth"
)

var ftmsControlPoint = bluetooth.New16BitUUID(0x2AD9)

const (
	opRequestControl = 0x00
	opStartOrResume  = 0x07
)

type trainerControl struct {
	mu        sync.Mutex
	cp        *bluetooth.DeviceCharacteristic
	active    bool // a Click is connected: we're in charge of resistance
	inControl bool // the trainer accepted our control request
	grade     float64
	debug     bool
}

// attach is called when a trainer with an FTMS control point connects.
func (c *trainerControl) attach(cp bluetooth.DeviceCharacteristic) {
	// Responses arrive as indications; they must be enabled before writing.
	if err := cp.EnableNotifications(func(b []byte) {
		if c.debug {
			fmt.Printf("\n  [trainer control response] % x\n", b)
		}
	}); err != nil {
		fmt.Printf("  (trainer resistance control unavailable: %v)\n", err)
		return
	}
	c.mu.Lock()
	c.cp = &cp
	c.inControl = false
	active, grade := c.active, c.grade
	c.mu.Unlock()
	if active {
		c.setGrade(grade)
	}
}

func (c *trainerControl) detach() {
	c.mu.Lock()
	c.cp = nil
	c.inControl = false
	c.mu.Unlock()
}

// activate is called when a Click connects: from now on gears set resistance.
func (c *trainerControl) activate(grade float64) {
	c.mu.Lock()
	c.active = true
	c.mu.Unlock()
	c.setGrade(grade)
}

// setGrade sends the simulated slope for the current gear to the trainer.
func (c *trainerControl) setGrade(grade float64) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.grade = grade
	if !c.active || c.cp == nil {
		return
	}
	if !c.inControl {
		if err := c.write([]byte{opRequestControl}); err != nil {
			fmt.Printf("\n  (trainer refused resistance control: %v)\n", err)
			return
		}
		time.Sleep(150 * time.Millisecond)
		_ = c.write([]byte{opStartOrResume})
		c.inControl = true
	}
	if err := c.write(SimulationCommand(grade)); err != nil {
		fmt.Printf("\n  (could not set trainer resistance: %v)\n", err)
		c.inControl = false // ask for control again next time
	}
}

// release puts the trainer back on the flat when the bridge exits.
func (c *trainerControl) release() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cp != nil && c.inControl {
		_ = c.write(SimulationCommand(0))
	}
}

// write must be called with c.mu held.
func (c *trainerControl) write(b []byte) error {
	if c.debug {
		fmt.Printf("\n  [trainer control] % x\n", b)
	}
	if _, err := c.cp.Write(b); err != nil {
		if _, err2 := c.cp.WriteWithoutResponse(b); err2 != nil {
			return err
		}
	}
	return nil
}
