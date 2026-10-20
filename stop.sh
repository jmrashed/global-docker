#!/usr/bin/env bash
# Stop the shared local stack.
# Usage: ./stop.sh [--down] [service ...]
#   (default)  stop containers; they and all data are kept, ./start.sh brings them back in ~2s
#   --down     also remove the containers (named volumes / data are kept)
set -euo pipefail
. "$(dirname "$0")/scripts/lib.sh"

DOWN=0; SELECTED=()
for a in "$@"; do
  case $a in
    --down) DOWN=1 ;;
    -*) echo "Unknown option: $a"; exit 2 ;;
    *) [ -d "services/$a" ] || { echo "Unknown service: $a (available: ${ALL_SERVICES[*]})"; exit 2; }
       SELECTED+=("$a") ;;
  esac
done
[ ${#SELECTED[@]} -eq 0 ] && SELECTED=("${ALL_SERVICES[@]}")

for s in "${SELECTED[@]}"; do
  if [ $DOWN -eq 1 ]; then
    compose "$s" down 2>&1 | sed "s/^/[$s] /"
  else
    mapfile -t ids < <(ctrs "$s")
    [ ${#ids[@]} -gt 0 ] && docker stop "${ids[@]}" >/dev/null && echo "[$s] stopped"
  fi
done
true
