#!/bin/bash

# Add to GNOME Startup Applications
# - Open Startup Applications (gnome-session-properties)
# - Click Add
# - Name: Conky Monitor
# - Command: ~/.config/conky/conky_starter.sh

# Path to the conky binary
CONKY_BIN="/usr/bin/conky"

# Interval in seconds to check if Conky is still running
CHECK_INTERVAL=30

# Logging + clean log at startup
LOG_FILE="$HOME/.conky_manager.log"
rm -f "$LOG_FILE"; touch "$LOG_FILE"
echo "***** $(date): Start of $0" >> "$LOG_FILE"

# Function to start Conky
start_conky() {
    echo "$(date): Starting conky..." >> "$LOG_FILE"
    nohup $CONKY_BIN >> "$LOG_FILE" 2>&1 &
}

# Kill extra instances if more than one is running
kill_extra_conkys() {
    local pids
    pids=($(pgrep -x conky))
    if [ ${#pids[@]} -gt 1 ]; then
        echo "***** $(date): Multiple conky instances found. Killing extras..." >> "$LOG_FILE"
        for ((i=1; i<${#pids[@]}; i++)); do
            kill "${pids[$i]}"
        done
    fi
}

# Start conky initially
start_conky

# Keep script running and monitoring
while true; do
    sleep $CHECK_INTERVAL

    # Check if conky is running
    if ! pgrep -x conky > /dev/null; then
        echo "$(date): Conky is not running. Restarting..." >> "$LOG_FILE"
        start_conky
    else
        kill_extra_conkys
    fi
done
