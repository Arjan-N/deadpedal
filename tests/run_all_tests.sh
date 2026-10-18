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

echo ""
echo "$PASS passed, $FAIL failed (logs in $LOG_DIR/)"
[ "$FAIL" -eq 0 ]
