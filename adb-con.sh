#!/bin/bash

IP="192.168.178.56"
PORT="5555"

# 1. Restart the server (optional but clean)
adb kill-server
adb start-server

# 2. Tell the USB-connected device to listen on port 5555
# This only needs to be run once after the device reboots
echo "Switching device to TCP/IP mode..."
adb tcpip $PORT

# 3. Give it a second to initialize
sleep 2

# 4. Connect wirelessly
echo "Connecting to $IP..."
adb connect $IP:$PORT

# 5. Show status
adb devices