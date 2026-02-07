#!/bin/bash
# Debug Multiplayer Launcher
# Launches a server + N clients and tails all logs for debugging
#
# Usage:
#   ./debug_multiplayer.sh              # 1 server + 1 client
#   ./debug_multiplayer.sh 3            # 1 server + 3 clients
#   ./debug_multiplayer.sh 3 farmhouse  # 1 server + 3 clients on farmhouse
#   ./debug_multiplayer.sh stop         # Kill all instances

set -e

GODOT="./Godot_v4.5.1-stable_linux.x86_64"
LOG_DIR="/tmp/zvh_debug"
PORT=7777
NUM_CLIENTS="${1:-1}"
MAP="${2:-nacht}"

# --- Stop command ---
if [ "$1" = "stop" ] || [ "$1" = "kill" ]; then
    echo "Stopping all Zombies vs Humans instances..."
    pkill -f "Godot.*zvh_debug" 2>/dev/null && echo "Killed." || echo "Nothing running."
    rm -rf "$LOG_DIR"
    exit 0
fi

# --- Validate ---
if [ ! -f "$GODOT" ]; then
    echo "ERROR: Godot binary not found at $GODOT"
    echo "Run this script from the project root directory."
    exit 1
fi

if ! [[ "$NUM_CLIENTS" =~ ^[0-9]+$ ]] || [ "$NUM_CLIENTS" -lt 1 ] || [ "$NUM_CLIENTS" -gt 5 ]; then
    echo "Usage: $0 [num_clients 1-5] [map_name]"
    echo "       $0 stop"
    exit 1
fi

# --- Setup ---
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"

echo "============================================"
echo "  Zombies vs Humans - Multiplayer Debug"
echo "============================================"
echo "  Server:  port $PORT, map '$MAP'"
echo "  Clients: $NUM_CLIENTS"
echo "  Logs:    $LOG_DIR/"
echo "============================================"
echo ""

# --- Launch server ---
echo "[*] Starting server..."
$GODOT --position 0,0 -- --server --port "$PORT" --map "$MAP" --name "Host" \
    > "$LOG_DIR/server.log" 2>&1 &
SERVER_PID=$!
echo "    PID: $SERVER_PID -> $LOG_DIR/server.log"

# Wait for server to initialize
sleep 2

# Check server is still alive
if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "ERROR: Server crashed on startup! Log:"
    cat "$LOG_DIR/server.log"
    exit 1
fi

# --- Launch clients ---
CLIENT_PIDS=()
for i in $(seq 1 "$NUM_CLIENTS"); do
    echo "[*] Starting client $i..."
    # Offset window position so they don't stack
    X_POS=$((960 * ((i - 1) % 2)))
    Y_POS=$((540 * ((i - 1) / 2)))
    $GODOT --position "$X_POS","$Y_POS" -- --join 127.0.0.1 --port "$PORT" --name "Player_$i" \
        > "$LOG_DIR/client_$i.log" 2>&1 &
    CLIENT_PIDS+=($!)
    echo "    PID: ${CLIENT_PIDS[-1]} -> $LOG_DIR/client_$i.log"
    sleep 1
done

echo ""
echo "============================================"
echo "  All instances launched!"
echo "============================================"
echo ""
echo "Commands:"
echo "  tail -f $LOG_DIR/server.log        # Watch server log"
echo "  tail -f $LOG_DIR/client_1.log      # Watch client 1 log"
echo "  tail -f $LOG_DIR/*.log             # Watch all logs"
echo "  $0 stop                            # Kill everything"
echo ""
echo "Watching all logs (Ctrl+C to stop watching, instances keep running):"
echo "--------------------------------------------"

# Tail all logs with prefixed filenames
tail -f "$LOG_DIR"/*.log 2>/dev/null | while IFS= read -r line; do
    echo "$line"
done
