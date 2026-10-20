#!/usr/bin/env bash
# Start the shared local stack.
# Usage: ./start.sh [--no-ui] [--recreate] [service ...]
#   services : mysql postgresql redis mailpit phpmyadmin pgadmin traefik   (default: all)
#   --no-ui    skip phpmyadmin and pgadmin
#   --recreate re-apply compose config even if containers already exist
# Host ports start from .env; if one is taken or reserved by Windows the next free port is used.
# Ports of containers that are already running are kept. Services start in parallel.
set -euo pipefail
. "$(dirname "$0")/scripts/lib.sh"

UI=1; RECREATE=0; SELECTED=()
for a in "$@"; do
  case $a in
    --no-ui) UI=0 ;;
    --recreate) RECREATE=1 ;;
    -*) echo "Unknown option: $a"; exit 2 ;;
    *) [ -d "services/$a" ] || { echo "Unknown service: $a (available: ${ALL_SERVICES[*]})"; exit 2; }
       SELECTED+=("$a") ;;
  esac
done
if [ ${#SELECTED[@]} -eq 0 ]; then
  for s in "${ALL_SERVICES[@]}"; do
    [ $UI -eq 0 ] && [[ " ${UI_SERVICES[*]} " == *" $s "* ]] && continue
    SELECTED+=("$s")
  done
fi

# Host ports: VAR, container, container port, default host port.
# Defaults can be overridden in .env; the next free port is used when one is taken.
PORTS=(
  "MYSQL_PORT        mysql      3306 3306"
  "POSTGRES_PORT     postgres   5432 5432"
  "REDIS_PORT        redis      6379 6379"
  "MAILPIT_SMTP_PORT mailpit    1025 1025"
  "MAILPIT_UI_PORT   mailpit    8025 8025"
  "PHPMYADMIN_PORT   phpmyadmin 80   8080"
  "PGADMIN_PORT      pgadmin    80   5050"
  "TRAEFIK_PORT      traefik    80   80"
)

# ---- progress bar ----
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
STEP=0; TOTAL=$((1 + ${#PORTS[@]} + ${#SELECTED[@]} + 1))   # prepare + ports + services + health wait
show() {
  local w=30 f=$((STEP * 30 / TOTAL))
  printf '\r\033[K[%s%s] %3d%%  step %d/%d, %d left  %s' \
    "$(printf '%*s' "$f" '' | tr ' ' '#')" "$(printf '%*s' $((w - f)) '' | tr ' ' '-')" \
    $((STEP * 100 / TOTAL)) "$STEP" "$TOTAL" $((TOTAL - STEP)) "$1"
}
step() { STEP=$((STEP + 1)); }
fail() { echo; echo "FAILED: $1"; [ -f "${2:-}" ] && cat "$2"; exit 1; }

# ---- preflight ----
show "preparing"
[ -f .env ] || { cp .env.example .env; echo; echo "Created .env - set ADMIN_PASSWORD, then re-run."; exit 1; }
set -a; . ./.env; set +a
[ "${ADMIN_PASSWORD:-change_me}" != "change_me" ] || { echo; echo "Set a real ADMIN_PASSWORD in .env first."; exit 1; }
docker info >/dev/null 2>&1 || { echo; echo "Docker is not running."; exit 1; }
docker network inspect global-net >/dev/null 2>&1 || docker network create global-net >/dev/null

# ---- fast path: every selected service already has containers (just stopped) ----
IDS=(); FAST=1
for s in "${SELECTED[@]}"; do
  mapfile -t c < <(ctrs "$s"); [ ${#c[@]} -gt 0 ] || { FAST=0; break; }
  IDS+=("${c[@]}")
done
if [ $RECREATE -eq 0 ] && [ $FAST -eq 1 ] && ! docker inspect -f '{{.State.Status}}' "${IDS[@]}" | grep -qx created; then
  TOTAL=2; STEP=1; show "starting ${SELECTED[*]}"
  docker start "${IDS[@]}" >"$TMP/start.log" 2>&1 || fail "docker start" "$TMP/start.log"
  STEP=2; show "done"; echo; echo
  summary; exit 0
fi
step

# ---- ports ----
# ONE PowerShell call lists every port in the candidate windows that Windows will not let us bind
# (already listening, or inside a reserved/excluded range).
BLOCKED=""; PROBED=0
probe() {
  [ $PROBED -eq 1 ] && return; PROBED=1
  local expr="" row v d b
  for row in "${PORTS[@]}"; do
    read -r v _ _ d <<< "$row"; b=${!v:-$d}
    expr+="(${b}..$((b + 200)))+"
  done
  BLOCKED=" $(powershell.exe -NoProfile -Command "foreach(\$p in ${expr%+}){try{\$l=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,\$p);\$l.Start();\$l.Stop()}catch{\$p}}" 2>/dev/null | tr -d '\r' | tr '\n' ' ') "
}
in_use() { [[ "$BLOCKED" == *" $1 "* ]] || (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

CHOSEN=" "
pick() { # VAR container container_port default
  local var=$1 ctr=$2 cport=$3 want=${!1:-$4} cur
  show "choosing port for $var"
  cur=$(docker port "$ctr" "$cport/tcp" 2>/dev/null | head -1 | sed 's/.*://' || true)
  if [ -n "$cur" ]; then
    want=$cur
  else
    probe
    while in_use "$want" || [[ "$CHOSEN" == *" $want "* ]]; do want=$((want + 1)); done
  fi
  CHOSEN+="$want "
  export "$var=$want"
  step
}

for row in "${PORTS[@]}"; do
  read -r v c p d <<< "$row"
  pick "$v" "$c" "$p" "$d"
done

# ---- start services in parallel ----
declare -A PID
for s in "${SELECTED[@]}"; do
  compose "$s" up -d >"$TMP/$s.log" 2>&1 &
  PID[$!]=$s
done
while [ ${#PID[@]} -gt 0 ]; do
  show "starting: ${PID[*]} (first run pulls images)"
  for p in "${!PID[@]}"; do
    kill -0 "$p" 2>/dev/null && continue
    svc=${PID[$p]}
    wait "$p" || fail "$svc" "$TMP/$svc.log"
    unset "PID[$p]"; step
  done
  sleep 0.3
done

for row in "${PORTS[@]}"; do read -r v _ <<< "$row"; echo "$v=${!v}"; done > .ports.env

# ---- wait for healthchecks (1s polling, 2 min cap) ----
IDS=(); for s in "${SELECTED[@]}"; do IDS+=($(ctrs "$s")); done
for i in $(seq 1 120); do
  ok=1
  for c in "${IDS[@]}"; do
    st=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}healthy{{end}}' "$c")
    [ "$st" = healthy ] || ok=0
  done
  show "waiting for healthchecks (${i}s)"
  [ $ok -eq 1 ] && break; sleep 1
done
step; show "done"; echo; echo
summary
