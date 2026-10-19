package main

// Zwift Click support: connects to the Click (v1, or the right puck of a
// Click v2), performs the plain-text "RideOn" handshake, and turns button
// presses into gear shifts. Protocol facts (UUIDs, message types, button
// bits) follow the community reverse-engineering of the Zwift controllers.

import (
	"fmt"
	"time"

	"tinygo.org/x/bluetooth"
)

const zwiftCompanyID = 0x094A

// Device type byte at the start of the Zwift manufacturer data.
const (
	zwiftClickV1      = 0x09
	zwiftClickV2Right = 0x0A
	zwiftClickV2Left  = 0x0B
)

var (
	zwiftService   = mustUUID("00000001-19ca-4651-86e5-fa29dcdd09d1")
	zwiftAsync     = mustUUID("00000002-19ca-4651-86e5-fa29dcdd09d1") // button notifications
	zwiftSyncRx    = mustUUID("00000003-19ca-4651-86e5-fa29dcdd09d1") // we write here
	zwiftSyncTx    = mustUUID("00000004-19ca-4651-86e5-fa29dcdd09d1") // replies (indications)
	rideOnGreeting = []byte("RideOn")
)

func mustUUID(s string) bluetooth.UUID {
	u, err := bluetooth.ParseUUID(s)
	if err != nil {
		panic(err)
	}
	return u
}

func clickModelName(kind byte) string {
	switch kind {
	case zwiftClickV1:
		return "Zwift Click"
	case zwiftClickV2Right:
		return "Zwift Click v2 (right, +)"
	case zwiftClickV2Left:
		return "Zwift Click v2 (left, -)"
	}
	return "Zwift controller"
}

// runClick connects to one Click and forwards its shifts until it disconnects.
func runClick(adapter *bluetooth.Adapter, d found, shifts chan<- int, debug bool) error {
	name := clickModelName(d.zwiftKind)
	device, err := adapter.Connect(d.address, bluetooth.ConnectionParams{})
	if err != nil {
		return err
	}
	defer device.Disconnect()

	services, err := device.DiscoverServices([]bluetooth.UUID{zwiftService})
	if err != nil || len(services) == 0 {
		return fmt.Errorf("%s: Zwift service not found - update its firmware in the Zwift Companion app", name)
	}
	chars, err := services[0].DiscoverCharacteristics([]bluetooth.UUID{zwiftAsync, zwiftSyncRx, zwiftSyncTx})
	if err != nil {
		return fmt.Errorf("%s: %w", name, err)
	}
	var rx *bluetooth.DeviceCharacteristic
	var edges shiftEdges
	onMessage := func(b []byte) {
		if debug {
			fmt.Printf("\n  [%s] % x\n", name, b)
		}
		if buttons, ok := ParseZwiftControllerMessage(b); ok {
			if delta := edges.update(buttons); delta != 0 {
				select { // never block the Bluetooth callback
				case shifts <- delta:
				default:
				}
			}
		}
	}
	for i := range chars {
		switch chars[i].UUID() {
		case zwiftAsync, zwiftSyncTx:
			if err := chars[i].EnableNotifications(onMessage); err != nil {
				return fmt.Errorf("%s: could not subscribe: %w", name, err)
			}
		case zwiftSyncRx:
			rx = &chars[i]
		}
	}
	if rx == nil {
		return fmt.Errorf("%s: handshake characteristic missing", name)
	}
	if _, err := rx.WriteWithoutResponse(rideOnGreeting); err != nil {
		if _, err := rx.Write(rideOnGreeting); err != nil {
			return fmt.Errorf("%s: handshake failed: %w", name, err)
		}
	}
	fmt.Printf("\n%s connected - press + / - to change gear.\n", name)

	for range time.Tick(2 * time.Second) {
		if ok, err := device.Connected(); err == nil && !ok {
			return fmt.Errorf("%s disconnected", name)
		}
	}
	return nil
}

// clickLoop keeps looking for Zwift Clicks and connects every usable one.
func clickLoop(adapter *bluetooth.Adapter, scanner *scanner, discovered <-chan []found, shifts chan<- int, onFirstClick func(), debug bool) {
	connected := map[string]bool{}
	disconnected := make(chan string)
	var warnedLeft bool
	connect := func(list []found) {
		for _, d := range list {
			key := d.address.String()
			if connected[key] {
				continue
			}
			if d.zwiftKind == zwiftClickV2Left {
				if !warnedLeft {
					warnedLeft = true
					fmt.Println("\nFound the LEFT puck of a Zwift Click v2. Zwift locks that puck to its own app,")
					fmt.Println("so use the RIGHT puck: + or Y = harder gear, B or Z = easier gear.")
				}
				continue
			}
			connected[key] = true
			onFirstClick()
			go func(d found, key string) {
				if err := runClick(adapter, d, shifts, debug); err != nil {
					fmt.Printf("\n%v\n", err)
				}
				disconnected <- key
			}(d, key)
		}
	}
	for {
		select {
		case list := <-discovered:
			connect(list)
		case key := <-disconnected:
			delete(connected, key)
		case <-time.After(20 * time.Second):
			if len(connected) == 0 {
				if list, err := scanner.scan("", false); err == nil {
					connect(list)
				}
			}
		}
	}
}
