#!/bin/sh
set -e
alembic upgrade head
# One worker: SQLite requires it (D6); scale Postgres installs by running more containers.
exec uvicorn copycore.app:create_app --factory --host 0.0.0.0 --port "${PORT:-8000}" --workers 1 \
  --proxy-headers --no-server-header
