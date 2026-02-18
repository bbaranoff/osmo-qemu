#!/bin/bash
# launch_calypso.sh — Direct layer1 boot (no loader needed)
QEMU=qemu-system-arm
FIRMWARE=${1:-~/compal_e88/layer1.highram.elf}
MONSOCK=/tmp/qemu-calypso-mon.sock
LOGFILE=/tmp/qemu-calypso.log
rm -f "$MONSOCK" "$LOGFILE"
killall -q qemu-system-arm 2>/dev/null
sleep 0.3

echo "=== Starting QEMU Calypso with direct layer1 ==="
$QEMU -M calypso \
  -kernel "$FIRMWARE" \
  -serial pty \
  -monitor unix:$MONSOCK,server,nowait \
  >"$LOGFILE" 2>&1 &
QEMU_PID=$!

PTS=""
for i in $(seq 1 50); do
    [ -f "$LOGFILE" ] && PTS=$(grep -o '/dev/pts/[0-9]*' "$LOGFILE" | head -1)
    [ -n "$PTS" ] && break
    sleep 0.1
done
if [ -z "$PTS" ]; then
    echo "ERROR: Could not find QEMU pty"
    cat "$LOGFILE" 2>/dev/null
    kill $QEMU_PID 2>/dev/null
    exit 1
fi
echo "=== QEMU pty: $PTS ==="
echo "=== QEMU PID: $QEMU_PID ==="
echo "=== Monitor: socat - UNIX-CONNECT:$MONSOCK ==="

# Start osmocon as sercomm<->L1CTL bridge
sleep 0.5
echo "=== Starting osmocon (sercomm bridge) on $PTS ==="
osmocon -p "$PTS" -m c123xor >"$LOGFILE.osmocon" 2>&1 &
OSMO_PID=$!

echo "=== L1CTL socket: /tmp/osmocom_l2 ==="
echo "=== Press Ctrl+C to stop ==="
trap "kill $QEMU_PID $OSMO_PID 2>/dev/null; rm -f $MONSOCK; exit" INT TERM
wait $QEMU_PID 2>/dev/null
kill $OSMO_PID 2>/dev/null
rm -f "$MONSOCK"
