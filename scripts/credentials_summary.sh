#!/bin/bash
# List where credentials live per service (databases, redis, livekit).
# Usage: ./credentials_summary.sh [--show] [--paths-only]
#   --show       print secret values (use with care)
#   --paths-only print only .env paths (for scripting)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHOW_VALS=false
PATHS_ONLY=false
for arg in "$@"; do
  [ "$arg" = "--show" ] && SHOW_VALS=true
  [ "$arg" = "--paths-only" ] && PATHS_ONLY=true
done

if [ "$PATHS_ONLY" = true ]; then
  for d in "$ROOT/databases" "$ROOT/redis" "$ROOT/livekit" "$ROOT/minio" "$ROOT/elasticsearch" "$ROOT/meilisearch"; do
    [ ! -d "$d" ] && continue
    for dir in "$d"/*/; do
      [ -d "$dir" ] && [ -f "${dir}.env" ] && echo "${dir}.env"
    done
  done
  exit 0
fi

echo "=== Credentials per service ==="
echo "All secrets are stored in each instance's .env file. Central env files (databases.env, redis.env, livekit.env, minio.env, elasticsearch.env, meilisearch.env) also contain secrets."
echo ""

# Databases (Supabase)
if [ -f "$ROOT/databases.env" ]; then
  echo "--- Databases (Supabase) ---"
  while IFS='|' read -r name rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ "$name" == "DASHBOARD_USERNAME" ]] && break
    env_file="$ROOT/databases/$name/.env"
    if [ -f "$env_file" ]; then
      echo "  $name: $env_file"
      echo "    Keys: POSTGRES_PASSWORD, JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY, DATABASE_URL, POOLER_URL, STUDIO_URL, ..."
      if [ "$SHOW_VALS" = true ]; then
        grep -E "^(POSTGRES_PASSWORD|JWT_SECRET|ANON_KEY|SERVICE_ROLE_KEY|DATABASE_URL|POOLER_URL|STUDIO_URL)=" "$env_file" 2>/dev/null | sed 's/^/    /'
      fi
    else
      echo "  $name: (no .env yet – run generate or re-add)"
    fi
  done < <(grep -E "^[a-zA-Z0-9-]+\|" "$ROOT/databases.env" 2>/dev/null || true)
  echo ""
fi

# Redis
if [ -f "$ROOT/redis.env" ]; then
  echo "--- Redis ---"
  while IFS='|' read -r name port cpu memory password rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ ! "$port" =~ ^[0-9]+$ ]] && continue
    env_file="$ROOT/redis/$name/.env"
    if [ -f "$env_file" ]; then
      echo "  $name: $env_file (port $port)"
      echo "    Keys: REDIS_PORT, REDIS_PASSWORD (if set), REDIS_URL"
      if [ "$SHOW_VALS" = true ]; then
        grep -E "^(REDIS_PORT|REDIS_PASSWORD|REDIS_URL)=" "$env_file" 2>/dev/null | sed 's/^/    /'
      fi
    else
      echo "  $name: $ROOT/redis/$name/ (port $port) – add REDIS_PORT, REDIS_URL to .env if needed"
    fi
  done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$ROOT/redis.env" 2>/dev/null || true)
  echo ""
fi

# LiveKit
if [ -f "$ROOT/livekit.env" ]; then
  echo "--- LiveKit ---"
  while IFS='|' read -r name http_port rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue
    env_file="$ROOT/livekit/$name/.env"
    if [ -f "$env_file" ]; then
      echo "  $name: $env_file (HTTP port $http_port)"
      echo "    Keys: LIVEKIT_URL, LIVEKIT_HTTP_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET"
      if [ "$SHOW_VALS" = true ]; then
        grep -E "^(LIVEKIT_URL|LIVEKIT_HTTP_URL|LIVEKIT_API_KEY|LIVEKIT_API_SECRET)=" "$env_file" 2>/dev/null | sed 's/^/    /'
      fi
    else
      echo "  $name: (no .env yet – run generate or re-add)"
    fi
  done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$ROOT/livekit.env" 2>/dev/null || true)
  echo ""
fi

# MinIO
if [ -f "$ROOT/minio.env" ]; then
  echo "--- MinIO ---"
  while IFS='|' read -r name api_port rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ ! "$api_port" =~ ^[0-9]+$ ]] && continue
    env_file="$ROOT/minio/$name/.env"
    if [ -f "$env_file" ]; then
      echo "  $name: $env_file (API $api_port)"
      echo "    Keys: MINIO_ENDPOINT, MINIO_CONSOLE_URL, MINIO_ROOT_USER, MINIO_ROOT_PASSWORD"
      if [ "$SHOW_VALS" = true ]; then
        grep -E "^(MINIO_ENDPOINT|MINIO_CONSOLE_URL|MINIO_ROOT_USER|MINIO_ROOT_PASSWORD)=" "$env_file" 2>/dev/null | sed 's/^/    /'
      fi
    else
      echo "  $name: (no .env yet – run generate or re-add)"
    fi
  done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$ROOT/minio.env" 2>/dev/null || true)
  echo ""
fi

# Elasticsearch
if [ -f "$ROOT/elasticsearch.env" ]; then
  echo "--- Elasticsearch ---"
  while IFS='|' read -r name http_port rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue
    env_file="$ROOT/elasticsearch/$name/.env"
    if [ -f "$env_file" ]; then
      echo "  $name: $env_file (HTTP $http_port)"
      echo "    Keys: ELASTICSEARCH_URL, ELASTIC_USER, ELASTIC_PASSWORD"
      if [ "$SHOW_VALS" = true ]; then
        grep -E "^(ELASTICSEARCH_URL|ELASTIC_USER|ELASTIC_PASSWORD)=" "$env_file" 2>/dev/null | sed 's/^/    /'
      fi
    else
      echo "  $name: (no .env yet – run generate or re-add)"
    fi
  done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$ROOT/elasticsearch.env" 2>/dev/null || true)
  echo ""
fi

# Meilisearch
if [ -f "$ROOT/meilisearch.env" ]; then
  echo "--- Meilisearch ---"
  while IFS='|' read -r name http_port rest; do
    [[ "$name" =~ ^#.*$ ]] && continue
    [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]] && continue
    [[ ! "$http_port" =~ ^[0-9]+$ ]] && continue
    env_file="$ROOT/meilisearch/$name/.env"
    if [ -f "$env_file" ]; then
      echo "  $name: $env_file (HTTP $http_port)"
      echo "    Keys: MEILISEARCH_URL, MEILI_MASTER_KEY"
      if [ "$SHOW_VALS" = true ]; then
        grep -E "^(MEILISEARCH_URL|MEILI_MASTER_KEY)=" "$env_file" 2>/dev/null | sed 's/^/    /'
      fi
    else
      echo "  $name: (no .env yet – run generate or re-add)"
    fi
  done < <(grep -E "^[a-zA-Z0-9-]+\|[0-9]+" "$ROOT/meilisearch.env" 2>/dev/null || true)
  echo ""
fi

echo "Summary: Use the paths above. Run with --paths-only to list only .env paths. Run with --show to print values (keep secure)."
