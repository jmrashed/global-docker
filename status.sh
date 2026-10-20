#!/usr/bin/env bash
# Show state, health and published ports of the shared stack, plus connection info.
set -euo pipefail
. "$(dirname "$0")/scripts/lib.sh"
SELECTED=("${ALL_SERVICES[@]}")

printf '%-12s %-32s %s\n' SERVICE STATUS PORTS
for s in "${ALL_SERVICES[@]}"; do
  out=$(docker ps -a --filter "label=com.docker.compose.project=global-$s" --format '{{.Status}}|{{.Ports}}')
  if [ -z "$out" ]; then printf '%-12s %-32s\n' "$s" "not created"; continue; fi
  while IFS='|' read -r st ports; do printf '%-12s %-32s %s\n' "$s" "$st" "$ports"; done <<< "$out"
done
echo; summary
