# Test layout

Tests live under `test/` with **one folder per area**. Add and run tests as you develop.

## Folders and current tests

| Folder | Area | Tests |
|--------|------|--------|
| `test/databases/` | Supabase DB | `test_db_manager_show_ports.sh` (smoke) |
| `test/redis/` | Redis | `test_redis_manager_show_ports.sh` (smoke) |
| `test/livekit/` | LiveKit | `test_livekit_manager_show_ports.sh` (smoke) |
| `test/port_allocator/` | Port registry | `test_port_allocator_basic.sh`, `test_validate_ports_*.sh` |
| `test/container_manager/` | Central manager | `test_show_commands.sh` (show-ports, show-credentials, validate-ports) |

## Running tests

From project root:

- Run one area: `./test/databases/run.sh` or `./test/port_allocator/run.sh`
- Run all areas: `./test/run_all.sh`

If needed: `chmod +x test/run_all.sh test/*/run.sh test/*/test_*.sh`

Each area has a `run.sh` that runs every `test_*.sh` in that folder. Prefer **shell** tests (`test_*.sh`) or **pytest** per area; keep one runner per folder.

## Conventions

- One runner per area: `run.sh` (or `run_tests.sh`) in each area folder.
- Tests should not mutate production env; use temp dirs or a dedicated test env file where needed.
- Naming: `test_<thing>.sh` or `test_<thing>.py` so it’s clear what is under test.
