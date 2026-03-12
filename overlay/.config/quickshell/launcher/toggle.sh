#!/bin/bash
PID_FILE="/tmp/qs-launcher.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        rm -f "$PID_FILE"
        exit 0
    fi
    rm -f "$PID_FILE"
fi

/usr/bin/quickshell -c launcher &
echo $! > "$PID_FILE"
