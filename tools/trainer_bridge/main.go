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
// Virtual gears: if a Zwift Click is found, its buttons change gear and the
// bridge sets the trainer's resistance to match (FTMS simulation mode). Without
// a Click, the bridge only reads data and never changes the trainer.
//
// Usage:
//
//	DeadPedalTrainerBridge.exe                 connect to the first trainer found
//	DeadPedalTrainerBridge.exe -name "Zwift"   only trainers whose name contains this
//	DeadPedalTrainerBridge.exe -list           list nearby trainers and Clicks, then exit
//	DeadPedalTrainerBridge.exe -simulate       fake data, no hardware (marked simulated)
//	DeadPedalTrainerBridge.exe -debug          print raw Click / trainer-control messages
//	DeadPedalTrainerBridge.exe -gears=false    ignore Zwift Clicks
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
	"os/signal"
	"sort"
	"strings"
	"sync"
	"syscall"
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
	gear      int // 0 = no virtual gears (no Click connected)
	gears     int
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
	l.mu.Unlock()
	l.send()
	l.printStatus()
}

func (l *gameLink) setGear(gear, gears int) {
	l.mu.Lock()
	l.gear, l.gears = gear, gears
	l.mu.Unlock()
	l.send()
	l.printStatus()
}

func (l *gameLink) printStatus() {
	l.mu.Lock()
	power, cadence, gear, gears := l.power, l.cadence, l.gear, l.gears
	l.mu.Unlock()
	cad := "  -- rpm"
	if cadence >= 0 {
		cad = fmt.Sprintf("%5.0f rpm", cadence)
	}
	gearText := ""
	if gears > 0 {
		gearText = fmt.Sprintf("  gear %2d/%d", gear, gears)
	}
	fmt.Printf("\r  %5.0f W  %s%s   -> game on %s   ", power, cad, gearText, gameAddress)
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
		"gear":      l.gear,
		"gears":     l.gears,
	})
	_, _ = l.conn.Write(packet) // nobody listening yet is fine
}

// --- Scanning -----------------------------------------------------------------

// found is a device seen while scanning: a trainer, or a Zwift controller.
type found struct {
	address   bluetooth.Address
	name      string
	ftms      bool
	cps       bool
	zwiftKind byte // Zwift manufacturer data type (0 = not a Zwift controller)
}

func (f found) isTrainer() bool { return f.ftms || f.cps }
func (f found) isClick() bool {
	return f.zwiftKind == zwiftClickV1 || f.zwiftKind == zwiftClickV2Right || f.zwiftKind == zwiftClickV2Left
}

// scanner serialises scans: the adapter can only run one at a time.
type scanner struct {
	mu      sync.Mutex
	adapter *bluetooth.Adapter
}

// scan listens for advertisements for scanDuration. Name, services and
// manufacturer data can arrive in separate packets, so everything seen per
// address is merged.
func (s *scanner) scan(nameFilter string, verbose bool) ([]found, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if verbose {
		fmt.Printf("Scanning for %.0f s... (pedal to wake the trainer up)\n", scanDuration.Seconds())
	}
	var mu sync.Mutex
	seen := map[string]*found{}
	go func() {
		time.Sleep(scanDuration)
		_ = s.adapter.StopScan()
	}()
	err := s.adapter.Scan(func(_ *bluetooth.Adapter, result bluetooth.ScanResult) {
		mu.Lock()
		defer mu.Unlock()
		key := result.Address.String()
		f, ok := seen[key]
		if !ok {
			f = &found{address: result.Address}
			seen[key] = f
		}
		if name := result.LocalName(); name != "" {
			f.name = name
		}
		f.ftms = f.ftms || result.HasServiceUUID(ftmsService)
		f.cps = f.cps || result.HasServiceUUID(cpsService)
		for _, m := range result.ManufacturerData() {
			if m.CompanyID == zwiftCompanyID && len(m.Data) > 0 {
				f.zwiftKind = m.Data[0]
			}
		}
	})
	if err != nil {
		return nil, err
	}
	mu.Lock()
	defer mu.Unlock()
	var list []found
	for _, f := range seen {
		if f.name == "" {
			f.name = f.address.String()
		}
		if f.isClick() {
			list = append(list, *f)
			continue
		}
		looksLikeTrainer := f.isTrainer() || strings.Contains(strings.ToLower(f.name), "hub")
		if !looksLikeTrainer {
			continue
		}
		if nameFilter != "" && !strings.Contains(strings.ToLower(f.name), strings.ToLower(nameFilter)) {
			continue
		}
		list = append(list, *f)
	}
	// Prefer FTMS trainers, then alphabetical for a stable choice.
	sort.Slice(list, func(i, j int) bool {
		if list[i].ftms != list[j].ftms {
			return list[i].ftms
		}
		return list[i].name < list[j].name
	})
	return list, nil
}

// --- Trainer ------------------------------------------------------------------

