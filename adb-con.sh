#!/bin/bash

IP="192.168.178.56"
PORT="5555"

adb kill-server
adb start-server
adb connect $IP:$PORT
adb devices