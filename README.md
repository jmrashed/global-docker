# global-docker

Shared local **MySQL 8.4**, **PostgreSQL 17**, **Redis 7**, **Mailpit**, **phpMyAdmin**, **pgAdmin** and a **Traefik** reverse proxy for every project on this machine. One admin password (`ADMIN_PASSWORD` in `.env`) is used for MySQL `root`, PostgreSQL `postgres`, Redis and pgAdmin. Each service has its own compose file and folder.

```
global-docker/
├── start.sh              start the stack (progress bar, auto ports, parallel)
├── stop.sh               stop the stack (or remove containers with --down)
├── status.sh             state, health, ports and connection info
├── scripts/lib.sh        helpers shared by the three scripts
├── .env                  ADMIN_PASSWORD + default host ports (git-ignored)
├── .env.example          template for .env
├── .ports.env            ports actually chosen by start.sh (generated, git-ignored)
├── .gitignore  .gitattributes  .editorconfig
└── services/             one folder + one compose file per service
    ├── mysql/            MySQL 8.4            + init/01-example.sql
    ├── postgresql/       PostgreSQL 17        + init/01-example.sql
    ├── redis/            Redis 7 (password, AOF persistence)
    ├── mailpit/          Mailpit (SMTP + web UI)
    ├── phpmyadmin/       phpMyAdmin (talks to the "mysql" container)
    ├── pgadmin/          pgAdmin (talks to the "postgres" container)
    └── traefik/          Reverse proxy: http://<name>.localhost -> container
```

Adding a service means adding a folder under `services/` with a `docker-compose.yml` that has `name: global-<folder>` and joins the external `global-net` network. The scripts pick it up automatically.

## Quick start (Git Bash)

```bash
cd /e/laragon/www/global-docker
cp .env.example .env          # first time only, then set ADMIN_PASSWORD
./start.sh                    # all services, with progress bar
./status.sh                   # what is running, on which ports
./stop.sh                     # stop (containers + data kept, restart takes ~2s)
```

| Command | What it does |
|---|---|
| `./start.sh` | Start everything. If the containers already exist it just restarts them (about 2 seconds, same ports). |
| `./start.sh --no-ui` | Skip phpMyAdmin and pgAdmin |
| `./start.sh mysql mailpit` | Start only the named services (`mysql postgresql redis mailpit phpmyadmin pgadmin traefik`) |
| `./start.sh --recreate` | Re-apply the compose files, for example after editing one. Data volumes are kept. |
| `./status.sh` | Show state, health, published ports and connection info |
| `./stop.sh [service ...]` | Stop containers, keep them and all data |
| `./stop.sh --down [service ...]` | Remove the containers too (volumes and data are kept) |

All ports bind to `127.0.0.1` only, so nothing is exposed to your LAN. Every service has `restart: unless-stopped`, so they come back on their own when Docker Desktop starts.

### Automatic ports

Default host ports come from `.env`. If one is already in use **or reserved by Windows** (3306 is often inside a Windows excluded range), `start.sh` picks the next free one. The result is printed at the end and saved in **`.ports.env`**. Check it for the ports to use from the host:

```bash
cat .ports.env
```

| Service | Default host port | Container port (use this between containers) |
|---|---|---|
| MySQL | 3306 | 3306 |
| PostgreSQL | 5432 | 5432 |
| Redis | 6379 | 6379 |
| Mailpit SMTP | 1025 | 1025 |
| Mailpit UI | 8025 | 8025 |
| phpMyAdmin | 8080 | 80 |
| pgAdmin | 5050 | 80 |
| Traefik (HTTP proxy) | 80 | 80 |

---

## Sample logins

Replace `<ADMIN_PASSWORD>` with the value in `.env`. Replace `<port>` placeholders with the value from `.ports.env` (the default if it was free).

### MySQL

| | From your machine (Laragon PHP, DBeaver, CLI) | From another container on `global-net` |
|---|---|---|
| Host | `127.0.0.1` | `mysql` |
| Port | `<MYSQL_PORT>` (default 3306) | `3306` |
| User | `root` | `root` |
| Password | `<ADMIN_PASSWORD>` | `<ADMIN_PASSWORD>` |

```bash
# inside the container (no password typing)
docker exec -it mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"'

# from the host with a local client
mysql -h 127.0.0.1 -P <MYSQL_PORT> -u root -p

# connection URL
mysql://root:<ADMIN_PASSWORD>@127.0.0.1:<MYSQL_PORT>/myapp
```

