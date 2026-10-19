#!/usr/bin/env bash
# Runs every automated check: unit tests, solo success/failure runs and a
# two-instance networked mission. Usage: tests/run_all_tests.sh [godot-binary]
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
LOG_DIR=tests/output
mkdir -p "$LOG_DIR"
PASS=0
FAIL=0

result() {  # name expected actual
	if [ "$2" = "$3" ]; then echo "PASS  $1"; PASS=$((PASS + 1)); else echo "FAIL  $1 (expected exit $2, got $3)"; FAIL=$((FAIL + 1)); fi
}

"$GODOT" --headless --path . --import > /dev/null 2>&1

"$GODOT" --headless --path . res://tests/unit_tests.tscn > "$LOG_DIR/unit.log" 2>&1
result "unit tests" 0 $?

"$GODOT" --headless --path . -- --solo --autopilot=230 --timescale=6 --exit-on-results --quit-after=120 > "$LOG_DIR/solo_strong.log" 2>&1
result "solo: strong rider escapes" 0 $?

"$GODOT" --headless --path . -- --solo --autopilot=90 --timescale=6 --exit-on-results --quit-after=120 > "$LOG_DIR/solo_weak.log" 2>&1
result "solo: weak rider is caught" 2 $?

"$GODOT" --headless --path . -- --solo --autopilot=60 --timescale=6 --exit-on-results --replays=1 --quit-after=120 > "$LOG_DIR/solo_replay.log" 2>&1
result "solo: replay restarts the mission" 2 $?

# Endless Survival: a rider who picks up survivors loses one to the horde
# before being caught; the world seed is fixed so the run is repeatable.
"$GODOT" --headless --path . -- --solo --mode=endless --seed=42 --autopilot=125 --autopilot-pickup --timescale=10 --exit-on-results --quit-after=150 > "$LOG_DIR/endless_solo.log" 2>&1
CODE=$?
if [ "$CODE" = 2 ] && grep -q "Picked up" "$LOG_DIR/endless_solo.log" && grep -q "taken by the horde" "$LOG_DIR/endless_solo.log"; then
	result "endless: survivors picked up, one taken by the horde, then caught" 0 0
else
	result "endless: survivors picked up, one taken by the horde, then caught" 2 "$CODE"
fi

PORT=$((20000 + RANDOM % 20000))
"$GODOT" --headless --path . -- --host --port=$PORT --auto-start=2 --name=Host --autopilot=220 --timescale=3 --exit-on-results --replays=1 --quit-after=200 > "$LOG_DIR/mp_host.log" 2>&1 &
HOST_PID=$!
sleep 2
"$GODOT" --headless --path . -- --join=127.0.0.1 --port=$PORT --name=Client --ftp=150 --autopilot=150 --timescale=3 --exit-on-results --replays=1 --quit-after=200 > "$LOG_DIR/mp_client.log" 2>&1
CLIENT=$?
wait $HOST_PID
HOST=$?
result "multiplayer: host completes mission twice" 0 $HOST
result "multiplayer: client completes mission twice" 0 $CLIENT
# Both machines must agree on every stage change.
if diff <(grep -o "Stage -> [A-Z_]*" "$LOG_DIR/mp_host.log") <(grep -o "Stage -> [A-Z_]*" "$LOG_DIR/mp_client.log") > /dev/null; then
	result "multiplayer: identical mission state on both machines" 0 0
else
	result "multiplayer: identical mission state on both machines" 0 1
fi

# Endless multiplayer: both machines must see identical stages, checkpoints,
# pick-ups and losses (same world seed). The run is cut off by --quit-after,
# so the shorter of the two event lists is compared against the other.
PORT=$((20000 + RANDOM % 20000))
"$GODOT" --headless --path . -- --host --mode=endless --seed=7 --port=$PORT --auto-start=2 --autopilot=160 --autopilot-pickup --autopilot-react=300 --timescale=10 --exit-on-results --quit-after=110 > "$LOG_DIR/endless_host.log" 2>&1 &
HOST_PID=$!
sleep 2
"$GODOT" --headless --path . -- --join=127.0.0.1 --port=$PORT --ftp=170 --autopilot=140 --autopilot-react=270 --timescale=10 --exit-on-results --quit-after=110 > "$LOG_DIR/endless_client.log" 2>&1
wait $HOST_PID
EVENTS="Stage -> [A-Z_]*|Checkpoint [0-9]* passed|Picked up [A-Za-z]*|Left [A-Za-z]* behind|[A-Za-z]* was taken"
grep -oE "$EVENTS" "$LOG_DIR/endless_host.log" > "$LOG_DIR/endless_host.events"
grep -oE "$EVENTS" "$LOG_DIR/endless_client.log" > "$LOG_DIR/endless_client.events"
N=$(( $(wc -l < "$LOG_DIR/endless_host.events") < $(wc -l < "$LOG_DIR/endless_client.events") ? $(wc -l < "$LOG_DIR/endless_host.events") : $(wc -l < "$LOG_DIR/endless_client.events") ))
if [ "$N" -gt 5 ] && diff <(head -n "$N" "$LOG_DIR/endless_host.events") <(head -n "$N" "$LOG_DIR/endless_client.events") > /dev/null \
		&& grep -q "Checkpoint" "$LOG_DIR/endless_client.events" && grep -q "Picked up" "$LOG_DIR/endless_client.events"; then
	result "endless multiplayer: identical world events on both machines ($N events)" 0 0
else
	result "endless multiplayer: identical world events on both machines" 0 1
fi

# Trainer bridge (Go): Bluetooth parsing unit tests, Windows build, then
# bridge (simulate mode) -> UDP -> game, riding a full mission.
if command -v go > /dev/null; then
	(cd tools/trainer_bridge && go test ./... > "../../$LOG_DIR/bridge_unit.log" 2>&1)
	result "trainer bridge: Bluetooth data parsing" 0 $?
	(cd tools/trainer_bridge && GOOS=windows GOARCH=amd64 go build -o DeadPedalTrainerBridge.exe . > "../../$LOG_DIR/bridge_build.log" 2>&1)
	result "trainer bridge: Windows .exe builds" 0 $?
	(cd tools/trainer_bridge && go build -o "../../$LOG_DIR/bridge" .)
	"$LOG_DIR/bridge" -simulate < /dev/null > "$LOG_DIR/bridge.log" 2>&1 &
	BRIDGE_PID=$!
	sleep 1
	"$GODOT" --headless --path . -- --solo --input=trainer --timescale=4 --exit-on-results --quit-after=150 > "$LOG_DIR/bridge_game.log" 2>&1
	result "trainer bridge: game rides a mission on bridge data" 0 $?
	kill $BRIDGE_PID 2> /dev/null
fi

echo ""
echo "$PASS passed, $FAIL failed (logs in $LOG_DIR/)"
[ "$FAIL" -eq 0 ]
