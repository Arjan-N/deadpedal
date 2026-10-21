#!/usr/bin/env bash
# Runs every automated check: unit tests, solo runs of each mode, two-instance
# networked missions and the trainer bridge.
#
# Usage: tests/run_all_tests.sh [--quick] [godot-binary]
#   --quick   unit tests + one short run per game mode (well under a minute)
#
# Speed: single-player runs use Godot's --fixed-fps 60 - every frame is
# exactly 1/60 s of game time and the game runs as fast as the computer
# allows (~25x real time), with the same result every time. Tests run in
# parallel, one per CPU core. The multiplayer tests must run in real time
# (two copies of the game talking over the network), so they start first and
# run alongside the rest.
set -u
QUICK=0
if [ "${1:-}" = "--quick" ]; then QUICK=1; shift; fi
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
LOG_DIR=tests/output
RES_DIR="$LOG_DIR/results"
rm -rf "$RES_DIR"
mkdir -p "$RES_DIR"
JOBS=$(nproc 2> /dev/null || echo 4)
SOLO=("$GODOT" --headless --fixed-fps 60 --path .)
START=$SECONDS

result() {  # name expected actual
	if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (expected exit $2, got $3)"; fi
}

# Runs a test function in the background (at most $JOBS at once); its
# PASS/FAIL lines go to a results file, printed in order at the end.
run() {
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
	"$2" > "$RES_DIR/$1.txt" 2>&1 &
}

# --- Tests ---------------------------------------------------------------------

test_unit() {
	"$GODOT" --headless --path . res://tests/unit_tests.tscn > "$LOG_DIR/unit.log" 2>&1
	result "unit tests" 0 $?
}

test_story_strong() {
	"${SOLO[@]}" -- --solo --autopilot=230 --exit-on-results --quit-after=120 > "$LOG_DIR/solo_strong.log" 2>&1
	result "solo: strong rider escapes" 0 $?
}

test_story_weak() {
	"${SOLO[@]}" -- --solo --autopilot=90 --exit-on-results --quit-after=120 > "$LOG_DIR/solo_weak.log" 2>&1
	result "solo: weak rider is caught" 2 $?
}

test_story_replay() {
	"${SOLO[@]}" -- --solo --autopilot=60 --exit-on-results --replays=1 --quit-after=120 > "$LOG_DIR/solo_replay.log" 2>&1
	result "solo: replay restarts the mission" 2 $?
}

# Endless Survival: a rider who picks up survivors rides behind them until
# one is exhausted; then they're either rescued or taken by the horde. Fixed
# world seed; the run stops after 5 minutes of riding (exit 3) unless the
# horde wins first (exit 2).
test_endless() {
	local log="$LOG_DIR/endless_solo.log"
	"${SOLO[@]}" -- --solo --mode=endless --seed=7 --autopilot=150 --autopilot-pickup --autopilot-react=270 --exit-on-results --stop-at=300 --quit-after=150 > "$log" 2>&1
	local code=$?
	if { [ "$code" = 2 ] || [ "$code" = 3 ]; } && grep -q "Picked up" "$log" && grep -q "is exhausted" "$log" \
			&& grep -qE "taken by the horde|back with the group" "$log" && ! grep -q "SCRIPT ERROR" "$log"; then
		result "endless: survivors picked up, pull on the front, get exhausted" 0 0
	else
		result "endless: survivors picked up, pull on the front, get exhausted" 2 "$code"
	fi
}

# Criterium: a race to 5 points against 7 computer riders finishes with a
# winner, scoring every lap (the 5th, a bell lap, is worth 2). The test rider
# races like a computer rider of equal strength.
test_race() {
	local log="$LOG_DIR/race.log"
	"${SOLO[@]}" -- --solo --mode=race --seed=3 --race-points=5 --race-difficulty=1 --autopilot=150 --autopilot-race=sprinter --exit-on-results --quit-after=200 > "$log" 2>&1
	local code=$?
	if { [ "$code" = 0 ] || [ "$code" = 2 ]; } && grep -q "Lap 1 won by" "$log" && grep -q "WINNER" "$log" \
			&& ! grep -q "SCRIPT ERROR" "$log" && { ! grep -q "Lap 5 won" "$log" || grep -q "Lap 5 won by [A-Za-z]* (+2" "$log"; }; then
		result "criterium: race to 5 points finishes with a winner" 0 0
	else
		result "criterium: race to 5 points finishes with a winner" 0 1
	fi
}

# ...and against "harder" rivals it loses (exit code 2).
test_race_hard() {
	"${SOLO[@]}" -- --solo --mode=race --seed=11 --race-points=5 --race-difficulty=2 --autopilot=150 --autopilot-race=sprinter --exit-on-results --quit-after=200 > "$LOG_DIR/race_hard.log" 2>&1
	result "criterium: harder rivals beat an equal-strength rider" 2 $?
}