Sample project user created by `services/mysql/init/01-example.sql`: database `example_app`, user `example_app`, password `example_app_secret`. It is a throwaway example, so **change or delete it**.

### PostgreSQL

| | From your machine | From another container on `global-net` |
|---|---|---|
| Host | `127.0.0.1` | `postgres` |
| Port | `<POSTGRES_PORT>` (default 5432) | `5432` |
| User | `postgres` | `postgres` |
| Password | `<ADMIN_PASSWORD>` | `<ADMIN_PASSWORD>` |

```bash
docker exec -it postgres psql -U postgres

# host client
psql -h 127.0.0.1 -p <POSTGRES_PORT> -U postgres

# connection URL
postgresql://postgres:<ADMIN_PASSWORD>@127.0.0.1:<POSTGRES_PORT>/myapp
```

Sample project role from `services/postgresql/init/01-example.sql`: database `example_app`, role `example_app`, password `example_app_secret` (throwaway, change or delete).

### Redis

| | From your machine | From another container on `global-net` |
|---|---|---|
| Host | `127.0.0.1` | `redis` |
| Port | `<REDIS_PORT>` (default 6379) | `6379` |
| Username | none (default user) | none |
| Password | `<ADMIN_PASSWORD>` | `<ADMIN_PASSWORD>` |

```bash
docker exec -it redis redis-cli              # already authenticated inside the container
redis-cli -h 127.0.0.1 -p <REDIS_PORT> -a '<ADMIN_PASSWORD>'
# connection URL
redis://:<ADMIN_PASSWORD>@127.0.0.1:<REDIS_PORT>/0
```

Data is persisted (AOF) and capped at 512 MB. The eviction policy is `volatile-lru`, so only keys with a TTL (cache) are evicted. Queues and sessions without a TTL are never dropped. Share one instance between projects by giving each its own database index (`REDIS_DB`, `REDIS_CACHE_DB`) or `REDIS_PREFIX` / `CACHE_PREFIX`.

### Mailpit (catches all outgoing mail, nothing is delivered)

| | Host | Port |
|---|---|---|
| Web UI | http://127.0.0.1:`<MAILPIT_UI_PORT>` (default 8025) | no login |
| SMTP from your machine | `127.0.0.1` | `<MAILPIT_SMTP_PORT>` (default 1025) |
| SMTP from a container | `mailpit` | `1025` |

No username, password or encryption is needed, and any SMTP auth is accepted. Send a test mail:

```bash
curl --url smtp://127.0.0.1:<MAILPIT_SMTP_PORT> --mail-from a@test.local --mail-rcpt b@test.local \
     -T - <<< $'Subject: hello\n\nTest body'
```

Then open the web UI to see it. Mailpit keeps up to 5000 messages, persisted in a volume.

### phpMyAdmin: http://127.0.0.1:`<PHPMYADMIN_PORT>` (default 8080)

- Server: `mysql` (automatic)
- Username: `root`
- Password: `<ADMIN_PASSWORD>`

### pgAdmin: http://127.0.0.1:`<PGADMIN_PORT>` (default 5050)

1. Log in with email `admin@example.com` (`PGADMIN_EMAIL` in `.env`) and password `<ADMIN_PASSWORD>`.
2. **Add New Server**:
   - General > Name: `global-postgres`
   - Connection > Host: `postgres`, Port: `5432`, Maintenance DB: `postgres`, Username: `postgres`, Password: `<ADMIN_PASSWORD>` (tick *Save password*)

pgAdmin runs inside the Docker network, so use the host `postgres` and port `5432` there, not the host-published port.

### Traefik dashboard: http://traefik.localhost

No login. It lists every router and service that Traefik has discovered. Handy to check that a project's labels were picked up. The web UIs are also reachable through the proxy:

| Service | Direct | Through the proxy |
|---|---|---|
| Mailpit | http://127.0.0.1:8025 | http://mailpit.localhost |
| phpMyAdmin | http://127.0.0.1:8080 | http://phpmyadmin.localhost |
| pgAdmin | http://127.0.0.1:5050 | http://pgadmin.localhost |

