#!/bin/sh

# Memory Used ≈ Activity Monitor: App Memory (anonymous) + Wired + Compressed.
# Same cost as before: one `vm_stat` + one `sysctl`, every update_freq seconds.

PAGE_SIZE=$(pagesize)
TOTAL_BYTES=$(sysctl -n hw.memsize)

eval "$(vm_stat | awk -v ps="$PAGE_SIZE" -v total="$TOTAL_BYTES" '
  /Anonymous pages/ {
    gsub(/\./, "", $NF)
    anon = $NF
  }
  /Pages wired down/ {
    gsub(/\./, "", $NF)
    wired = $NF
  }
  /Pages occupied by compressor/ {
    gsub(/\./, "", $NF)
    comp = $NF
  }
  END {
    used = (anon + wired + comp) * ps
    printf "USED_GB=%.1f TOTAL_GB=%.0f PCT=%.0f\n",
           used / 1073741824,
           total / 1073741824,
           (used * 100) / total
  }
')"

sketchybar --set "${NAME:-ram}" label="${PCT}% ${USED_GB}/${TOTAL_GB}G"
