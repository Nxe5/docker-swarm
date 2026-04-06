# Config and credentials

## Root layout (clean)

- **`databases.env`** – Supabase DB list and global config (ports, secrets, JWT, etc.).
- **`redis.env`** – Redis instance list (name, port, cpu, memory, password).
- **`livekit.env`** – LiveKit instance list (name, ports, api key/secret, etc.).
- **`minio.env`** – MinIO instance list (name, api port, cpu, memory, root user/password).
- **`elasticsearch.env`** – Elasticsearch instance list (name, http port, cpu, memory, elastic password).
- **`meilisearch.env`** – Meilisearch instance list (name, http port, cpu, memory, master key).
- **`port_registry.env`** – Single source of truth for **all** allocated ports (db, redis, livekit, minio, elasticsearch, meilisearch). Do not edit by hand.
- **`db_manager.sh`**, **`container_manager.sh`** – Wrappers that run `scripts/db_manager.sh` and `scripts/container_manager.sh`.
- **`scripts/`** – All management logic (db, redis, livekit, minio, elasticsearch, meilisearch, helpers, port allocator).
- **`helpers/`** – Legacy helpers only (e.g. detect_changes, parse_databases_env). Compose generators live in `scripts/helpers/`.
- **`databases/`**, **`redis/`**, **`livekit/`**, **`minio/`**, **`elasticsearch/`**, **`meilisearch/`** – One folder per instance; each has its own `docker-compose.yml` and **`.env`** with credentials and URLs. **Git ignores** everything under those directories except each directory’s **`.gitkeep`** so generated compose and secrets are never committed.

## How we avoid port and “domain” conflicts

- **Ports:** Every add (db, redis, livekit, minio, elasticsearch, meilisearch) goes through the **port allocator** (`scripts/helpers/port_allocator.sh`). It reads and updates **`port_registry.env`** so that:
  - Postgres, Kong HTTP/HTTPS, pooler, Redis, LiveKit HTTP/TCP/UDP, MinIO API/console, Elasticsearch HTTP, Meilisearch HTTP each get the next free port or range.
  - No port is allocated twice (same or different service).
- **Domains:** Everything is **localhost** with different ports (e.g. `http://localhost:8000`, `redis://localhost:6379`, `ws://localhost:7880`). There are no hostnames to clash; only ports matter, and those are tracked in the registry.
- **Check for conflicts:** Run:
  ```bash
  ./container_manager.sh validate-ports
  ```
  This checks `port_registry.env` for duplicate ports and reports any conflict.

## Where credentials live (and how to track them)

| Service      | Per-instance credentials   | Central config (also has secrets)   |
|-------------|-----------------------------|--------------------------------------|
| Supabase    | `databases/<name>/.env`     | `databases.env` (pipe-delimited rows) |
| Redis       | `redis/<name>/.env`         | `redis.env` (pipe-delimited rows)     |
| LiveKit     | `livekit/<name>/.env`       | `livekit.env` (pipe-delimited rows)   |
| MinIO       | `minio/<name>/.env`         | `minio.env` (pipe-delimited rows)     |
| Elasticsearch | `elasticsearch/<name>/.env` | `elasticsearch.env` (pipe-delimited) |
| Meilisearch | `meilisearch/<name>/.env`   | `meilisearch.env` (pipe-delimited)    |

- **Supabase:** `.env` has `POSTGRES_PASSWORD`, `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`, `DATABASE_URL`, `POOLER_URL`, `STUDIO_URL`, etc.
- **Redis:** `.env` has `REDIS_PORT`, `REDIS_PASSWORD` (if set), `REDIS_URL`.
- **LiveKit:** `.env` has `LIVEKIT_URL`, `LIVEKIT_HTTP_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`.
- **MinIO:** `.env` has `MINIO_ENDPOINT`, `MINIO_CONSOLE_URL`, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`.
- **Elasticsearch:** `.env` has `ELASTICSEARCH_URL`, `ELASTIC_USER`, `ELASTIC_PASSWORD`.
- **Meilisearch:** `.env` has `MEILISEARCH_URL`, `MEILI_MASTER_KEY`.

**List and track credentials:**

```bash
# Where credentials live (paths and variable names; no secret values)
./container_manager.sh show-credentials

# Only list .env file paths
./container_manager.sh show-credentials --paths-only

# Print secret values (use with care, avoid sharing output)
./container_manager.sh show-credentials --show
```

New services get their `.env` when you add them. Keep these `.env` files out of version control (they are listed in `.gitignore`).