test_multiplayer() {
	local port=$((20000 + RANDOM % 20000))
	"$GODOT" --headless --path . -- --host --port=$port --auto-start=2 --name=Host --autopilot=220 --timescale=3 --exit-on-results --replays=1 --quit-after=200 > "$LOG_DIR/mp_host.log" 2>&1 &
	local host_pid=$!
	sleep 2
	"$GODOT" --headless --path . -- --join=127.0.0.1 --port=$port --name=Client --ftp=150 --autopilot=150 --timescale=3 --exit-on-results --replays=1 --quit-after=200 > "$LOG_DIR/mp_client.log" 2>&1
	local client=$?
	wait $host_pid
	local host=$?
	result "multiplayer: host completes mission twice" 0 $host
	result "multiplayer: client completes mission twice" 0 $client
	# Both machines must agree on every stage change.
	if diff <(grep -o "Stage -> [A-Z_]*" "$LOG_DIR/mp_host.log") <(grep -o "Stage -> [A-Z_]*" "$LOG_DIR/mp_client.log") > /dev/null; then
		result "multiplayer: identical mission state on both machines" 0 0
	else
		result "multiplayer: identical mission state on both machines" 0 1
	fi
}

# Endless multiplayer: both machines must see identical stages, checkpoints,
# pick-ups and losses (same world seed). The run is cut off by --quit-after,
# so the shorter of the two event lists is compared against the other.
test_endless_multiplayer() {
	local port=$((20000 + RANDOM % 20000))
	"$GODOT" --headless --path . -- --host --mode=endless --seed=7 --port=$port --auto-start=2 --autopilot=160 --autopilot-pickup --autopilot-react=300 --timescale=10 --exit-on-results --quit-after=110 > "$LOG_DIR/endless_host.log" 2>&1 &
	local host_pid=$!
	sleep 2
	"$GODOT" --headless --path . -- --join=127.0.0.1 --port=$port --ftp=170 --autopilot=140 --autopilot-react=270 --timescale=10 --exit-on-results --quit-after=110 > "$LOG_DIR/endless_client.log" 2>&1
	wait $host_pid
	local events="Stage -> [A-Z_]*|Checkpoint [0-9]* passed|Picked up [A-Za-z]*|Left [A-Za-z]* behind|[A-Za-z]* was taken|[A-Za-z]* is exhausted|[A-Za-z]* is back with the group|screamer went off|Sprinted past a screamer|Grabbed [a-z]*|Missed a crate|runner breaks|runner caught [A-Za-z]*"
	grep -oE "$events" "$LOG_DIR/endless_host.log" > "$LOG_DIR/endless_host.events"
	grep -oE "$events" "$LOG_DIR/endless_client.log" > "$LOG_DIR/endless_client.events"
	local h c n
	h=$(wc -l < "$LOG_DIR/endless_host.events")
	c=$(wc -l < "$LOG_DIR/endless_client.events")
	n=$((h < c ? h : c))
	if [ "$n" -gt 5 ] && diff <(head -n "$n" "$LOG_DIR/endless_host.events") <(head -n "$n" "$LOG_DIR/endless_client.events") > /dev/null \
			&& grep -q "Checkpoint" "$LOG_DIR/endless_client.events" && grep -q "Picked up" "$LOG_DIR/endless_client.events"; then
		result "endless multiplayer: identical world events on both machines ($n events)" 0 0
	else
		result "endless multiplayer: identical world events on both machines" 0 1
	fi
}

# Trainer bridge (Go): Bluetooth parsing unit tests and the Windows build.
test_bridge_build() {
	(cd tools/trainer_bridge && go test ./... > "../../$LOG_DIR/bridge_unit.log" 2>&1)
	result "trainer bridge: Bluetooth data parsing" 0 $?
	(cd tools/trainer_bridge && GOOS=windows GOARCH=amd64 go build -o DeadPedalTrainerBridge.exe . > "../../$LOG_DIR/bridge_build.log" 2>&1)
	result "trainer bridge: Windows .exe builds" 0 $?
	(cd tools/trainer_bridge && go build -o "../../$LOG_DIR/bridge" .)
}

# Bridge (simulate mode) -> UDP -> game, riding a full mission. Runs last, on
# its own: it needs the trainer data port (UDP 47800) to itself.
test_bridge_game() {
	"$LOG_DIR/bridge" -simulate < /dev/null > "$LOG_DIR/bridge.log" 2>&1 &
	local bridge_pid=$!
	sleep 1
	"$GODOT" --headless --path . -- --solo --input=trainer --timescale=4 --exit-on-results --quit-after=150 > "$LOG_DIR/bridge_game.log" 2>&1
	result "trainer bridge: game rides a mission on bridge data" 0 $?
	kill $bridge_pid 2> /dev/null
}

# --- Run -------------------------------------------------------------------------

"$GODOT" --headless --path . --import > /dev/null 2>&1

if [ "$QUICK" = 1 ]; then
	run 01 test_unit
	run 02 test_story_strong
	run 05 test_endless
	run 06 test_race
	wait
else
	# Slowest (real-time) tests first, so they overlap everything else.
	run 08 test_multiplayer
	run 09 test_endless_multiplayer
	run 01 test_unit
	run 02 test_story_strong
	run 03 test_story_weak
	run 04 test_story_replay
	run 05 test_endless
	run 06 test_race
	run 07 test_race_hard
	if command -v go > /dev/null; then
		run 10 test_bridge_build
	fi
	wait
	if command -v go > /dev/null; then
		test_bridge_game > "$RES_DIR/11.txt" 2>&1
	fi
fi

cat "$RES_DIR"/*.txt
PASS=$(cat "$RES_DIR"/*.txt | grep -c "^PASS")
FAIL=$(cat "$RES_DIR"/*.txt | grep -c "^FAIL")
echo ""
echo "$PASS passed, $FAIL failed in $((SECONDS - START)) s (logs in $LOG_DIR/)"
[ "$FAIL" -eq 0 ]
