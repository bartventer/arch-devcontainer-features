#!/usr/bin/env bash

set -euo pipefail

# This script generates a lockfile for the specified tools using the Arch Linux package manager (pacman).

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <package1> <package2> ... <packageN>"
  exit 1
fi

pacman -Si "$@" | awk -F ': ' -v dq='"' '
  BEGIN { print "[ " }
  NF == 2 && $1 ~ /^(Name|Version)/ {
    key = tolower($1)
    value = $2
    gsub(/ /, "", key)
    gsub(/ /, "", value)
    if (key == "name") {
      if (n > 0) { print " }," }  # Close the previous object
      printf "  { "
      n++
    } else {
      printf ", "
    }
    printf "%s%s%s: %s%s%s", dq, key, dq, dq, value, dq
  }
  END { print " } ]" }
' | jq 'map(. + { versionScheme: "archlinux" }) | sort_by(.name)'