If port 80 was taken (Laragon's web server often uses it) Traefik moves to the next free port. Then add it to the URL, for example `http://mailpit.localhost:81`. Check `.ports.env` (`TRAEFIK_PORT`) or run `./status.sh`.

---

## Use from your projects

### Laravel on the host (Laragon PHP)

```dotenv
DB_CONNECTION=mysql              # or pgsql
DB_HOST=127.0.0.1
DB_PORT=3306                     # your <MYSQL_PORT>; for pgsql your <POSTGRES_PORT> (5432)
DB_DATABASE=myapp
DB_USERNAME=root                 # pgsql: postgres
DB_PASSWORD=<ADMIN_PASSWORD>

MAIL_MAILER=smtp
MAIL_HOST=127.0.0.1
MAIL_PORT=1025                   # your <MAILPIT_SMTP_PORT>
MAIL_USERNAME=null
MAIL_PASSWORD=null
MAIL_ENCRYPTION=null

REDIS_CLIENT=phpredis            # or predis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379                  # your <REDIS_PORT>
REDIS_PASSWORD=<ADMIN_PASSWORD>
REDIS_DB=0
REDIS_CACHE_DB=1
CACHE_STORE=redis
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
```

### Project running in its own Docker Compose

Join the shared network and use the service names and **container** ports:

```yaml
services:
  app:
    # ...
    networks: [default, global-net]
networks:
  global-net:
    external: true
```

```dotenv
DB_HOST=mysql        # or postgres
DB_PORT=3306         # or 5432
MAIL_HOST=mailpit
MAIL_PORT=1025
REDIS_HOST=redis
REDIS_PORT=6379
```

### Give a project a URL through Traefik

Add `global-net` and four labels to the container that serves HTTP. No ports need to be published, and there is no hosts-file entry or port to remember:

```yaml
services:
  web:
    image: nginx:alpine
    networks: [default, global-net]
    labels:
      - traefik.enable=true
      - traefik.http.routers.myapp.rule=Host(`myapp.localhost`)
      - traefik.http.routers.myapp.entrypoints=web
      - traefik.http.services.myapp.loadbalancer.server.port=80   # port the app listens on INSIDE the container
networks:
  global-net:
    external: true
```

Then open http://myapp.localhost. Router names (`myapp`) must be unique across all projects. Without `traefik.enable=true` a container is ignored. Apps that run on the host (Laragon) are not proxied, so keep using Laragon's own virtual hosts for those.

## Add a database for a new project

Quick way, with the admin account:

```bash
docker exec mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"'
docker exec postgres psql -U postgres -c "CREATE DATABASE myapp"
```

Dedicated user per project (recommended for shared use):

```bash
docker exec mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER \"myapp\"@\"%\" IDENTIFIED BY \"s3cret\"; GRANT ALL ON myapp.* TO \"myapp\"@\"%\""'
docker exec postgres psql -U postgres -c "CREATE ROLE myapp LOGIN PASSWORD 's3cret'" -c "ALTER DATABASE myapp OWNER TO myapp"
```

Files in `services/*/init/` run **only once**, when the data volume is first created. They are for bootstrapping, not for later changes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Container stuck in *Created*, error `forbidden by its access permissions` | The port is in a Windows reserved range. Run `./start.sh`, it picks a free port. |
| `Set ADMIN_PASSWORD in .env` | Run compose through `./start.sh`, or add `--env-file ../../.env` when running `docker compose` inside a `services/<name>` folder. |
| Can't connect on 3306 or 1025 from the host | Check `.ports.env`. The host port may have been moved (for example MySQL 3355). |
| phpMyAdmin can't connect | MySQL must be running (`docker ps`). phpMyAdmin talks to the container name `mysql`. |
| `network global-net not found` | `docker network create global-net` (`start.sh` does this automatically). |
| Logs | `docker logs -f mysql` (also `postgres`, `mailpit`, `phpmyadmin`, `pgadmin`) |

## Change the password or reset

Changing `ADMIN_PASSWORD` in `.env` does **not** change existing databases. Change it in place:

```bash
docker exec mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "ALTER USER \"root\"@\"%\" IDENTIFIED BY \"NEW\"; ALTER USER \"root\"@\"localhost\" IDENTIFIED BY \"NEW\""'
docker exec postgres psql -U postgres -c "ALTER USER postgres PASSWORD 'NEW'"
```

Then update `.env` and recreate the containers with `./stop.sh --down && ./start.sh`. For pgAdmin, also remove its volume (`docker volume rm global-pgadmin_pgadmin_data`) so it picks up the new password.

**Full reset, destroys all data:**

```bash
./stop.sh --down
docker volume rm global-mysql_mysql_data global-postgresql_postgres_data global-pgadmin_pgadmin_data global-mailpit_mailpit_data global-redis_redis_data
./start.sh
```
