// DEAD PEDAL trainer bridge.
//
// Connects to a Bluetooth smart trainer (e.g. Zwift Hub One, Wahoo KICKR,
// Tacx, Elite...) and forwards live power and cadence to the game over UDP on
// this computer (127.0.0.1:47800). The game's "Smart trainer" input reads it.
//
// Reads the standard Bluetooth profiles trainers broadcast:
//   - Fitness Machine Service (FTMS) Indoor Bike Data   (preferred)
//   - Cycling Power Service (CPS) Power Measurement     (fallback)
//
// It only reads data and never changes the trainer's resistance.
//
// Usage:
//
//	DeadPedalTrainerBridge.exe                 connect to the first trainer found
//	DeadPedalTrainerBridge.exe -name "Zwift"   only trainers whose name contains this
//	DeadPedalTrainerBridge.exe -list           list nearby trainers and exit
//	DeadPedalTrainerBridge.exe -simulate       fake data, no hardware (marked simulated)
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"math"
	"net"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"tinygo.org/x/bluetooth"
)

const (
	gameAddress = "127.0.0.1:47800"
	// The last reading is re-sent this often so the game knows we're alive.
	heartbeat = 250 * time.Millisecond
	// Readings older than this aren't forwarded (the trainer stopped sending).
	staleAfter = 3 * time.Second
	// Reconnect if the trainer sends nothing for this long.
	silenceTimeout = 10 * time.Second
	scanDuration   = 8 * time.Second
)

var (
	ftmsService    = bluetooth.New16BitUUID(0x1826)
	indoorBikeData = bluetooth.New16BitUUID(0x2AD2)
	cpsService     = bluetooth.New16BitUUID(0x1818)
	cpsMeasurement = bluetooth.New16BitUUID(0x2A63)
)

// gameLink holds the latest reading and sends it to the game.
type gameLink struct {
	mu        sync.Mutex
	conn      net.Conn
	device    string
	simulated bool
	power     float64
	cadence   float64
	updated   time.Time
}

func newGameLink(device string, simulated bool) (*gameLink, error) {
	conn, err := net.Dial("udp", gameAddress)
	if err != nil {
		return nil, err
	}
	l := &gameLink{conn: conn, device: device, simulated: simulated, cadence: -1}
	go func() {
		for range time.Tick(heartbeat) {
			l.send()
		}
	}()
	return l, nil
}

func (l *gameLink) update(r Reading) {
	l.mu.Lock()
	if r.HasPower {
		l.power = math.Max(r.Power, 0)
	}
	if r.HasCadence {
		l.cadence = r.Cadence
	}
	l.updated = time.Now()
	power, cadence := l.power, l.cadence
	l.mu.Unlock()
	l.send()
	cad := "  -- rpm"
	if cadence >= 0 {
		cad = fmt.Sprintf("%5.0f rpm", cadence)
	}
	fmt.Printf("\r  %5.0f W  %s   -> game on %s   ", power, cad, gameAddress)
}

func (l *gameLink) lastUpdate() time.Time {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.updated
}

func (l *gameLink) send() {
	l.mu.Lock()
	defer l.mu.Unlock()
	if time.Since(l.updated) > staleAfter {
		return
	}
	packet, _ := json.Marshal(map[string]any{
		"power":     math.Round(l.power*10) / 10,
		"cadence":   math.Round(l.cadence*10) / 10,
		"device":    l.device,
		"simulated": l.simulated,
	})
	_, _ = l.conn.Write(packet) // nobody listening yet is fine
}

// --- Scanning -----------------------------------------------------------------

type trainer struct {
	address bluetooth.Address
	name    string
	ftms    bool
	cps     bool
}

// scan listens for advertisements for scanDuration and returns devices that
// look like trainers. Name and services can arrive in separate packets, so
// everything seen per address is merged.
func scan(adapter *bluetooth.Adapter, nameFilter string) ([]trainer, error) {
	fmt.Printf("Scanning for trainers for %.0f s... (pedal to wake the trainer up)\n", scanDuration.Seconds())
	var mu sync.Mutex
	seen := map[string]*trainer{}
	go func() {
		time.Sleep(scanDuration)
		_ = adapter.StopScan()
	}()
	err := adapter.Scan(func(_ *bluetooth.Adapter, result bluetooth.ScanResult) {
		mu.Lock()
		defer mu.Unlock()
		key := result.Address.String()
		t, ok := seen[key]
		if !ok {
			t = &trainer{address: result.Address}
			seen[key] = t
		}
		if name := result.LocalName(); name != "" {
			t.name = name
		}
		t.ftms = t.ftms || result.HasServiceUUID(ftmsService)
		t.cps = t.cps || result.HasServiceUUID(cpsService)
	})
	if err != nil {
		return nil, err
	}
	mu.Lock()
	defer mu.Unlock()
	var found []trainer
	for _, t := range seen {
		looksLikeTrainer := t.ftms || t.cps || strings.Contains(strings.ToLower(t.name), "hub")
		if !looksLikeTrainer {
			continue
		}
		if nameFilter != "" && !strings.Contains(strings.ToLower(t.name), strings.ToLower(nameFilter)) {
			continue
		}
		if t.name == "" {
			t.name = t.address.String()
		}
		found = append(found, *t)
	}
	// Prefer FTMS trainers, then alphabetical for a stable choice.
	sort.Slice(found, func(i, j int) bool {
		if found[i].ftms != found[j].ftms {
			return found[i].ftms
		}
		return found[i].name < found[j].name
	})
	return found, nil
}

