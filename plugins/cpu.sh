#!/bin/sh

# CPU busy percent averaged across cores (fast, no top delay)
NCPU=$(sysctl -n hw.ncpu)
CPU=$(ps -A -o %cpu | awk -v n="$NCPU" '{s+=$1} END {printf "%.0f", (n>0)?s/n:0}')

sketchybar --set "$NAME" label="${CPU}%"