// ride connects to one trainer and forwards its data until it disconnects or
// goes silent.
func ride(adapter *bluetooth.Adapter, t found, link *gameLink, control *trainerControl) error {
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

	// The FTMS control point lets the virtual gears set the resistance.
	if control != nil {
		for _, s := range services {
			if s.UUID() != ftmsService {
				continue
			}
			if chars, err := s.DiscoverCharacteristics([]bluetooth.UUID{ftmsControlPoint}); err == nil && len(chars) > 0 {
				control.attach(chars[0])
				defer control.detach()
			}
		}
	}

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

type options struct {
	name      string
	list      bool
	gears     bool
	gearCount int
	neutral   int
	gearStep  float64
	debug     bool
}

func runBluetooth(opt options) error {
	adapter := bluetooth.DefaultAdapter
	if err := adapter.Enable(); err != nil {
		return fmt.Errorf("could not start Bluetooth (is it switched on?): %w", err)
	}
	sc := &scanner{adapter: adapter}

	if opt.list {
		devices, err := sc.scan(opt.name, true)
		if err != nil {
			return fmt.Errorf("scanning failed (is Bluetooth switched on?): %w", err)
		}
		if len(devices) == 0 {
			fmt.Println("No trainers or Zwift Clicks found.")
		}
		for _, d := range devices {
			kind := "Cycling Power trainer"
			switch {
			case d.isClick():
				kind = clickModelName(d.zwiftKind)
			case d.ftms:
				kind = "FTMS trainer"
			}
			fmt.Printf("  %-30s %s   %s\n", d.name, d.address.String(), kind)
		}
		return nil
	}

	link, err := newGameLink("trainer", false)
	if err != nil {
		return err
	}

	// Virtual gears: Click presses -> gearbox -> trainer resistance + game HUD.
	var control *trainerControl
	discoveredClicks := make(chan []found, 1)
	if opt.gears {
		control = &trainerControl{debug: opt.debug}
		gearbox := NewGearbox(opt.gearCount, opt.neutral, opt.gearStep)
		shifts := make(chan int, 16)
		go func() {
			for delta := range shifts {
				if gear, changed := gearbox.Shift(delta); changed {
					link.setGear(gear, gearbox.Count())
					control.setGrade(gearbox.Grade())
				}
			}
		}()
		onClick := func() {
			link.setGear(gearbox.Gear(), gearbox.Count())
			control.activate(gearbox.Grade())
		}
		go clickLoop(adapter, sc, discoveredClicks, shifts, onClick, opt.debug)

		// Put the trainer back on the flat when the window is closed.
		quit := make(chan os.Signal, 1)
		signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
		go func() {
			<-quit
			control.release()
			os.Exit(0)
		}()
	}

	for {
		devices, err := sc.scan(opt.name, true)
		if err != nil {
			return fmt.Errorf("scanning failed (is Bluetooth switched on?): %w", err)
		}
		var trainers, clicks []found
		for _, d := range devices {
			if d.isClick() {
				clicks = append(clicks, d)
			} else {
				trainers = append(trainers, d)
			}
		}
		if len(clicks) > 0 && opt.gears {
			select {
			case discoveredClicks <- clicks:
			default:
			}
		}
		if len(trainers) == 0 {
			fmt.Println("No trainer found. Is it powered on and NOT connected to Zwift or another app?")
			fmt.Println("Retrying in 3 s...")
			time.Sleep(3 * time.Second)
			continue
		}
		if err := ride(adapter, trainers[0], link, control); err != nil {
			fmt.Printf("\n%v - reconnecting in 3 s...\n", err)
		}
		time.Sleep(3 * time.Second)
	}
}

// runSimulated sends fake data for testing without hardware. Every packet is
// marked "simulated", and the game labels it that way. The gear also changes
// every few seconds so the in-game gear display can be checked.
func runSimulated() error {
	link, err := newGameLink("Simulated trainer", true)
	if err != nil {
		return err
	}
	fmt.Println("SIMULATED trainer (no hardware). Sending fake power to the game.")
	start := time.Now()
	for range time.Tick(heartbeat) {
		t := time.Since(start).Seconds()
		link.mu.Lock()
		link.gear, link.gears = 8+int(t/6)%6, 24
		link.mu.Unlock()
		link.update(Reading{
			Power: 190 + 40*math.Sin(t/6), HasPower: true,
			Cadence: 85 + 5*math.Sin(t/3), HasCadence: true,
		})
	}
	return nil
}

func main() {
	var opt options
	flag.StringVar(&opt.name, "name", "", "only connect to trainers whose name contains this text")
	flag.BoolVar(&opt.list, "list", false, "list nearby trainers and Zwift Clicks, then exit")
	flag.BoolVar(&opt.gears, "gears", true, "use a Zwift Click to change virtual gears")
	flag.IntVar(&opt.gearCount, "gear-count", 24, "number of virtual gears")
	flag.IntVar(&opt.neutral, "neutral-gear", 8, "the gear that feels like a flat road")
	flag.Float64Var(&opt.gearStep, "gear-step", 0.4, "extra simulated slope (%) per gear")
	flag.BoolVar(&opt.debug, "debug", false, "print raw Zwift Click and trainer-control messages")
	simulate := flag.Bool("simulate", false, "send fake data (no hardware needed)")
	flag.Parse()

	fmt.Println("DEAD PEDAL trainer bridge")
	var err error
	if *simulate {
		err = runSimulated()
	} else {
		err = runBluetooth(opt)
	}
	if err != nil {
		fmt.Println("\nError:", err)
	}
	// Keep the window open when started by double-click, so the message can be read.
	fmt.Println("\nPress Enter to close.")
	_, _ = bufio.NewReader(os.Stdin).ReadString('\n')
}