// --- Connecting ---------------------------------------------------------------

// ride connects to one trainer and forwards its data until it disconnects or
// goes silent.
func ride(adapter *bluetooth.Adapter, t trainer, link *gameLink) error {
	fmt.Printf("Connecting to %s (%s)...\n", t.name, t.address.String())
	device, err := adapter.Connect(t.address, bluetooth.ConnectionParams{})
	if err != nil {
		return err
	}
	defer device.Disconnect()

	link.mu.Lock()
	link.device = t.name
	link.mu.Unlock()
	services, err := device.DiscoverServices([]bluetooth.UUID{ftmsService, cpsService})
	if err != nil {
		return fmt.Errorf("reading the trainer's services: %w", err)
	}
	var subscribed string
	// FTMS first: it reports cadence directly.
	for _, wanted := range []bluetooth.UUID{ftmsService, cpsService} {
		for _, s := range services {
			if s.UUID() != wanted || subscribed != "" {
				continue
			}
			if wanted == ftmsService {
				subscribed, err = subscribe(s, indoorBikeData, "FTMS Indoor Bike Data", func(b []byte) {
					if r, err := ParseIndoorBikeData(b); err == nil {
						link.update(r)
					}
				})
			} else {
				var cad CrankCadence
				start := time.Now()
				subscribed, err = subscribe(s, cpsMeasurement, "Cycling Power", func(b []byte) {
					if r, err := ParseCyclingPower(b, &cad, time.Since(start).Seconds()); err == nil {
						link.update(r)
					}
				})
			}
			if err != nil {
				fmt.Printf("  (%v)\n", err)
			}
		}
	}
	if subscribed == "" {
		return errors.New("this device doesn't offer FTMS or Cycling Power data")
	}
	fmt.Printf("Connected using %s. Start DEAD PEDAL and choose 'Smart trainer'.\n", subscribed)
	fmt.Println("Leave this window open while you ride. Close it to stop.")

	connectedAt := time.Now()
	link.mu.Lock()
	link.updated = time.Time{} // ignore readings from a previous connection
	link.mu.Unlock()
	for range time.Tick(time.Second) {
		if ok, err := device.Connected(); err == nil && !ok {
			return errors.New("trainer disconnected")
		}
		last := link.lastUpdate()
		if last.IsZero() {
			last = connectedAt
		}
		if time.Since(last) > silenceTimeout {
			return errors.New("no data from the trainer for 10 s")
		}
	}
	return nil
}

func subscribe(s bluetooth.DeviceService, char bluetooth.UUID, label string, callback func([]byte)) (string, error) {
	chars, err := s.DiscoverCharacteristics([]bluetooth.UUID{char})
	if err != nil || len(chars) == 0 {
		return "", fmt.Errorf("%s not available", label)
	}
	if err := chars[0].EnableNotifications(callback); err != nil {
		return "", fmt.Errorf("could not subscribe to %s: %w", label, err)
	}
	return label, nil
}

func runBluetooth(nameFilter string, listOnly bool) error {
	adapter := bluetooth.DefaultAdapter
	if err := adapter.Enable(); err != nil {
		return fmt.Errorf("could not start Bluetooth (is it switched on?): %w", err)
	}
	link, err := newGameLink("trainer", false)
	if err != nil {
		return err
	}
	for {
		trainers, err := scan(adapter, nameFilter)
		if err != nil {
			return fmt.Errorf("scanning failed (is Bluetooth switched on?): %w", err)
		}
		if listOnly {
			if len(trainers) == 0 {
				fmt.Println("No trainers found.")
			}
			for _, t := range trainers {
				profile := "Cycling Power"
				if t.ftms {
					profile = "FTMS"
				}
				fmt.Printf("  %-30s %s   %s\n", t.name, t.address.String(), profile)
			}
			return nil
		}
		if len(trainers) == 0 {
			fmt.Println("No trainer found. Is it powered on and NOT connected to Zwift or another app?")
			fmt.Println("Retrying in 3 s...")
			time.Sleep(3 * time.Second)
			continue
		}
		if err := ride(adapter, trainers[0], link); err != nil {
			fmt.Printf("\n%v - reconnecting in 3 s...\n", err)
		}
		time.Sleep(3 * time.Second)
	}
}

// runSimulated sends fake data for testing without hardware. Every packet is
// marked "simulated", and the game labels it that way.
func runSimulated() error {
	link, err := newGameLink("Simulated trainer", true)
	if err != nil {
		return err
	}
	fmt.Println("SIMULATED trainer (no hardware). Sending fake power to the game.")
	start := time.Now()
	for range time.Tick(heartbeat) {
		t := time.Since(start).Seconds()
		link.update(Reading{
			Power: 190 + 40*math.Sin(t/6), HasPower: true,
			Cadence: 85 + 5*math.Sin(t/3), HasCadence: true,
		})
	}
	return nil
}

func main() {
	name := flag.String("name", "", "only connect to trainers whose name contains this text")
	list := flag.Bool("list", false, "list nearby trainers and exit")
	simulate := flag.Bool("simulate", false, "send fake data (no hardware needed)")
	flag.Parse()

	fmt.Println("DEAD PEDAL trainer bridge")
	var err error
	if *simulate {
		err = runSimulated()
	} else {
		err = runBluetooth(*name, *list)
	}
	if err != nil {
		fmt.Println("\nError:", err)
	}
	// Keep the window open when started by double-click, so the message can be read.
	fmt.Println("\nPress Enter to close.")
	_, _ = bufio.NewReader(os.Stdin).ReadString('\n')
}
