# Copy Server image (design D7): python:3.12-slim, non-root, migrations on start.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/app/.venv

COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /usr/local/bin/uv

WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY copycore ./copycore
COPY migrations ./migrations
COPY alembic.ini docker-entrypoint.sh ./
RUN uv sync --frozen --no-dev \
 && useradd --system --uid 10001 --no-create-home copy \
 && mkdir -p /data && chown copy /data

ENV PATH=/app/.venv/bin:$PATH \
    DATABASE_URL=sqlite:////data/copy.db \
    PORT=8000
USER copy
VOLUME ["/data"]
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD python -c "import os,urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ[\"PORT\"]}/healthz', timeout=3)"
ENTRYPOINT ["./docker-entrypoint.sh"]
