#!/usr/bin/env bash
# Shared helpers for start.sh / stop.sh / status.sh. Source it, do not execute it.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

UI_SERVICES=(phpmyadmin pgadmin)      # skipped by --no-ui
ALL_SERVICES=(); for _d in services/*/; do ALL_SERVICES+=("$(basename "$_d")"); done; unset _d

# Container ids (running or not) belonging to the compose project of a service.
ctrs() { docker ps -aq --filter "label=com.docker.compose.project=global-$1"; }

# compose <service> <args...>   (runs in the service folder with the shared .env)
compose() { local s=$1; shift; (cd "services/$s" && docker compose --env-file ../../.env "$@"); }

has() { [[ " ${SELECTED[*]} " == *" $1 "* ]]; }

# Print connection info for the SELECTED services, from the ports recorded in .ports.env.
summary() {
  [ -f .ports.env ] || return 0
  ( set -a; . ./.ports.env
    sfx=""; [ "${TRAEFIK_PORT:-80}" != 80 ] && sfx=":$TRAEFIK_PORT"
    has mysql      && echo "MySQL       127.0.0.1:$MYSQL_PORT   (root)"
    has postgresql && echo "PostgreSQL  127.0.0.1:$POSTGRES_PORT   (postgres)"
    has redis      && echo "Redis       127.0.0.1:$REDIS_PORT   (password = ADMIN_PASSWORD, no username)"
    has mailpit    && echo "Mailpit     SMTP 127.0.0.1:$MAILPIT_SMTP_PORT   UI http://127.0.0.1:$MAILPIT_UI_PORT"
    has phpmyadmin && echo "phpMyAdmin  http://127.0.0.1:$PHPMYADMIN_PORT"
    has pgadmin    && echo "pgAdmin     http://127.0.0.1:$PGADMIN_PORT"
    if has traefik; then
      echo "Traefik     http://traefik.localhost$sfx  (proxy listens on 127.0.0.1:$TRAEFIK_PORT)"
      has mailpit    && echo "            http://mailpit.localhost$sfx"
      has phpmyadmin && echo "            http://phpmyadmin.localhost$sfx"
      has pgadmin    && echo "            http://pgadmin.localhost$sfx"
    fi
    true )
}
